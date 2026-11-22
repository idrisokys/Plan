//! Disk işlemleri: ~/Link altındaki klasör/.url/.txt dosyalarını okur ve yazar.
//! Tüm yazma işlemleri tek bir kilitle sıralanır.

use crate::entry::{has_ext, Entry};
use crate::text::{self, clean, collapse_ws, extract_url, host_of, nfc, norm};
use std::collections::HashSet;
use std::fs;
use std::io;
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::{Mutex, MutexGuard};

pub const ORDER: &str = ".order.txt";
/// Sabitlenen öğelerin adları (yalnızca bu cihazda, eşitlenmez).
pub const PINNED: &str = ".pinned.txt";
/// Gönderilen metnin sınırı: bunu aşan (tek parça link olmayan) metin .txt olur.
pub const ADD_MAX: usize = 116;

static LOCK: Mutex<()> = Mutex::new(());
fn lock() -> MutexGuard<'static, ()> {
    LOCK.lock().unwrap_or_else(|e| e.into_inner())
}

static COUNTER: AtomicU64 = AtomicU64::new(0);
/// Geçici dosya adları için kısa benzersiz son ek.
pub fn unique_suffix() -> String {
    let n = COUNTER.fetch_add(1, Ordering::Relaxed);
    let t = std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).map(|d| d.subsec_nanos()).unwrap_or(0);
    format!("{:x}{:x}{:x}", std::process::id(), t, n)
}

// MARK: - Kök klasör

pub fn home_dir() -> PathBuf {
    std::env::var_os("HOME").or_else(|| std::env::var_os("USERPROFILE")).map(PathBuf::from).unwrap_or_else(|| PathBuf::from("."))
}

/// Varsayılan veri klasörü: <ana dizin>/Link (PLAN_ROOT ile değiştirilebilir).
pub fn default_root() -> PathBuf {
    std::env::var_os("PLAN_ROOT").map(PathBuf::from).unwrap_or_else(|| home_dir().join("Link"))
}

fn usable(p: &Path) -> bool {
    match fs::metadata(p) {
        Ok(m) => m.is_dir() && !m.permissions().readonly(),
        Err(_) => false,
    }
}

/// Kök klasör (gerekirse oluşturulur). Oluşturulamaz ya da yazılamazsa None.
pub fn root() -> Option<PathBuf> {
    let d = default_root();
    if !usable(&d) {
        let _ = fs::create_dir_all(&d);
        if !usable(&d) {
            return None;
        }
    }
    Some(d)
}

/// Ana dizindeki gizli .onemsiz klasörü ("Sil" öğeleri buraya taşır).
pub fn onemsiz_dir() -> PathBuf {
    home_dir().join(".onemsiz")
}

// MARK: - Yardımcılar

/// Yarım yazılmış dosya kalmasın diye önce geçici dosyaya yazıp yeniden adlandırır.
pub fn atomic_write(path: &Path, data: &[u8]) -> io::Result<()> {
    let dir = path.parent().unwrap_or_else(|| Path::new("."));
    let tmp = dir.join(format!(".tmp-{}", unique_suffix()));
    if let Err(e) = fs::write(&tmp, data) {
        let _ = fs::remove_file(&tmp);
        return Err(e);
    }
    fs::rename(&tmp, path).map_err(|e| {
        let _ = fs::remove_file(&tmp);
        e
    })
}

fn children(dir: &Path) -> Vec<Entry> {
    let Ok(rd) = fs::read_dir(dir) else { return vec![] };
    rd.filter_map(|r| r.ok())
        .map(|e| {
            let name = e.file_name().to_string_lossy().into_owned();
            let path = e.path();
            let is_dir = fs::metadata(&path).map(|m| m.is_dir()).unwrap_or(false);
            Entry::new(&name, path, is_dir)
        })
        .collect()
}

fn read_name_list(all: &[Entry], file: &str) -> Vec<String> {
    let Some(f) = all.iter().find(|e| e.name == file) else { return vec![] };
    let Ok(data) = fs::read(&f.path) else { return vec![] };
    String::from_utf8_lossy(&data).split(['\n', '\r']).filter(|l| !l.trim().is_empty()).map(|l| l.to_string()).collect()
}

