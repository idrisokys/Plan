//! Arama motorları (kullanıcının eklediği) ve adres şeması (plan://add, search, send).

use crate::text::{encode_query, percent_decode};
use std::path::Path;

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct SearchEngine {
    pub id: String,
    pub name: String,
    /// %s veya {q} sorgunun yerine geçer; yoksa sorgu sona eklenir.
    pub url: String,
}

impl SearchEngine {
    pub fn new(name: &str, url: &str) -> SearchEngine {
        SearchEngine { id: crate::store::unique_suffix(), name: name.trim().to_string(), url: url.trim().to_string() }
    }

    pub fn letter(&self) -> String {
        self.name.trim().chars().next().map(|c| c.to_uppercase().to_string()).unwrap_or_else(|| "?".into())
    }

    pub fn search_url(&self, query: &str) -> String {
        let q = encode_query(query);
        if self.url.contains("%s") {
            self.url.replace("%s", &q)
        } else if self.url.contains("{q}") {
            self.url.replace("{q}", &q)
        } else {
            format!("{}{}", self.url, q)
        }
    }
}

/// Dosya biçimi: her satır `id<TAB>ad<TAB>adres`.
pub fn load_engines(path: &Path) -> Vec<SearchEngine> {
    let Ok(s) = std::fs::read_to_string(path) else { return vec![] };
    s.lines()
        .filter_map(|l| {
            let mut p = l.splitn(3, '\t');
            let (id, name, url) = (p.next()?, p.next()?, p.next()?);
            Some(SearchEngine { id: id.into(), name: name.into(), url: url.into() })
        })
        .collect()
}

pub fn save_engines(path: &Path, engines: &[SearchEngine]) -> std::io::Result<()> {
    let clean = |s: &str| s.replace(['\t', '\n', '\r'], " ");
    let body: String = engines.iter().map(|e| format!("{}\t{}\t{}\n", clean(&e.id), clean(&e.name), clean(&e.url))).collect();
    if let Some(d) = path.parent() {
        std::fs::create_dir_all(d)?;
    }
    crate::store::atomic_write(path, body.as_bytes())
}

/// plan:// adreslerinin anlamı.
#[derive(Debug, PartialEq, Eq)]
pub enum UrlAction {
    /// plan://add?t=…&s=… (t: metin/link, s: tarayıcının verdiği sayfa başlığı)
    Add { text: String, subject: Option<String> },
    /// plan://search?q=…
    Search(String),
    /// plan://send?f=<yol>&f=<yol>
    Send(Vec<String>),
}

fn query_items(q: &str) -> Vec<(String, String)> {
    q.split('&')
        .filter(|p| !p.is_empty())
        .map(|p| {
            let (k, v) = p.split_once('=').unwrap_or((p, ""));
            (percent_decode(k).unwrap_or_else(|| k.into()), percent_decode(v).unwrap_or_else(|| v.into()))
        })
        .collect()
}

pub fn parse_plan_url(u: &str) -> Option<UrlAction> {
    let rest = u.strip_prefix("plan://")?;
    let (host, query) = rest.split_once('?').unwrap_or((rest, ""));
    let host = host.trim_end_matches('/');
    let items = query_items(query);
    let get = |k: &str| items.iter().find(|(n, _)| n == k).map(|(_, v)| v.clone());
    match host {
        "search" => get("q").map(UrlAction::Search),
        "send" => Some(UrlAction::Send(items.iter().filter(|(n, _)| n == "f").map(|(_, v)| v.clone()).collect())),
        _ => get("t").map(|text| UrlAction::Add { text, subject: get("s") }),
    }
}
