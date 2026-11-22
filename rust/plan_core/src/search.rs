//! Not/link dosyalarında paralel arama. Swift'teki eski `NotesStore.search` ile aynı kurallar:
//! yazılan her kelime (klasör adı, başlık, link adresi veya not metninde) bulunmalıdır.

use crate::fold::{fold, fold_mapped};
use std::sync::atomic::{AtomicUsize, Ordering};
use std::sync::Mutex;

pub const KIND_URL: u8 = 0;
pub const KIND_TXT: u8 = 1;
pub const KIND_DIR: u8 = 2;
pub const MAX_HITS: usize = 500;

pub struct Item {
    pub kind: u8,
    pub path: String,
    pub title: String,
}

#[derive(Debug, Clone, PartialEq)]
pub struct Hit {
    pub index: usize,
    pub is_note: bool,
    pub title_match: bool,
    pub detail: String,
}

fn is_newline(c: char) -> bool {
    matches!(c, '\n' | '\u{0B}' | '\u{0C}' | '\r' | '\u{85}' | '\u{2028}' | '\u{2029}')
}

/// Başındaki BOM atılır, kenar boşlukları kırpılır.
fn clean_line(l: &str) -> &str {
    l.strip_prefix('\u{FEFF}').unwrap_or(l).trim()
}

fn starts_with_ci(line: &str, prefix: &str) -> bool {
    line.len() >= prefix.len()
        && line.is_char_boundary(prefix.len())
        && line[..prefix.len()].eq_ignore_ascii_case(prefix)
}

/// `.url` dosyasından (link, metin) çıkarır.
pub fn parse_link(data: &str) -> (Option<String>, Option<String>) {
    let lines: Vec<&str> = data.split(is_newline).map(clean_line).collect();
    let url = lines.iter().find(|l| starts_with_ci(l, "url=")).and_then(|l| {
        let v = l[4..].trim();
        if v.is_empty() { None } else { Some(v.to_string()) }
    });
    let text = lines.iter().find(|l| starts_with_ci(l, "text=")).map(|l| unescape(&l[5..]));
    (url, text)
}

fn unescape(s: &str) -> String {
    let mut out = String::with_capacity(s.len());
    let mut it = s.chars().peekable();
    while let Some(c) = it.next() {
        if c == '\\' {
            match it.next() {
                Some('n') => out.push('\n'),
                Some(o) => out.push(o),
                None => out.push('\\'),
            }
        } else {
            out.push(c);
        }
    }
    out
}

/// Sorgudaki kelimeler (sadeleştirilmiş, boşluklara göre bölünmüş).
pub fn terms(query: &str) -> Vec<String> {
    fold(query)
        .split(|c: char| c.is_whitespace() || is_newline(c))
        .filter(|t| !t.is_empty())
        .map(str::to_string)
        .collect()
}

fn snippet(text: &str, terms: &[String]) -> String {
    let (fb, map) = fold_mapped(text);
    let first = terms
        .iter()
        .filter_map(|t| fb.find(t.as_str()))
        .map(|off| fb[..off].chars().count())
        .min()
        .unwrap_or(0);
    let i = map.get(first).copied().unwrap_or(0) as usize;
    let chars: Vec<char> = text.chars().collect();
    let st = i.saturating_sub(30);
    let end = chars.len().min(st + 120);
    let mut out = String::new();
    if st > 0 {
        out.push('…');
    }
    if st < end {
        let mut prev_space = false;
        for &c in &chars[st..end] {
            if c.is_whitespace() {
                if !prev_space {
                    out.push(' ');
                }
                prev_space = true;
            } else {
                out.push(c);
                prev_space = false;
            }
        }
    }
    out
}

fn read_lossy(path: &str) -> String {
    match std::fs::read(path) {
        Ok(b) => String::from_utf8_lossy(&b).into_owned(),
        Err(_) => String::new(),
    }
}

fn matches(index: usize, item: &Item, terms: &[String]) -> Option<Hit> {
    let ft = fold(&item.title);
    if item.kind == KIND_DIR {
        if !terms.iter().all(|t| ft.contains(t.as_str())) {
            return None;
        }
        return Some(Hit { index, is_note: false, title_match: true, detail: String::new() });
    }
    let raw = read_lossy(&item.path);
    let (url, text) = if item.kind == KIND_TXT {
        (None, raw.strip_prefix('\u{FEFF}').unwrap_or(&raw).to_string())
    } else {
        let (u, t) = parse_link(&raw);
        (u, t.unwrap_or_default())
    };
    let body: &str = url.as_deref().unwrap_or(&text);
    let fb = fold(body);
    if !terms.iter().all(|t| ft.contains(t.as_str()) || fb.contains(t.as_str())) {
        return None;
    }
    let detail = match &url {
        Some(u) => u.clone(),
        None => snippet(&text, terms),
    };
    Some(Hit {
        index,
        is_note: url.is_none(),
        title_match: terms.iter().all(|t| ft.contains(t.as_str())),
        detail,
    })
}