fn read_order(all: &[Entry]) -> Vec<String> {
    read_name_list(all, ORDER)
}

fn read_pinned(all: &[Entry]) -> HashSet<String> {
    read_name_list(all, PINNED).iter().map(|n| nfc(n)).collect()
}

fn write_pinned(dir: &Path, pins: &HashSet<String>) {
    let f = dir.join(PINNED);
    if pins.is_empty() {
        let _ = fs::remove_file(&f);
        return;
    }
    let mut v: Vec<&String> = pins.iter().collect();
    v.sort();
    let body = v.iter().map(|s| s.as_str()).collect::<Vec<_>>().join("\n");
    let _ = atomic_write(&f, body.as_bytes());
}

fn ordered(all: &[Entry]) -> Vec<Entry> {
    let files: Vec<&Entry> =
        all.iter().filter(|e| !e.name.starts_with('.') && (e.is_dir || has_ext(&e.name, ".url") || has_ext(&e.name, ".txt"))).collect();
    let mut by_name = std::collections::HashMap::new();
    for f in &files {
        by_name.insert(nfc(&f.name), *f);
    }
    let mut seen = HashSet::new();
    let mut ord: Vec<Entry> = vec![];
    for n in read_order(all) {
        let k = nfc(&n);
        if !seen.contains(&k) {
            if let Some(e) = by_name.get(&k) {
                ord.push((*e).clone());
                seen.insert(k);
            }
        }
    }
    let mut rest: Vec<Entry> = files.iter().filter(|f| !seen.contains(&nfc(&f.name))).map(|f| (*f).clone()).collect();
    rest.sort_by(|a, b| {
        if a.is_dir != b.is_dir {
            return b.is_dir.cmp(&a.is_dir);
        }
        a.name.to_lowercase().cmp(&b.name.to_lowercase())
    });
    ord.extend(rest);
    let pins = read_pinned(all);
    if pins.is_empty() {
        return ord;
    }
    for e in ord.iter_mut() {
        e.pinned = pins.contains(&nfc(&e.name));
    }
    // Sabitlenenler başta (kendi aralarında mevcut sıra korunur)
    let (mut p, np): (Vec<Entry>, Vec<Entry>) = ord.into_iter().partition(|e| e.pinned);
    p.extend(np);
    p
}

fn names(v: &[Entry]) -> Vec<String> {
    v.iter().map(|e| e.name.clone()).collect()
}

fn save_order_in(dir: &Path, names: &[String]) {
    let _ = atomic_write(&dir.join(ORDER), names.join("\n").as_bytes());
}

fn rename_pin(dir: &Path, old: &str, new: Option<&str>) {
    let mut pins = read_pinned(&children(dir));
    let k = nfc(old);
    if !pins.remove(&k) {
        return;
    }
    if let Some(n) = new {
        pins.insert(nfc(n));
    }
    write_pinned(dir, &pins);
}

// MARK: - Listeleme ve sıra

pub fn list(dir: &Path) -> Vec<Entry> {
    let _g = lock();
    ordered(&children(dir))
}

pub fn save_order(dir: &Path, names: &[String]) {
    let _g = lock();
    save_order_in(dir, names);
}

/// Öğeleri sabitler / sabitlemeyi kaldırır.
pub fn set_pinned(dir: &Path, names: &[String], pinned: bool) {
    let _g = lock();
    let mut pins = read_pinned(&children(dir));
    for n in names {
        let k = nfc(n);
        if pinned {
            pins.insert(k);
        } else {
            pins.remove(&k);
        }
    }
    write_pinned(dir, &pins);
}

// MARK: - Yazma

