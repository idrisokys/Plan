//! Notlar klasörünün dolaşımı: Swift'teki `NotesStore.list/ordered` ile aynı kurallar.
//!
//! * gizli (.) dosyalar ve .url/.txt dışındaki dosyalar listelenmez; klasörler listelenir
//! * `.order.txt` sırası, kalanlar klasörler önce + ada göre; `.pinned.txt` ile sabitlenenler başa
//! * ad eşleştirmeleri NFC (precomposedStringWithCanonicalMapping) üzerinden yapılır

use crate::search::{self, Hit, Item, KIND_DIR, KIND_TXT, KIND_URL};
use crate::unicode::nfc;
use std::collections::{HashMap, HashSet};
use std::path::Path;

const ORDER: &str = ".order.txt";
const PINNED: &str = ".pinned.txt";
const MAX_DEPTH: usize = 64; // symlink döngülerine karşı güvenlik

#[derive(Debug, Clone, PartialEq)]
pub struct TreeEntry {
    pub name: String,
    pub path: String,
    pub is_dir: bool,
    pub pinned: bool,
}

impl TreeEntry {
    fn lower_name(&self) -> String {
        self.name.to_lowercase()
    }
    pub fn is_txt(&self) -> bool {
        !self.is_dir && self.lower_name().ends_with(".txt")
    }
    pub fn is_url(&self) -> bool {
        !self.is_dir && self.lower_name().ends_with(".url")
    }
    /// Listede gösterilen ad (.url / .txt uzantısı atılır).
    pub fn title(&self) -> String {
        if self.is_txt() || self.is_url() {
            let n = self.name.chars().count();
            self.name.chars().take(n.saturating_sub(4)).collect()
        } else {
            self.name.clone()
        }
    }
}

fn is_newline(c: char) -> bool {
    matches!(c, '\n' | '\u{0B}' | '\u{0C}' | '\r' | '\u{85}' | '\u{2028}' | '\u{2029}')
}

fn read_lines(path: &Path) -> Vec<String> {
    match std::fs::read(path) {
        Ok(b) => String::from_utf8_lossy(&b)
            .split(is_newline)
            .filter(|l| !l.trim().is_empty())
            .map(str::to_string)
            .collect(),
        Err(_) => Vec::new(),
    }
}

/// Bir klasörün sıralı, süzülmüş içeriği.
pub fn list(dir: &Path) -> Vec<TreeEntry> {
    let Ok(rd) = std::fs::read_dir(dir) else { return Vec::new() };
    let mut files = Vec::new();
    for e in rd.flatten() {
        let name = e.file_name().to_string_lossy().into_owned();
        if name.starts_with('.') {
            continue;
        }
        let path = e.path();
        let is_dir = std::fs::metadata(&path).map(|m| m.is_dir()).unwrap_or(false);
        let lower = name.to_lowercase();
        if is_dir || lower.ends_with(".url") || lower.ends_with(".txt") {
            files.push(TreeEntry { name, path: path.to_string_lossy().into_owned(), is_dir, pinned: false });
        }
    }

    let mut by_name: HashMap<String, usize> = HashMap::new();
    for (i, f) in files.iter().enumerate() {
        by_name.insert(nfc(&f.name), i);
    }
    let mut seen: HashSet<String> = HashSet::new();
    let mut ord: Vec<usize> = Vec::new();
    for n in read_lines(&dir.join(ORDER)) {
        let k = nfc(&n);
        if !seen.contains(&k) {
            if let Some(&i) = by_name.get(&k) {
                ord.push(i);
                seen.insert(k);
            }
        }
    }
    let mut rest: Vec<(usize, String)> = files
        .iter()
        .enumerate()
        .filter(|(_, f)| !seen.contains(&nfc(&f.name)))
        .map(|(i, f)| (i, nfc(&f.lower_name())))
        .collect();
    rest.sort_by(|a, b| {
        let (fa, fb) = (&files[a.0], &files[b.0]);
        fb.is_dir.cmp(&fa.is_dir).then_with(|| a.1.cmp(&b.1))
    });
    ord.extend(rest.into_iter().map(|r| r.0));

    let pins: HashSet<String> = read_lines(&dir.join(PINNED)).iter().map(|l| nfc(l)).collect();
    let mut slots: Vec<Option<TreeEntry>> = files.into_iter().map(Some).collect();
    let mut all: Vec<TreeEntry> = ord.into_iter().filter_map(|i| slots[i].take()).collect();
    if pins.is_empty() {
        return all;
    }
    for e in all.iter_mut() {
        e.pinned = pins.contains(&nfc(&e.name));
    }
    let (mut first, rest): (Vec<_>, Vec<_>) = all.into_iter().partition(|e| e.pinned);
    first.extend(rest);
    first
}

