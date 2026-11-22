mod common;
use common::Tmp;
use plan_core::search::{search, txt_matches};
use plan_core::store::*;
use plan_core::text::*;
use plan_core::Entry;
use std::path::PathBuf;

fn titles(d: &std::path::Path) -> Vec<String> {
    list(d).into_iter().map(|e| e.title).collect()
}

#[test]
fn add_link_round_trip() {
    let t = Tmp::new();
    assert!(add_link(t.path(), "Example: Site", "https://example.com"));
    let items = list(t.path());
    assert_eq!(items.len(), 1);
    assert_eq!(items[0].title, "Example - Site");
    assert_eq!(read_link(&items[0].path).0.as_deref(), Some("https://example.com"));
}

#[test]
fn new_items_go_to_top() {
    let t = Tmp::new();
    for n in ["b", "a", "c"] {
        assert!(add_link(t.path(), n, &format!("https://example.com/{n}")));
    }
    assert_eq!(titles(t.path()), ["c", "a", "b"]);
    assert!(add_folder(t.path(), "Klasör").is_some());
    assert_eq!(titles(t.path())[0], "Klasör");
}

#[test]
fn duplicate_titles_get_number_suffix() {
    let t = Tmp::new();
    assert!(add_link(t.path(), "b", "https://example.com/1"));
    assert!(add_link(t.path(), "b", "https://example.com/2"));
    assert_eq!(titles(t.path()), ["b (2)", "b"]);
}

#[test]
fn note_keeps_newlines() {
    let t = Tmp::new();
    assert!(add_note(t.path(), "line1\nline2"));
    let e = &list(t.path())[0];
    let (url, text) = read_link(&e.path);
    assert!(url.is_none());
    assert_eq!(text.as_deref(), Some("line1\nline2"));
}

#[test]
fn note_with_backslash_round_trips() {
    let t = Tmp::new();
    assert!(add_note(t.path(), "a\\nb \\ c"));
    let e = &list(t.path())[0];
    assert_eq!(read_link(&e.path).1.as_deref(), Some("a\\nb \\ c"));
}

#[test]
fn text_file_round_trip() {
    let t = Tmp::new();
    assert!(add_text_file(t.path(), "hello world"));
    let e = list(t.path()).remove(0);
    assert!(e.is_txt);
    assert_eq!(read_plain(&e.path).as_deref(), Some("hello world"));
    assert!(write_plain(&e.path, "changed"));
    assert_eq!(read_plain(&e.path).as_deref(), Some("changed"));
}

#[test]
fn rename_keeps_extension() {
    let t = Tmp::new();
    assert!(add_link(t.path(), "old", "https://example.com"));
    let e = list(t.path()).remove(0);
    assert!(rename(t.path(), &e, "new"));
    let after = list(t.path());
    assert_eq!(after.iter().map(|e| e.title.clone()).collect::<Vec<_>>(), ["new"]);
    assert_eq!(after[0].name, "new.url");
}

#[test]
fn rename_note_updates_content() {
    let t = Tmp::new();
    assert!(add_note(t.path(), "old text"));
    let e = list(t.path()).remove(0);
    assert!(rename(t.path(), &e, "new text"));
    let after = list(t.path()).remove(0);
    assert_eq!(read_link(&after.path).1.as_deref(), Some("new text"));
}

#[test]
fn rename_case_only_and_conflict() {
    let t = Tmp::new();
    assert!(add_link(t.path(), "abc", "https://e.com/1"));
    assert!(add_link(t.path(), "xyz", "https://e.com/2"));
    let e = list(t.path()).into_iter().find(|e| e.title == "abc").unwrap();
    assert!(rename(t.path(), &e, "ABC"));
    assert!(titles(t.path()).contains(&"ABC".to_string()));
    let e = list(t.path()).into_iter().find(|e| e.title == "xyz").unwrap();
    assert!(!rename(t.path(), &e, "abc")); // çakışma
}

#[test]
fn convert_to_txt_keeps_position() {
    let t = Tmp::new();
    for (n, i) in [("first", 1), ("second", 2), ("third", 3)] {
        assert!(add_link(t.path(), n, &format!("https://example.com/{i}")));
    }
    let e = list(t.path()).remove(1);
    assert!(convert_to_txt(t.path(), &e, "long text\nhttps://example.com/2"));
    let after = list(t.path());
    assert_eq!(after.len(), 3);
    assert!(after[1].is_txt);
    assert_eq!(read_plain(&after[1].path).as_deref(), Some("long text\nhttps://example.com/2"));
}