/// Tüm öğelerde arar. `alive` false dönerse iş bırakılır. Sonuç: ilk 500 isabet, başlıkta
/// geçenler önce (kendi aralarında girdi sırası korunur).
pub fn search(items: &[Item], query: &str, alive: &(dyn Fn() -> bool + Sync)) -> Vec<Hit> {
    let terms = terms(query);
    if terms.is_empty() {
        return Vec::new();
    }
    let next = AtomicUsize::new(0);
    let found: Mutex<Vec<Hit>> = Mutex::new(Vec::new());
    let n = crate::workers().min(items.len().max(1));
    std::thread::scope(|s| {
        for _ in 0..n {
            s.spawn(|| {
                let mut local = Vec::new();
                loop {
                    let i = next.fetch_add(1, Ordering::Relaxed);
                    if i >= items.len() || !alive() {
                        break;
                    }
                    if let Some(h) = matches(i, &items[i], &terms) {
                        local.push(h);
                    }
                }
                found.lock().unwrap().extend(local);
            });
        }
    });
    let mut hits = found.into_inner().unwrap();
    hits.sort_by_key(|h| h.index);
    hits.truncate(MAX_HITS);
    let (mut first, rest): (Vec<Hit>, Vec<Hit>) = hits.into_iter().partition(|h| h.title_match);
    first.extend(rest);
    first
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::fs;

    fn tmp(name: &str) -> std::path::PathBuf {
        let d = std::env::temp_dir().join(format!("plan_core_{}_{}", name, std::process::id()));
        let _ = fs::remove_dir_all(&d);
        fs::create_dir_all(&d).unwrap();
        d
    }

    fn item(kind: u8, dir: &std::path::Path, file: &str, title: &str, body: &str) -> Item {
        let p = dir.join(file);
        if kind != KIND_DIR {
            fs::write(&p, body).unwrap();
        }
        Item { kind, path: p.to_string_lossy().into_owned(), title: title.into() }
    }

    #[test]
    fn parse_link_reads_url_and_text() {
        let (u, t) = parse_link("\u{FEFF}[InternetShortcut]\r\nURL=https://a.b/c\r\n");
        assert_eq!(u.as_deref(), Some("https://a.b/c"));
        assert_eq!(t, None);
        let (u, t) = parse_link("[InternetShortcut]\r\nTEXT=a\\nb\\\\c\r\n");
        assert_eq!(u, None);
        assert_eq!(t.as_deref(), Some("a\nb\\c"));
        assert_eq!(parse_link("url=\n").0, None);
    }

    #[test]
    fn finds_across_items_with_turkish_letters() {
        let d = tmp("find");
        let items = vec![
            item(KIND_URL, &d, "a.url", "Swift Docs", "[InternetShortcut]\r\nURL=https://developer.apple.com/swift\r\n"),
            item(KIND_URL, &d, "b.url", "Çalışma Notları", "[InternetShortcut]\r\nTEXT=Çalışma Notları\r\n"),
            item(KIND_TXT, &d, "c.txt", "uzun", "Bugün çiçek sulama günü"),
            item(KIND_DIR, &d, "Work", "Work", ""),
        ];
        let alive = || true;
        let a = search(&items, "SWIFT", &alive);
        assert_eq!(a.len(), 1);
        assert_eq!(a[0].index, 0);
        assert!(!a[0].is_note);
        assert_eq!(a[0].detail, "https://developer.apple.com/swift");

        let b = search(&items, "calisma notlari", &alive);
        assert_eq!(b.len(), 1);
        assert!(b[0].is_note && b[0].title_match);

        let c = search(&items, "cicek", &alive);
        assert_eq!(c.len(), 1);
        assert_eq!(c[0].index, 2);
        assert!(!c[0].title_match);
        assert_eq!(c[0].detail, "Bugün çiçek sulama günü");

        let w = search(&items, "work", &alive);
        assert_eq!(w.len(), 1);
        assert_eq!(w[0].detail, "");
        assert!(search(&items, "   ", &alive).is_empty());
        let _ = fs::remove_dir_all(&d);
    }

    #[test]
    fn title_matches_come_first_and_all_terms_required() {
        let d = tmp("order");
        let items = vec![
            item(KIND_TXT, &d, "1.txt", "x", "alfa beta"),
            item(KIND_TXT, &d, "2.txt", "alfa beta", "yok"),
            item(KIND_TXT, &d, "3.txt", "y", "alfa"),
        ];
        let h = search(&items, "alfa beta", &|| true);
        assert_eq!(h.iter().map(|x| x.index).collect::<Vec<_>>(), vec![1, 0]);
        let _ = fs::remove_dir_all(&d);
    }

    #[test]
    fn snippet_window_and_ellipsis() {
        let long = format!("{} hedef {}", "a ".repeat(60), "b ".repeat(80));
        let s = snippet(&long, &["hedef".to_string()]);
        assert!(s.starts_with('…'));
        assert!(s.contains("hedef"));
        assert!(s.chars().count() <= 121);
    }

    #[test]
    fn cancelled_search_returns_quickly() {
        let d = tmp("cancel");
        let items: Vec<Item> = (0..50).map(|i| item(KIND_TXT, &d, &format!("{i}.txt"), "t", "alfa")).collect();
        let h = search(&items, "alfa", &|| false);
        assert!(h.is_empty());
        let _ = fs::remove_dir_all(&d);
    }
}
