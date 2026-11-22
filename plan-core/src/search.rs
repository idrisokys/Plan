//! Tüm klasörlerde arama (klasör adı, başlık, link adresi, not metni) ve .txt içi arama.

use crate::entry::{Entry, Hit};
use crate::store;
use crate::text::{fk, fold};
use std::path::Path;
use std::sync::atomic::{AtomicUsize, Ordering};
use std::sync::Mutex;

/// Tüm klasörlerde arar. Yazılan her kelime bulunmalıdır; `alive` false dönerse arama bırakılır.
/// Başlıkta geçenler önce gelir; en çok 500 sonuç.
pub fn search(root: &Path, query: &str, alive: &(dyn Fn() -> bool + Sync)) -> Vec<Hit> {
    let terms: Vec<String> = fold(query).split_whitespace().map(str::to_string).collect();
    if terms.is_empty() {
        return vec![];
    }

    let mut files: Vec<(Entry, Vec<Entry>)> = vec![];
    fn walk(dir: &Path, path: &[Entry], files: &mut Vec<(Entry, Vec<Entry>)>, alive: &(dyn Fn() -> bool + Sync)) {
        for e in store::list(dir) {
            if !alive() {
                return;
            }
            if e.is_dir {
                files.push((e.clone(), path.to_vec()));
                let mut p = path.to_vec();
                p.push(e.clone());
                walk(&e.path, &p, files, alive);
            } else {
                files.push((e, path.to_vec()));
            }
        }
    }
    walk(root, &[], &mut files, alive);

    let results: Vec<Mutex<Option<Hit>>> = files.iter().map(|_| Mutex::new(None)).collect();
    let next = AtomicUsize::new(0);
    let workers = std::thread::available_parallelism().map(|n| n.get()).unwrap_or(4).min(8);
    std::thread::scope(|s| {
        for _ in 0..workers {
            s.spawn(|| loop {
                let i = next.fetch_add(1, Ordering::Relaxed);
                if i >= files.len() || !alive() {
                    break;
                }
                let (e, path) = &files[i];
                if let Some(h) = match_entry(e, path, &terms) {
                    *results[i].lock().unwrap() = Some(h);
                }
            });
        }
    });

    let hits: Vec<Hit> = results.into_iter().filter_map(|m| m.into_inner().unwrap()).take(500).collect();
    let (mut a, b): (Vec<Hit>, Vec<Hit>) = hits.into_iter().partition(|h| h.title_match);
    a.extend(b);
    a
}

fn match_entry(e: &Entry, path: &[Entry], terms: &[String]) -> Option<Hit> {
    // Klasör: yalnızca adında aranır
    if e.is_dir {
        let fnm = fold(&e.title);
        if !terms.iter().all(|t| fnm.contains(t)) {
            return None;
        }
        return Some(Hit { entry: e.clone(), path: path.to_vec(), detail: String::new(), is_note: false, title_match: true });
    }
    let ls = if e.is_txt { vec![] } else { store::lines(&e.path) };
    let url = store::url_of(&ls);
    let text = if e.is_txt { store::read_plain(&e.path).unwrap_or_default() } else { store::text_of(&ls).unwrap_or_default() };
    let ft = fold(&e.title);
    let body: &str = url.as_deref().unwrap_or(&text);
    let fb = fold(body);
    let all = format!("{ft}\n{fb}");
    if !terms.iter().all(|t| all.contains(t)) {
        return None;
    }
    let detail = if let Some(u) = &url {
        u.clone()
    } else {
        let idx = terms.iter().filter_map(|t| fb.find(t.as_str()).map(|b| fb[..b].chars().count())).min().unwrap_or(0);
        let chars: Vec<char> = text.chars().collect();
        let st = idx.saturating_sub(30);
        let end = (st + 120).min(chars.len());
        let slice: String = if st < end { chars[st..end].iter().collect() } else { String::new() };
        format!("{}{}", if st > 0 { "…" } else { "" }, crate::text::collapse_ws_keep_edges(&slice))
    };
    Some(Hit { entry: e.clone(), path: path.to_vec(), detail, is_note: url.is_none(), title_match: terms.iter().all(|t| ft.contains(t)) })
}

/// .txt içinde arama: eşleşmelerin (başlangıç, bitiş) KARAKTER konumları (en çok 5000).
pub fn txt_matches(text: &str, query: &str) -> Vec<(usize, usize)> {
    let q: Vec<char> = fk(query.trim()).chars().collect();
    if q.is_empty() {
        return vec![];
    }
    let hay: Vec<char> = fk(text).chars().collect();
    let mut out = vec![];
    let mut i = 0;
    while out.len() < 5000 && i + q.len() <= hay.len() {
        if hay[i..i + q.len()] == q[..] {
            out.push((i, i + q.len()));
            i += q.len();
        } else {
            i += 1;
        }
    }
    out
}