#[test]
fn move_and_trash_and_pin() {
    let t = Tmp::new();
    let sub = add_folder(t.path(), "Work").unwrap();
    assert!(add_link(t.path(), "a", "https://e.com/a"));
    assert!(add_link(t.path(), "b", "https://e.com/b"));
    let a = list(t.path()).into_iter().find(|e| e.title == "a").unwrap();
    assert!(move_entry(&a, &sub));
    assert_eq!(titles(&sub), ["a"]);
    // klasörü kendi içine taşıma reddedilir
    let work = list(t.path()).into_iter().find(|e| e.is_dir).unwrap();
    assert!(!move_entry(&work, &sub));
    // sabitleme: sabitlenen başa gelir
    assert!(add_link(t.path(), "c", "https://e.com/c"));
    set_pinned(t.path(), &["b.url".to_string()], true);
    assert_eq!(list(t.path())[0].title, "b");
    assert!(list(t.path())[0].pinned);
    // sil = çöp klasörüne taşı, ad çakışırsa _1
    let trash_dir = t.path().join("_trash");
    let b = list(t.path())[0].clone();
    assert!(trash_to(&b.path, &trash_dir));
    assert!(add_link(t.path(), "b", "https://e.com/b2"));
    let b2 = list(t.path()).into_iter().find(|e| e.title == "b").unwrap();
    assert!(trash_to(&b2.path, &trash_dir));
    assert!(trash_dir.join("b.url").exists() && trash_dir.join("b_1.url").exists());
    // sabitleme kaydı da temizlenir
    assert!(!list(t.path()).iter().any(|e| e.pinned));
}

#[test]
fn search_across_folders_and_turkish_letters() {
    let t = Tmp::new();
    let sub = add_folder(t.path(), "Work").unwrap();
    assert!(add_link(&sub, "Swift Docs", "https://developer.apple.com/swift"));
    assert!(add_note(t.path(), "Çalışma Notları"));
    let a = search(t.path(), "SWIFT", &|| true);
    assert_eq!(a.len(), 1);
    assert_eq!(a[0].entry.title, "Swift Docs");
    assert_eq!(a[0].path.iter().map(|e| e.name.clone()).collect::<Vec<_>>(), ["Work"]);
    assert_eq!(search(t.path(), "calisma notlari", &|| true).len(), 1);
    assert_eq!(search(t.path(), "yok böyle", &|| true).len(), 0);
}

#[test]
fn search_snippet_and_title_first() {
    let t = Tmp::new();
    assert!(add_text_file(t.path(), &format!("{} needle {}", "x ".repeat(60), "y ".repeat(60))));
    assert!(add_note(t.path(), "needle başlık"));
    let hits = search(t.path(), "needle", &|| true);
    assert_eq!(hits.len(), 2);
    assert!(hits[0].title_match); // başlıkta geçen önce
    let txt = hits.iter().find(|h| h.entry.is_txt).unwrap();
    assert!(txt.detail.starts_with('…') && txt.detail.contains("needle"));
}

#[test]
fn search_cancel() {
    let t = Tmp::new();
    assert!(add_note(t.path(), "abc"));
    assert!(search(t.path(), "abc", &|| false).is_empty());
}

#[test]
fn txt_search_fold_keeps_length() {
    let s = "İstanbul ŞĞÜÖÇ ıI";
    assert_eq!(fk(s).chars().count(), s.chars().count());
    let m = txt_matches("Çiçek çiçek ÇİÇEK", "cicek");
    assert_eq!(m, vec![(0, 5), (6, 11), (12, 17)]);
}

#[test]
fn submit_rules() {
    let t = Tmp::new();
    let nofetch = |_: &str| -> Option<String> { None };
    assert_eq!(submit_with(t.path(), "kısa bir not", None, &nofetch), SubmitResult::Added);
    assert_eq!(submit_with(t.path(), &"uzun metin ".repeat(40), None, &nofetch), SubmitResult::TextFile);
    let items = list(t.path());
    assert_eq!(items.len(), 2);
    assert_eq!(items.iter().filter(|e| e.is_txt).count(), 1);
    assert_eq!(submit_with(t.path(), "   ", None, &nofetch), SubmitResult::Failed);
}