fn write_new(dir: &Path, base: &str, data: &[u8], limit_chars: usize, ext: &str) -> bool {
    let _g = lock();
    let all = children(dir);
    let taken: HashSet<String> = all.iter().map(|e| norm(&e.name)).collect();
    let b = clean(base, limit_chars);
    let mut name = format!("{b}{ext}");
    let mut i = 2;
    while taken.contains(&norm(&name)) {
        name = format!("{b} ({i}){ext}");
        i += 1;
    }
    if atomic_write(&dir.join(&name), data).is_err() {
        return false;
    }
    // Yeni eklenen öğe listenin EN ÜSTÜNE konur; mevcut sıra altta aynen devam eder.
    let mut order = vec![name];
    order.extend(names(&ordered(&all)));
    save_order_in(dir, &order);
    true
}

pub fn add_link(dir: &Path, title: &str, url: &str) -> bool {
    write_new(dir, title, format!("[InternetShortcut]\r\nURL={url}\r\n").as_bytes(), ADD_MAX, ".url")
}

fn title_of(text: &str) -> String {
    let t = collapse_ws(text);
    if t.is_empty() {
        "not".to_string()
    } else {
        t
    }
}

/// Düz metni de kaydeder (URL olmayan kayıt).
pub fn add_note(dir: &Path, text: &str) -> bool {
    write_new(dir, &title_of(text), &note_bytes(text), ADD_MAX, ".url")
}

/// Kısa metin (not) kaydı: .url içinde TEXT= satırı.
pub fn note_bytes(text: &str) -> Vec<u8> {
    let enc = text.replace('\\', "\\\\").replace('\r', "").replace('\n', "\\n");
    format!("[InternetShortcut]\r\nTEXT={enc}\r\n").into_bytes()
}

/// Metni, uzunluk sınırı olmadan düz .txt dosyası olarak kaydeder; ad metnin ilk 100 karakteridir.
pub fn add_text_file(dir: &Path, text: &str) -> bool {
    write_new(dir, &title_of(text), text.as_bytes(), 100, ".txt")
}

pub fn read_plain(path: &Path) -> Option<String> {
    let d = fs::read(path).ok()?;
    let s = String::from_utf8_lossy(&d).into_owned();
    Some(s.strip_prefix('\u{FEFF}').map(|x| x.to_string()).unwrap_or(s))
}

/// Mevcut .txt dosyasının içeriğini baştan yazar (dosya adı değişmez).
pub fn write_plain(path: &Path, text: &str) -> bool {
    let _g = lock();
    atomic_write(path, text.as_bytes()).is_ok()
}

// MARK: - Okuma (.url içeriği)

pub fn lines(path: &Path) -> Vec<String> {
    let Ok(d) = fs::read(path) else { return vec![] };
    String::from_utf8_lossy(&d).split('\n').map(|l| l.strip_prefix('\u{FEFF}').unwrap_or(l).trim().to_string()).collect()
}

fn key_value(ls: &[String], key: &str) -> Option<String> {
    ls.iter().find(|l| l.get(..key.len()).map_or(false, |p| p.eq_ignore_ascii_case(key))).map(|l| l[key.len()..].to_string())
}

pub fn url_of(ls: &[String]) -> Option<String> {
    let v = key_value(ls, "url=")?;
    let v = v.trim();
    if v.is_empty() {
        None
    } else {
        Some(v.to_string())
    }
}

pub fn text_of(ls: &[String]) -> Option<String> {
    key_value(ls, "text=").map(|v| unescape(&v))
}

fn unescape(s: &str) -> String {
    let mut out = String::new();
    let mut it = s.chars();
    while let Some(c) = it.next() {
        if c == '\\' {
            match it.next() {
                Some('n') => out.push('\n'),
                Some(x) => out.push(x),
                None => out.push('\\'),
            }
        } else {
            out.push(c);
        }
    }
    out
}

/// Dosyayı bir kez okuyup (link, metin) çiftini döndürür.
pub fn read_link(path: &Path) -> (Option<String>, Option<String>) {
    let ls = lines(path);
    (url_of(&ls), text_of(&ls))
}

// MARK: - Link / metin ekleme