/// Tüm ağacı dolaşır (klasör, ardından içeriği). Her öğe için üst klasörlerinin dizin numaraları da döner.
/// `alive` false olursa dolaşım yarıda kesilir.
pub fn walk(root: &Path, alive: &dyn Fn() -> bool) -> (Vec<TreeEntry>, Vec<Vec<usize>>) {
    fn go(
        dir: &Path,
        chain: &mut Vec<usize>,
        entries: &mut Vec<TreeEntry>,
        chains: &mut Vec<Vec<usize>>,
        alive: &dyn Fn() -> bool,
    ) {
        if chain.len() >= MAX_DEPTH {
            return;
        }
        for e in list(dir) {
            if !alive() {
                return;
            }
            let (is_dir, path) = (e.is_dir, e.path.clone());
            entries.push(e);
            chains.push(chain.clone());
            if is_dir {
                chain.push(entries.len() - 1);
                go(Path::new(&path), chain, entries, chains, alive);
                chain.pop();
            }
        }
    }
    let (mut entries, mut chains) = (Vec::new(), Vec::new());
    go(root, &mut Vec::new(), &mut entries, &mut chains, alive);
    (entries, chains)
}

pub struct TreeHit {
    pub hit: Hit,
    pub entry: TreeEntry,
    pub ancestors: Vec<TreeEntry>,
}

/// Dolaşım + paralel arama. Sonuç sırası ve 500 sınırı `search::search` ile aynıdır.
pub fn search_tree(root: &Path, query: &str, alive: &(dyn Fn() -> bool + Sync)) -> Vec<TreeHit> {
    if search::terms(query).is_empty() {
        return Vec::new();
    }
    let (entries, chains) = walk(root, alive);
    let items: Vec<Item> = entries
        .iter()
        .map(|e| Item {
            kind: if e.is_dir { KIND_DIR } else if e.is_txt() { KIND_TXT } else { KIND_URL },
            path: e.path.clone(),
            title: e.title(),
        })
        .collect();
    search::search(&items, query, alive)
        .into_iter()
        .map(|h| TreeHit {
            entry: entries[h.index].clone(),
            ancestors: chains[h.index].iter().map(|&i| entries[i].clone()).collect(),
            hit: h,
        })
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::fs;

    fn tmp(name: &str) -> std::path::PathBuf {
        let d = std::env::temp_dir().join(format!("plan_core_tree_{}_{}", name, std::process::id()));
        let _ = fs::remove_dir_all(&d);
        fs::create_dir_all(&d).unwrap();
        d
    }
    fn names(v: &[TreeEntry]) -> Vec<&str> {
        v.iter().map(|e| e.name.as_str()).collect()
    }

    #[test]
    fn default_order_dirs_first_then_name_and_filters() {
        let d = tmp("order");
        fs::create_dir(d.join("Zeta")).unwrap();
        fs::create_dir(d.join("alfa")).unwrap();
        for f in ["b.url", "A.TXT", "x.png", ".gizli.txt"] {
            fs::write(d.join(f), "x").unwrap();
        }
        let l = list(&d);
        assert_eq!(names(&l), vec!["alfa", "Zeta", "A.TXT", "b.url"]);
        assert_eq!(l[2].title(), "A");
        assert!(l[2].is_txt());
        let _ = fs::remove_dir_all(&d);
    }

    #[test]
    fn order_file_wins_and_unlisted_follow() {
        let d = tmp("ordfile");
        for f in ["a.url", "b.url", "c.url"] {
            fs::write(d.join(f), "x").unwrap();
        }
        fs::write(d.join(ORDER), "c.url\r\nyok.url\nb.url\nc.url\n\n").unwrap();
        assert_eq!(names(&list(&d)), vec!["c.url", "b.url", "a.url"]);
        let _ = fs::remove_dir_all(&d);
    }

    #[test]
    fn pinned_go_first_keeping_relative_order() {
        let d = tmp("pin");
        for f in ["a.url", "b.url", "c.url"] {
            fs::write(d.join(f), "x").unwrap();
        }
        fs::write(d.join(PINNED), "c.url\nb.url").unwrap();
        let l = list(&d);
        assert_eq!(names(&l), vec!["b.url", "c.url", "a.url"]);
        assert_eq!(l.iter().map(|e| e.pinned).collect::<Vec<_>>(), vec![true, true, false]);
        let _ = fs::remove_dir_all(&d);
    }

    #[test]
    fn nfc_matching_between_order_file_and_disk() {
        let d = tmp("nfc");
        fs::write(d.join("Çay.url"), "x").unwrap(); // NFC
        fs::write(d.join("zz.url"), "x").unwrap();
        fs::write(d.join(ORDER), "zz.url\nC\u{0327}ay.url\n").unwrap(); // NFD yazılmış
        assert_eq!(names(&list(&d)), vec!["zz.url", "Çay.url"]);
        let _ = fs::remove_dir_all(&d);
    }

    #[test]
    fn search_tree_reports_ancestors() {
        let d = tmp("search");
        fs::create_dir(d.join("Work")).unwrap();
        fs::write(d.join("Work/Swift Docs.url"), "[InternetShortcut]\r\nURL=https://x.y/swift\r\n").unwrap();
        fs::write(d.join("Çalışma Notları.url"), "[InternetShortcut]\r\nTEXT=Çalışma Notları\r\n").unwrap();
        let a = search_tree(&d, "SWIFT", &|| true);
        assert_eq!(a.len(), 1);
        assert_eq!(a[0].entry.title(), "Swift Docs");
        assert_eq!(names(&a[0].ancestors), vec!["Work"]);
        assert_eq!(search_tree(&d, "calisma notlari", &|| true).len(), 1);
        assert!(search_tree(&d, " ", &|| true).is_empty());
        let _ = fs::remove_dir_all(&d);
    }
}
