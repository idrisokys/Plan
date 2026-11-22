use std::path::PathBuf;

/// Listedeki bir öğe: klasör, .url (link / kısa not) ya da .txt.
#[derive(Clone, Debug, PartialEq, Eq, Hash)]
pub struct Entry {
    pub name: String,
    pub path: PathBuf,
    pub is_dir: bool,
    /// Liste anahtarı (yol).
    pub key: String,
    /// Düz metin dosyası (.txt) mı?
    pub is_txt: bool,
    /// Listede gösterilen ad (uzantısız).
    pub title: String,
    pub ext: &'static str,
    /// Sabitlenmiş mi? (listenin başında durur)
    pub pinned: bool,
}

/// Son 4 bayt (ASCII) verilen uzantıya büyük/küçük harf duyarsız eşit mi?
pub fn has_ext(name: &str, ext: &str) -> bool {
    let n = name.len();
    let e = ext.len();
    n >= e && name.is_char_boundary(n - e) && name[n - e..].eq_ignore_ascii_case(ext)
}

impl Entry {
    pub fn new(name: &str, path: PathBuf, is_dir: bool) -> Entry {
        let txt = !is_dir && has_ext(name, ".txt");
        let titled = !is_dir && (has_ext(name, ".url") || txt);
        Entry {
            name: name.to_string(),
            key: path.to_string_lossy().into_owned(),
            path,
            is_dir,
            is_txt: txt,
            title: if titled { name[..name.len() - 4].to_string() } else { name.to_string() },
            ext: if txt { ".txt" } else { ".url" },
            pinned: false,
        }
    }
}

/// Arama sonucu: bulunan öğe, bulunduğu klasör zinciri ve gösterilecek özet.
#[derive(Clone, Debug)]
pub struct Hit {
    pub entry: Entry,
    pub path: Vec<Entry>,
    pub detail: String,
    pub is_note: bool,
    pub title_match: bool,
}
