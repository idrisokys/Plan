mod common;
use common::Tmp;
use plan_core::config::Settings;
use plan_core::engines::*;
use plan_core::pagetitle::{decode_entities, parse_title};
use plan_core::reorder::*;
use plan_core::Entry;
use std::collections::HashSet;
use std::path::PathBuf;

fn es(names: &[&str]) -> Vec<Entry> {
    names.iter().map(|n| Entry::new(&format!("{n}.url"), PathBuf::from(format!("/t/{n}.url")), false)).collect()
}
fn keys(l: &[Entry]) -> Vec<String> {
    l.iter().map(|e| e.title.clone()).collect()
}
fn sel(l: &[Entry], t: &[&str]) -> HashSet<String> {
    l.iter().filter(|e| t.contains(&e.title.as_str())).map(|e| e.key.clone()).collect()
}

#[test]
fn reorder_up_down_top_bottom() {
    let mut l = es(&["a", "b", "c", "d", "e"]);
    let s = sel(&l, &["b", "d"]);
    assert!(can_move_up(&l, &s) && can_move_down(&l, &s));
    assert!(move_selected(&mut l, &s, -1));
    assert_eq!(keys(&l), ["b", "a", "d", "c", "e"]);
    assert!(move_selected(&mut l, &s, -2));
    assert_eq!(keys(&l), ["b", "d", "a", "c", "e"]);
    assert!(!can_move_up(&l, &s));
    assert!(!move_selected(&mut l, &s, -1));
    assert!(move_selitem(&mut l, &s));
    fn move_selitem(l: &mut Vec<Entry>, s: &HashSet<String>) -> bool {
        move_selected(l, s, 2)
    }
    assert_eq!(keys(&l), ["a", "c", "e", "b", "d"]);
    assert!(!can_move_down(&l, &s));
    assert!(move_selected(&mut l, &s, 1) == false);
    let s2 = sel(&l, &["a"]);
    assert!(move_selected(&mut l, &s2, 1));
    assert_eq!(keys(&l), ["c", "a", "e", "b", "d"]);
}

#[test]
fn engines_urls_and_file() {
    let e = SearchEngine::new("google", "https://www.google.com/search?q=%s");
    assert_eq!(e.letter(), "G");
    assert_eq!(e.search_url("çay & kahve"), "https://www.google.com/search?q=%C3%A7ay%20&%20kahve");
    assert_eq!(SearchEngine::new("x", "https://x.com/?q={q}&a=1").search_url("a b"), "https://x.com/?q=a%20b&a=1");
    assert_eq!(SearchEngine::new("x", "https://x.com/?q=").search_url("a"), "https://x.com/?q=a");
    assert_eq!(SearchEngine::new("  ", "u").letter(), "?");
    let t = Tmp::new();
    let p = t.path().join("sub/engines.tsv");
    let list = vec![e.clone(), SearchEngine::new("b\tad", "https://b/%s")];
    save_engines(&p, &list).unwrap();
    let back = load_engines(&p);
    assert_eq!(back.len(), 2);
    assert_eq!(back[0], e);
    assert_eq!(back[1].name, "b ad");
}

#[test]
fn plan_urls() {
    assert_eq!(
        parse_plan_url("plan://add?t=https%3A%2F%2Fex.com%2Fa%3Fb%3D1&s=Ba%C5%9Fl%C4%B1k%20x"),
        Some(UrlAction::Add { text: "https://ex.com/a?b=1".into(), subject: Some("Başlık x".into()) })
    );
    assert_eq!(parse_plan_url("plan://add?t=hi"), Some(UrlAction::Add { text: "hi".into(), subject: None }));
    assert_eq!(parse_plan_url("plan://search?q=%C3%A7ay"), Some(UrlAction::Search("çay".into())));
    assert_eq!(
        parse_plan_url("plan://send?f=%2Ftmp%2Fa&f=%2Ftmp%2Fb%20c"),
        Some(UrlAction::Send(vec!["/tmp/a".into(), "/tmp/b c".into()]))
    );
    assert_eq!(parse_plan_url("plan://add"), None);
    assert_eq!(parse_plan_url("http://x"), None);
}

#[test]
fn settings_persist() {
    let t = Tmp::new();
    let p = t.path().join("c/settings.conf");
    let mut s = Settings::load_from(&p);
    assert!(!s.qs_on());
    assert_eq!(s.font_size(), 16.0);
    let id = s.qs_id();
    assert_eq!(id.len(), 32);
    s.set_qs_on(true);
    s.set_always_on_top(true);
    assert_eq!(s.bump_font(100.0), 32.0);
    assert_eq!(s.bump_font(-100.0), 10.0);
    let mut s2 = Settings::load_from(&p);
    assert_eq!(s2.qs_id(), id);
    assert!(s2.qs_on() && s2.always_on_top());
    assert_eq!(s2.font_size(), 10.0);
    assert_ne!(plan_core::config::random_hex32(), plan_core::config::random_hex32());
}

#[test]
fn page_title_parsing() {
    let html = b"<html><head><TITLE>\n  Merhaba &amp; D\xc3\xbcnya &#350;&#x131; \n</TITLE></head>";
    assert_eq!(parse_title(html, Some("text/html; charset=utf-8")).as_deref(), Some("Merhaba & Dünya Şı"));
    // Türkçe ISO-8859-9, meta charset ile
    let mut t9 = b"<meta charset=\"iso-8859-9\"><title>".to_vec();
    t9.extend_from_slice(&[0xDD, b's', b't', b'a', b'n', b'b', b'u', b'l', b' ', 0xFE, 0xF0, 0xFD]);
    t9.extend_from_slice(b"</title>");
    assert_eq!(parse_title(&t9, None).as_deref(), Some("İstanbul şğı"));
    // başlık yoksa og:title
    let og = b"<head><meta property=\"og:title\" content=\"OG Ba\xc5\x9fl\xc4\xb1k\"></head>";
    assert_eq!(parse_title(og, None).as_deref(), Some("OG Başlık"));
    let og2 = b"<meta content='Ters Sira' name='twitter:title'>";
    assert_eq!(parse_title(og2, None).as_deref(), Some("Ters Sira"));
    // engel sayfaları reddedilir
    assert_eq!(parse_title(b"<title>Just a moment...</title>", None), None);
    assert_eq!(parse_title(b"<title>  </title>", None), None);
    assert_eq!(parse_title(b"<p>yok</p>", None), None);
    assert_eq!(decode_entities("a&nbsp;b &lt;x&gt; &#9731; &bogus; &#xZZ;"), "a b <x> ☃ &bogus; &#xZZ;");
}
