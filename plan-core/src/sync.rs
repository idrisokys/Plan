//! Notlarım eşitleme (istemci): Hızlı Paylaş'ın (_qshare._tcp) ağdaki açık cihazlarıyla ~/Link içindeki
//! .url / .txt dosyaları ve klasörleri karşılaştırır (Android'deki NoteSync ile aynı protokol):
//!  - karşı cihazda olmayan dosya gönderilir, bizde olmayan dosya alınır (eksikler tamamlanır),
//!  - iki tarafta da olan aynı yoldaki dosyanın DEĞİŞTİRİLME ZAMANI yeni olanı eskisinin üzerine yazar.
//!
//! Modlar: 0 = iki cihaz aynı olsun (birleştirir), 1 = bu cihaza göre (karşıdaki bu cihazın aynısı olur),
//! 2 = karşıdaki cihaza göre (bu cihaz karşıdakinin aynısı olur; silinenler çöp klasörüne gider).
//! Uç noktalar: GET /m (liste), GET /f (dosya), POST /d (klasör), POST /u + X-Sync (dosya yaz), DELETE /x.

use crate::entry::has_ext;
use crate::net::{Conn, NetError};
use crate::store::{self, unique_suffix};
use crate::text::{dec, enc, l, nfc};
use std::collections::BTreeMap;
use std::fs;
use std::io::{Read, Write};
use std::path::{Path, PathBuf};
use std::time::{Duration, SystemTime, UNIX_EPOCH};