#[test]
fn submit_link_title_sources() {
    let t = Tmp::new();
    // 1) tarayıcının verdiği başlık
    assert_eq!(submit_with(t.path(), "https://a.com/x", Some("Sayfa Başlığı\nikinci"), &|_| Some("FETCH".into())), SubmitResult::Added);
    // 2) sayfadan alınan başlık
    assert_eq!(submit_with(t.path(), "https://b.com/x", None, &|_| Some("Fetched Title".into())), SubmitResult::Added);
    // 3) yalnızca metin + link: link dışındaki ilk satır
    assert_eq!(submit_with(t.path(), "güzel yazı https://c.com/x", None, &|_| None), SubmitResult::Added);
    // 4) hiçbiri: host
    assert_eq!(submit_with(t.path(), "https://d.example.org/x", None, &|_| None), SubmitResult::Added);
    let mut ts = titles(t.path());
    ts.sort();
    assert_eq!(ts, ["Fetched Title", "Sayfa Başlığı", "d.example.org", "güzel yazı"]);
    // uzun ama boşluksuz link yine link kalır
    let long = format!("https://e.com/{}", "a".repeat(200));
    assert_eq!(submit_with(t.path(), &long, None, &|_| None), SubmitResult::Added);
}

// --- Yardımcılar (StoreHelpersTests) ---

#[test]
fn fold_ignores_turkish_letters_case_and_accents() {
    assert_eq!(fold("İstanbul"), "istanbul");
    assert_eq!(fold("ŞĞÜÖÇı"), "sguoci");
    assert_eq!(fold("Café"), "cafe");
    assert_eq!(fold("Cafe\u{301}"), "cafe"); // ayrık (NFD) aksan
    assert_eq!(fold("s\u{327}"), "s"); // ş (NFD)
}

#[test]
fn nfc_composes_turkish() {
    assert_eq!(nfc("s\u{327}g\u{306}c\u{327}"), "şğç");
    assert_eq!(norm("S\u{327}EKER"), "şeker");
}

#[test]
fn extract_url_strips_trailing_punctuation() {
    assert_eq!(extract_url("bak https://example.com/a?b=1.").as_deref(), Some("https://example.com/a?b=1"));
    assert_eq!(extract_url("(https://example.com/x)").as_deref(), Some("https://example.com/x"));
    assert_eq!(
        extract_url("https://en.wikipedia.org/wiki/Swift_(programming_language)").as_deref(),
        Some("https://en.wikipedia.org/wiki/Swift_(programming_language)")
    );
    assert_eq!(extract_url("burada link yok"), None);
    assert_eq!(extract_url("HTTP://EXAMPLE.COM/a"), Some("HTTP://EXAMPLE.COM/a".into()));
    assert_eq!(extract_url("http:// boş"), None);
    assert_eq!(extract_url("http://a"), None); // 8 karakter ve altı
    assert_eq!(extract_url("http://a.b").as_deref(), Some("http://a.b"));
}

#[test]
fn clean_produces_safe_file_names() {
    assert_eq!(clean("a:b", 80), "a - b");
    assert_eq!(clean("a : b / c", 80), "a - b - c");
    assert_eq!(clean("what?", 80), "what");
    assert_eq!(clean("  ..hidden", 80), "hidden");
    assert_eq!(clean("***", 80), "link");
    assert_eq!(clean(&"a".repeat(300), 10), "a".repeat(10));
    assert_eq!(clean("tab\there\nnew", 80), "tab here new");
}

#[test]
fn fit_bytes_stays_within_limit() {
    let s = "ş".repeat(200);
    assert_eq!(fit_bytes(&s, 240).len(), 240);
    assert_eq!(fit_bytes(&"ş".repeat(121), 241).len(), 240); // karakteri ortadan bölmez
}

#[test]
fn entry_title_and_kind() {
    let d = PathBuf::from("/tmp");
    let link = Entry::new("a.url", d.join("a.url"), false);
    assert_eq!(link.title, "a");
    assert!(!link.is_txt);
    let txt = Entry::new("n.TXT", d.join("n.TXT"), false);
    assert!(txt.is_txt);
    assert_eq!(txt.title, "n");
    assert_eq!(txt.ext, ".txt");
    let folder = Entry::new("Klasör", d.join("Klasör"), true);
    assert_eq!(folder.title, "Klasör");
    let weird = Entry::new("ş.url", d.join("ş.url"), false);
    assert_eq!(weird.title, "ş");
}

#[test]
fn percent_codec() {
    assert_eq!(enc("a b/ç.url"), "a%20b%2Fç.url");
    assert_eq!(dec("a+b%20c%2F"), "a b c/");
    assert_eq!(dec("100%"), "100%"); // geçersiz → olduğu gibi
    assert_eq!(encode_query("a b&ç"), "a%20b&%C3%A7");
    assert_eq!(host_of("https://user@Host.com:8080/x?y").as_deref(), Some("Host.com"));
}