/// Link veya metni uygun şekilde kaydeder. Ağ erişimi yapabildiği için arka planda çağrılmalı.
/// `fetch_title`: sayfa başlığını getiren işlev (testlerde sahte verilebilir).
pub fn add_from_text(dir: &Path, text: &str, subject: Option<&str>, fetch_title: &dyn Fn(&str) -> Option<String>) -> bool {
    let t = text.trim();
    if t.is_empty() {
        return false;
    }
    let Some(url) = extract_url(t) else { return add_note(dir, t) };
    // Paylaşan tarayıcı sayfanın başlığını veriyorsa (Safari/Chrome) o kullanılır; yoksa sayfa indirilip <title> alınır.
    let mut title: Option<String> = None;
    if let Some(s) = subject.and_then(|s| s.lines().map(str::trim).find(|l| !l.is_empty())) {
        if extract_url(s).is_none() {
            title = Some(s.to_string());
        }
    }
    if title.is_none() {
        title = fetch_title(&url);
    }
    if title.is_none() {
        title = t.replace(&url, "").lines().map(str::trim).find(|l| !l.is_empty()).map(str::to_string);
    }
    if title.is_none() {
        title = host_of(&url);
    }
    add_link(dir, &title.unwrap_or_else(|| "link".to_string()), &url)
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum SubmitResult {
    Added,
    TextFile,
    Failed,
}

/// Ortak "gönder" kuralı: tek parça link → link (başlığı sayfadan alınır), kısa metin → not
/// (.url içinde TEXT=), sınırı aşan metin → .txt dosyası.
pub fn submit_with(dir: &Path, text: &str, subject: Option<&str>, fetch_title: &dyn Fn(&str) -> Option<String>) -> SubmitResult {
    let t = text.trim();
    if t.is_empty() {
        return SubmitResult::Failed;
    }
    let single_url = extract_url(t).is_some() && !t.chars().any(char::is_whitespace);
    if t.chars().count() > ADD_MAX && !single_url {
        return if add_text_file(dir, t) { SubmitResult::TextFile } else { SubmitResult::Failed };
    }
    if add_from_text(dir, t, subject, fetch_title) {
        SubmitResult::Added
    } else {
        SubmitResult::Failed
    }
}

/// `submit_with` + gerçek ağ ile başlık alma (curl).
pub fn submit(dir: &Path, text: &str, subject: Option<&str>) -> SubmitResult {
    submit_with(dir, text, subject, &crate::pagetitle::fetch)
}

// MARK: - Taşı / yeniden adlandır / sil

pub fn move_entry(e: &Entry, target: &Path) -> bool {
    let _g = lock();
    if e.is_dir && (target == e.path || target.starts_with(&e.path)) {
        return false;
    }
    let all = children(target);
    let taken: HashSet<String> = all.iter().map(|x| norm(&x.name)).collect();
    let base = if e.is_dir { e.name.clone() } else { e.title.clone() };
    let ext = if e.is_dir { "" } else { e.ext };
    let mut name = format!("{base}{ext}");
    let mut i = 2;
    while taken.contains(&norm(&name)) {
        name = format!("{base} ({i}){ext}");
        i += 1;
    }
    if fs::rename(&e.path, target.join(&name)).is_err() {
        return false;
    }
    if let Some(parent) = e.path.parent() {
        rename_pin(parent, &e.name, None);
    }
    let mut order = names(&ordered(&all));
    order.push(name);
    save_order_in(target, &order);
    true
}

pub fn add_folder(dir: &Path, name: &str) -> Option<PathBuf> {
    let _g = lock();
    let all = children(dir);
    let base = clean(name, 80);
    let mut n = base.clone();
    let mut i = 2;
    while all.iter().any(|e| norm(&e.name) == norm(&n)) {
        n = format!("{base} ({i})");
        i += 1;
    }
    let u = dir.join(&n);
    fs::create_dir(&u).ok()?;
    let mut order = vec![n];
    order.extend(names(&ordered(&all)));
    save_order_in(dir, &order);
    Some(u)
}

/// Link (.url/.txt) veya klasör adını değiştirir; sıralamayı korur.
pub fn rename(dir: &Path, e: &Entry, title: &str) -> bool {
    let _g = lock();
    let base = clean(title, 116);
    let new_name = if e.is_dir { base } else { format!("{base}{}", e.ext) };
    // Kısa metin (not) ise: kopyalanan içerik de yeni ada uysun diye dosya içeriği güncellenir
    let is_note = !e.is_dir && !e.is_txt && read_link(&e.path).1.is_some();
    if new_name == e.name {
        if is_note {
            let _ = atomic_write(&e.path, &note_bytes(title.trim()));
        }
        return true;
    }
    let all = children(dir);
    if all.iter().any(|x| norm(&x.name) == norm(&new_name) && x.path != e.path) {
        return false;
    }
    let order = names(&ordered(&all));
    let dest = dir.join(&new_name);
    let res = if norm(&new_name) == norm(&e.name) {
        // Yalnızca büyük/küçük harf değişiyor: büyük/küçük harfe duyarsız disklerde geçici ad gerekir.
        let tmp = dir.join(format!(".tmp-{}", unique_suffix()));
        fs::rename(&e.path, &tmp).and_then(|_| fs::rename(&tmp, &dest))
    } else {
        fs::rename(&e.path, &dest)
    };
    if res.is_err() {
        return false;
    }
    if is_note {
        let _ = atomic_write(&dest, &note_bytes(title.trim()));
    }
    let new_order: Vec<String> = order.into_iter().map(|n| if n == e.name { new_name.clone() } else { n }).collect();
    save_order_in(dir, &new_order);
    rename_pin(dir, &e.name, Some(&new_name));
    true
}

/// Düzenlenen .url kaydı ad sınırını (116) aşınca çağrılır: kayıt aynı yerde .txt dosyasına dönüşür
/// (içerik = text; sıralamadaki yeri korunur, eski .url silinir). Dosya adı metnin ilk 100 karakteridir.
pub fn convert_to_txt(dir: &Path, e: &Entry, text: &str) -> bool {
    let _g = lock();
    let all = children(dir);
    let order = names(&ordered(&all));
    let taken: HashSet<String> = all.iter().filter(|x| x.path != e.path).map(|x| norm(&x.name)).collect();
    let b = clean(&title_of(text), 100);
    let mut name = format!("{b}.txt");
    let mut i = 2;
    while taken.contains(&norm(&name)) {
        name = format!("{b} ({i}).txt");
        i += 1;
    }
    if atomic_write(&dir.join(&name), text.as_bytes()).is_err() {
        return false;
    }
    let _ = fs::remove_file(&e.path);
    let new_order: Vec<String> = order.into_iter().map(|n| if n == e.name { name.clone() } else { n }).collect();
    save_order_in(dir, &new_order);
    rename_pin(dir, &e.name, Some(&name));
    true
}

/// "Sil": öğeyi silmez, `trash_dir` (varsayılan ~/.onemsiz) klasörüne taşır
/// (klasörse içeriğiyle; aynı ad varsa ad_1, ad_2…).
pub fn trash_to(path: &Path, trash_dir: &Path) -> bool {
    let _g = lock();
    if fs::create_dir_all(trash_dir).is_err() {
        return false;
    }
    let Some(name) = path.file_name().map(|n| n.to_string_lossy().into_owned()) else { return false };
    let (base, ext) = match name.rsplit_once('.') {
        Some((b, e)) if !b.is_empty() => (b.to_string(), Some(e.to_string())),
        _ => (name.clone(), None),
    };
    let mut t = trash_dir.join(&name);
    let mut n = 1;
    while t.exists() {
        t = trash_dir.join(match &ext {
            Some(e) => format!("{base}_{n}.{e}"),
            None => format!("{base}_{n}"),
        });
        n += 1;
    }
    if fs::rename(path, &t).is_err() {
        return false;
    }
    if let Some(parent) = path.parent() {
        rename_pin(parent, &name, None);
    }
    true
}

pub fn trash(path: &Path) -> bool {
    trash_to(path, &onemsiz_dir())
}

// Yeniden dışa aktarım (CLI/GUI kolaylığı)
pub use text::extract_url as extract_url_from;