/// Dosya sistemlerinin zaman çözünürlüğü farkı için tolerans (ms).
pub const TOL: i64 = 2000;
pub const MAX_DEPTH: usize = 24;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Item {
    pub rel: String,
    pub dir: bool,
    pub size: i64,
    pub mtime: i64,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Peer {
    pub id: String,
    pub name: String,
    /// "host:port"
    pub addr: String,
}

#[derive(Debug, Default, Clone)]
pub struct Outcome {
    pub peers: usize,
    pub sent: usize,
    pub got: usize,
    pub deleted: usize,
    pub mode: i32,
    pub errors: Vec<String>,
    pub error: Option<String>,
}

impl Outcome {
    pub fn message(&self) -> String {
        if let Some(e) = &self.error {
            return l(&format!("Eşitleme hatası: {e}"), &format!("Sync error: {e}"));
        }
        if self.peers == 0 {
            return self.errors.first().cloned().unwrap_or_else(|| l("Açık cihaz bulunamadı", "No open device found"));
        }
        let (p, s, g, d) = (self.peers, self.sent, self.got, self.deleted);
        let base = match self.mode {
            2 => l(
                &format!("Karşıdaki cihaza göre eşitlendi: {g} alındı, {d} silindi"),
                &format!("Synced to the other device: {g} received, {d} deleted"),
            ),
            1 => l(
                &format!("Bu cihaz esas alındı: {p} cihaz, {s} gönderildi, {d} silindi"),
                &format!("This device is now the master: {p} device(s), {s} sent, {d} deleted"),
            ),
            _ => l(&format!("Eşitlendi: {p} cihaz, {s} gönderildi, {g} alındı"), &format!("Synced: {p} device(s), {s} sent, {g} received")),
        };
        match self.errors.first() {
            None => base,
            Some(e) => format!("{base}\n{e}"),
        }
    }
    pub fn ok(&self) -> bool {
        self.error.is_none() && self.errors.is_empty()
    }
}

// MARK: Ortak yardımcılar

/// Eşitlenen dosya adı mı? (.url / .txt; yarım kalan .part değil; yalnızca bu cihazdaki .pinned.txt hariç)
pub fn is_note_name(n: &str) -> bool {
    !has_ext(n, ".part") && n != store::PINNED && (has_ext(n, ".url") || has_ext(n, ".txt"))
}

pub fn ms(t: Option<SystemTime>) -> i64 {
    t.and_then(|t| t.duration_since(UNIX_EPOCH).ok()).map(|d| d.as_millis() as i64).unwrap_or(0)
}

fn depth_then_name(a: &String, b: &String) -> std::cmp::Ordering {
    let ca = a.matches('/').count();
    let cb = b.matches('/').count();
    ca.cmp(&cb).then_with(|| a.cmp(b)) // üst klasörler önce
}

/// Karşı taraftan gelen göreli yolu Link klasörü içinde güvenli bir yola çevirir; geçersizse None.
/// Her bölüm ayrı doğrulanır (".." ve kontrol karakterleri yok), sonuç Link dışına çıkamaz.
pub fn resolve(rel: &str, root: &Path, dir: bool) -> Option<PathBuf> {
    let segs: Vec<&str> = rel.split('/').collect();
    if segs.is_empty() || segs.len() > MAX_DEPTH {
        return None;
    }
    for sg in &segs {
        if sg.is_empty() || *sg == "." || *sg == ".." || sg.len() > 240 {
            return None;
        }
        if sg.chars().any(|c| (c as u32) < 32 || ":*?\"<>|\\".contains(c)) {
            return None;
        }
    }
    if !dir {
        let last = segs.last()?;
        if !(is_note_name(last) || *last == store::ORDER) {
            return None;
        }
    }
    let f = segs.iter().fold(root.to_path_buf(), |p, s| p.join(s));
    // Sembolik bağlar kökün dışına çıkarmasın: var olan en derin üst klasörü çöz.
    let base = fs::canonicalize(root).ok()?;
    let mut probe = f.clone();
    loop {
        if let Ok(c) = fs::canonicalize(&probe) {
            return if c.starts_with(&base) { Some(f) } else { None };
        }
        if !probe.pop() {
            return None;
        }
    }
}

/// Yerel not ağacı: göreli yol → öğe (yollar NFC; Android ile aynı yazım).
pub fn local(root: &Path) -> BTreeMap<String, Item> {
    let mut out = BTreeMap::new();
    fn walk(d: &Path, prefix: &str, depth: usize, out: &mut BTreeMap<String, Item>) {
        if depth > MAX_DEPTH {
            return;
        }
        let Ok(rd) = fs::read_dir(d) else { return };
        for e in rd.flatten() {
            let name = nfc(&e.file_name().to_string_lossy());
            let Ok(meta) = fs::metadata(e.path()) else { continue };
            let rel = format!("{prefix}{name}");
            if meta.is_dir() {
                if name.starts_with('.') {
                    continue;
                }
                out.insert(rel.clone(), Item { rel: rel.clone(), dir: true, size: 0, mtime: 0 });
                walk(&e.path(), &format!("{rel}/"), depth + 1, out);
            } else if is_note_name(&name) {
                out.insert(rel.clone(), Item { rel, dir: false, size: meta.len() as i64, mtime: ms(meta.modified().ok()) });
            }
        }
    }
    walk(root, "", 0, &mut out);
    out
}

/// Sunucunun /m yanıtı: "F|D <TAB> boyut <TAB> mtime <TAB> kodlu-yol" satırları.
pub fn manifest_body(items: &BTreeMap<String, Item>) -> String {
    items.values().map(|it| format!("{}\t{}\t{}\t{}\n", if it.dir { "D" } else { "F" }, it.size, it.mtime, enc(&it.rel))).collect()
}

pub fn parse_manifest(body: &str) -> BTreeMap<String, Item> {
    let mut out = BTreeMap::new();
    for ln in body.split('\n') {
        let a: Vec<&str> = ln.split('\t').collect();
        if a.len() != 4 {
            continue;
        }
        let rel = dec(a[3]);
        out.insert(rel.clone(), Item { rel, dir: a[0] == "D", size: a[1].parse().unwrap_or(0), mtime: a[2].parse().unwrap_or(0) });
    }
    out
}

fn set_mtime(path: &Path, mt_ms: i64) {
    if mt_ms <= 0 {
        return;
    }
    if let Ok(f) = fs::OpenOptions::new().write(true).open(path) {
        let _ = f.set_modified(UNIX_EPOCH + Duration::from_millis(mt_ms as u64));
    }
}

// MARK: İstemci işlemleri

fn fetch_manifest(p: &Peer) -> Result<BTreeMap<String, Item>, NetError> {
    let mut c = Conn::connect(&p.addr)?;
    c.send(b"GET /m HTTP/1.1\r\nHost: qs\r\nConnection: close\r\n\r\n")?;
    let h = c.read_head()?;
    if h.status() != 200 {
        let s = h.status();
        return Err(NetError(l(
            &format!("karşı cihaz Link eşitlemesini desteklemiyor (kod {s}); orada uygulamayı güncelleyin"),
            &format!("the other device does not support Link sync (code {s}); update the app there"),
        )));
    }
    let len = h.get("content-length").and_then(|v| v.parse::<usize>().ok()).unwrap_or(0).min(8 << 20);
    let mut data = vec![];
    c.read_body(len, &mut |b| {
        data.extend_from_slice(b);
        Ok(())
    })?;
    Ok(parse_manifest(&String::from_utf8_lossy(&data)))
}

fn pull(p: &Peer, it: &Item, root: &Path) -> Result<(), NetError> {
    let Some(dest) = resolve(&it.rel, root, false) else { return Ok(()) };
    let parent = dest.parent().unwrap().to_path_buf();
    fs::create_dir_all(&parent)?;
    let mut c = Conn::connect(&p.addr)?;
    c.send(format!("GET /f HTTP/1.1\r\nHost: qs\r\nX-Name: {}\r\nConnection: close\r\n\r\n", enc(&it.rel)).as_bytes())?;
    let h = c.read_head()?;
    if h.status() != 200 {
        return Err(NetError(format!("{}: {}", it.rel, h.status())));
    }
    let len = h.get("content-length").and_then(|v| v.parse::<usize>().ok()).unwrap_or(0);
    let tmp = parent.join(format!("{}.{}.part", dest.file_name().unwrap().to_string_lossy(), unique_suffix()));
    let mut file = fs::File::create(&tmp).map_err(|_| NetError(format!("{}: {}", it.rel, l("yazılamadı", "write failed"))))?;
    let res = c.read_body(len, &mut |b| file.write_all(b));
    drop(file);
    if let Err(e) = res {
        let _ = fs::remove_file(&tmp);
        return Err(e);
    }
    if let Some(mt) = h.get("x-mtime").and_then(|v| v.parse::<i64>().ok()) {
        set_mtime(&tmp, mt);
    }
    if dest.exists() {
        fs::remove_file(&dest)?;
    }
    fs::rename(&tmp, &dest)?;
    Ok(())
}

fn push(p: &Peer, it: &Item, root: &Path) -> Result<(), NetError> {
    let Some(f) = resolve(&it.rel, root, false) else { return Ok(()) };
    let meta = fs::metadata(&f)?;
    let len = meta.len();
    let mt = ms(meta.modified().ok());
    let mut c = Conn::connect(&p.addr)?;
    let head = format!(
        "POST /u HTTP/1.1\r\nHost: qs\r\nX-Name: {}\r\nX-Sync: 1\r\nX-Mtime: {mt}\r\nContent-Length: {len}\r\nConnection: close\r\n\r\n",
        enc(&it.rel)
    );
    c.send(head.as_bytes())?;
    let mut fh = fs::File::open(&f)?;
    let mut sent = 0u64;
    let mut buf = vec![0u8; 256 * 1024];
    while sent < len {
        let want = buf.len().min((len - sent) as usize);
        let n = fh.read(&mut buf[..want])?;
        if n == 0 {
            break;
        }
        c.send(&buf[..n])?;
        sent += n as u64;
    }
    if sent != len {
        return Err(NetError(format!("{}: {}", it.rel, l("dosya değişti", "file changed"))));
    }
    let h = c.read_head()?;
    if h.status() != 200 {
        return Err(NetError(format!("{}: {}", it.rel, l("karşı cihaz kabul etmedi", "refused"))));
    }
    Ok(())
}

fn mkdir_remote(p: &Peer, rel: &str) -> Result<(), NetError> {
    let mut c = Conn::connect(&p.addr)?;
    c.send(format!("POST /d HTTP/1.1\r\nHost: qs\r\nX-Name: {}\r\nContent-Length: 0\r\nConnection: close\r\n\r\n", enc(rel)).as_bytes())?;
    if c.read_head()?.status() != 200 {
        return Err(NetError(format!("{rel}: mkdir")));
    }
    Ok(())
}

fn delete_remote(p: &Peer, rel: &str, dir: bool) -> Result<(), NetError> {
    // Bilerek DELETE ve Content-Length yok: bu özelliği bilmeyen eski sürüm isteği reddeder (boş dosya oluşturmaz).
    let mut c = Conn::connect(&p.addr)?;
    c.send(
        format!(
            "DELETE /x HTTP/1.1\r\nHost: qs\r\nX-Name: {}\r\nX-Dir: {}\r\nConnection: close\r\n\r\n",
            enc(rel),
            if dir { 1 } else { 0 }
        )
        .as_bytes(),
    )?;
    if c.read_head()?.status() != 200 {
        return Err(NetError(format!("{rel}: {}", l("silinemedi / eski sürüm", "could not delete / old version"))));
    }
    Ok(())
}

/// Tek cihazla eşitler; (gönderilen, alınan). Dosya bazlı hatalar errs'e eklenir, diğer dosyalar sürer.
fn sync_peer(p: &Peer, root: &Path, errs: &mut Vec<String>) -> Result<(usize, usize), NetError> {
    let remote = fetch_manifest(p)?;
    let loc = local(root);
    let (mut sent, mut got) = (0, 0);
    let mut keys: Vec<String> = loc.keys().chain(remote.keys()).cloned().collect::<std::collections::BTreeSet<_>>().into_iter().collect();
    keys.sort_by(depth_then_name);
    for k in keys {
        let (lo, re) = (loc.get(&k), remote.get(&k));
        let r: Result<(), NetError> = (|| {
            if lo.or(re).map(|x| x.dir) == Some(true) {
                if lo.is_none() {
                    if let Some(d) = resolve(&k, root, true) {
                        fs::create_dir_all(d)?;
                    }
                } else if re.is_none() {
                    mkdir_remote(p, &k)?;
                }
                return Ok(());
            }
            match (lo, re) {
                (Some(a), Some(b)) => {
                    if a.mtime - b.mtime > TOL {
                        push(p, a, root)?;
                        sent += 1;
                    } else if b.mtime - a.mtime > TOL {
                        pull(p, b, root)?;
                        got += 1;
                    }
                }
                (Some(a), None) => {
                    push(p, a, root)?;
                    sent += 1;
                }
                (None, Some(b)) => {
                    pull(p, b, root)?;
                    got += 1;
                }
                _ => {}
            }
            Ok(())
        })();
        if let Err(e) = r {
            errs.push(format!("{}: {e}", p.name));
        }
    }
    Ok((sent, got))
}

/// Karşı cihazı bu cihazın aynısı yapar; (gönderilen, silinen). Bu cihazda hiçbir şey değişmez.
fn mirror_peer(p: &Peer, root: &Path, errs: &mut Vec<String>) -> Result<(usize, usize), NetError> {
    let remote = fetch_manifest(p)?;
    let loc = local(root);
    let (mut sent, mut deleted) = (0, 0);
    let mut gone: Vec<String> = vec![];
    let mut stale: Vec<String> = remote.keys().filter(|k| loc.get(*k).map_or(true, |x| x.dir != remote[*k].dir)).cloned().collect();
    stale.sort_by(depth_then_name);
    for k in stale {
        if gone.iter().any(|g| k.starts_with(&format!("{g}/"))) {
            continue;
        }
        let r = &remote[&k];
        match delete_remote(p, &k, r.dir) {
            Ok(()) => {
                deleted += 1;
                if r.dir {
                    gone.push(k);
                }
            }
            Err(e) => errs.push(format!("{}: {e}", p.name)),
        }
    }
    let mut keys: Vec<String> = loc.keys().cloned().collect();
    keys.sort_by(depth_then_name);
    for k in keys {
        let lo = &loc[&k];
        let mut re = remote.get(&k);
        if let Some(x) = re {
            if x.dir != lo.dir || gone.contains(&k) {
                re = None;
            }
        }
        let r: Result<(), NetError> = (|| {
            if lo.dir {
                if re.is_none() {
                    mkdir_remote(p, &k)?;
                }
            } else if re.map_or(true, |x| x.size != lo.size || (lo.mtime - x.mtime).abs() > TOL) {
                push(p, lo, root)?;
                sent += 1;
            }
            Ok(())
        })();
        if let Err(e) = r {
            errs.push(format!("{}: {e}", p.name));
        }
    }
    Ok((sent, deleted))
}

/// Bu cihazı karşı cihazın aynısı yapar; (alınan, silinen). Silinenler `trash_dir`'e taşınır.
fn pull_mirror(p: &Peer, root: &Path, trash_dir: &Path, errs: &mut Vec<String>) -> Result<(usize, usize), NetError> {
    let remote = fetch_manifest(p)?;
    let loc = local(root);
    let (mut got, mut deleted) = (0, 0);
    let mut gone: Vec<String> = vec![];
    let mut stale: Vec<String> = loc.keys().filter(|k| remote.get(*k).map_or(true, |x| x.dir != loc[*k].dir)).cloned().collect();
    stale.sort_by(depth_then_name);
    for k in stale {
        if gone.iter().any(|g| k.starts_with(&format!("{g}/"))) {
            continue;
        }
        let lo = &loc[&k];
        let r: Result<(), NetError> = (|| {
            if let Some(f) = resolve(&k, root, lo.dir) {
                if f.exists() && !store::trash_to(&f, trash_dir) {
                    return Err(NetError(format!("{k}: {}", l("çöpe taşınamadı", "could not move to trash"))));
                }
            }
            Ok(())
        })();
        match r {
            Ok(()) => {
                deleted += 1;
                if lo.dir {
                    gone.push(k);
                }
            }
            Err(e) => errs.push(format!("{}: {e}", p.name)),
        }
    }
    let mut keys: Vec<String> = remote.keys().cloned().collect();
    keys.sort_by(depth_then_name);
    for k in keys {
        let re = &remote[&k];
        let mut lo = loc.get(&k);
        if let Some(x) = lo {
            if x.dir != re.dir || gone.contains(&k) {
                lo = None;
            }
        }
        let r: Result<(), NetError> = (|| {
            if re.dir {
                if lo.is_none() {
                    if let Some(d) = resolve(&k, root, true) {
                        fs::create_dir_all(d)?;
                    }
                }
            } else if lo.map_or(true, |x| x.size != re.size || (x.mtime - re.mtime).abs() > TOL) {
                pull(p, re, root)?;
                got += 1;
            }
            Ok(())
        })();
        if let Err(e) = r {
            errs.push(format!("{}: {e}", p.name));
        }
    }
    Ok((got, deleted))
}

/// Seçilen cihazlarla eşitler. Arka plan iş parçacığında çağrılmalı (ağ + disk).
/// mode: 0 = iki cihazda aynı olsun, 1 = bu cihaza göre, 2 = karşıdaki cihaza göre (ilk seçilen).
pub fn run(mode: i32, targets: &[Peer], root: &Path, trash_dir: &Path) -> Outcome {
    let mut res = Outcome { mode, ..Default::default() };
    if targets.is_empty() {
        res.error = Some(l("cihaz seçilmedi", "no device selected"));
        return res;
    }
    let list: &[Peer] = if mode == 2 { &targets[..1] } else { targets };
    for p in list {
        let r = match mode {
            1 => mirror_peer(p, root, &mut res.errors).map(|(a, b)| {
                res.sent += a;
                res.deleted += b;
            }),
            2 => pull_mirror(p, root, trash_dir, &mut res.errors).map(|(a, b)| {
                res.got += a;
                res.deleted += b;
            }),
            _ => sync_peer(p, root, &mut res.errors).map(|(a, b)| {
                res.sent += a;
                res.got += b;
            }),
        };
        match r {
            Ok(()) => res.peers += 1,
            Err(e) => res.errors.push(format!("{}: {e}", p.name)),
        }
    }
    res
}
