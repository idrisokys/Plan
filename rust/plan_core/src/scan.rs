//! Dizin ağacını paralel tarama (symlink izlenmez).

use crate::hash::mtime_secs;
use std::path::PathBuf;
use std::sync::atomic::{AtomicUsize, Ordering};
use std::sync::Mutex;

pub const KIND_FILE: u8 = 0;
pub const KIND_DIR: u8 = 1;
pub const KIND_OTHER: u8 = 2;

#[derive(Debug, Clone)]
pub struct ScanEntry {
    pub kind: u8,
    pub size: u64,
    pub mtime: i64,
    pub path: String,
}

/// `root` altındaki her şeyi (kökün kendisi hariç) listeler; sonuç yola göre sıralıdır.
/// Katman katman ilerler: aynı derinlikteki klasörler iş parçacıklarına paylaştırılır.
pub fn scan(root: &str, include_hidden: bool) -> Vec<ScanEntry> {
    let mut out = Vec::new();
    let mut level = vec![PathBuf::from(root)];
    while !level.is_empty() {
        let next = AtomicUsize::new(0);
        let found: Mutex<Vec<ScanEntry>> = Mutex::new(Vec::new());
        let dirs: Mutex<Vec<PathBuf>> = Mutex::new(Vec::new());
        let n = crate::workers().min(level.len());
        std::thread::scope(|s| {
            for _ in 0..n {
                s.spawn(|| {
                    let (mut f, mut d) = (Vec::new(), Vec::new());
                    loop {
                        let i = next.fetch_add(1, Ordering::Relaxed);
                        if i >= level.len() {
                            break;
                        }
                        let Ok(rd) = std::fs::read_dir(&level[i]) else { continue };
                        for e in rd.flatten() {
                            if !include_hidden && e.file_name().to_string_lossy().starts_with('.') {
                                continue;
                            }
                            let Ok(ft) = e.file_type() else { continue };
                            let meta = e.metadata().ok();
                            let kind = if ft.is_dir() {
                                KIND_DIR
                            } else if ft.is_file() {
                                KIND_FILE
                            } else {
                                KIND_OTHER
                            };
                            if kind == KIND_DIR {
                                d.push(e.path());
                            }
                            f.push(ScanEntry {
                                kind,
                                size: if kind == KIND_FILE { meta.as_ref().map_or(0, |m| m.len()) } else { 0 },
                                mtime: meta.as_ref().map_or(0, mtime_secs),
                                path: e.path().to_string_lossy().into_owned(),
                            });
                        }
                    }
                    found.lock().unwrap().extend(f);
                    dirs.lock().unwrap().extend(d);
                });
            }
        });
        out.extend(found.into_inner().unwrap());
        level = dirs.into_inner().unwrap();
    }
    out.sort_by(|a, b| a.path.cmp(&b.path));
    out
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::fs;

    #[test]
    fn scans_tree_and_hides_dotfiles() {
        let d = std::env::temp_dir().join(format!("plan_core_scan_{}", std::process::id()));
        let _ = fs::remove_dir_all(&d);
        fs::create_dir_all(d.join("a/b")).unwrap();
        fs::write(d.join("a/b/x.txt"), b"hello").unwrap();
        fs::write(d.join("a/y.url"), b"u").unwrap();
        fs::write(d.join(".gizli"), b"g").unwrap();
        let r = scan(d.to_str().unwrap(), false);
        let names: Vec<_> = r.iter().map(|e| e.path.strip_prefix(d.to_str().unwrap()).unwrap().to_string()).collect();
        assert_eq!(names, vec!["/a", "/a/b", "/a/b/x.txt", "/a/y.url"]);
        let x = r.iter().find(|e| e.path.ends_with("x.txt")).unwrap();
        assert_eq!((x.kind, x.size), (KIND_FILE, 5));
        assert_eq!(scan(d.to_str().unwrap(), true).len(), 5);
        assert!(scan("/yok/boyle/dizin", false).is_empty());
        let _ = fs::remove_dir_all(&d);
    }
}
