mod common;
use common::Tmp;
use plan_core::quickshare::{send_files, Event, Server, ServerConfig};
use plan_core::store;
use plan_core::sync::{self, Peer};
use std::fs;
use std::sync::{Arc, Mutex};

fn names(root: &std::path::Path) -> Vec<String> {
    sync::local(root).keys().cloned().collect()
}

fn start(root: &std::path::Path, recv: &std::path::Path, trash: &std::path::Path) -> (Server, Arc<Mutex<Vec<Event>>>) {
    let evs = Arc::new(Mutex::new(vec![]));
    let e2 = evs.clone();
    let srv = Server::start(
        ServerConfig { root: root.into(), receive_dir: recv.into(), trash_dir: trash.into() },
        0,
        Arc::new(move |e| e2.lock().unwrap().push(e)),
    )
    .unwrap();
    (srv, evs)
}

fn peer(srv: &Server) -> Peer {
    Peer { id: "x".into(), name: "test".into(), addr: format!("127.0.0.1:{}", srv.port) }
}

#[test]
fn resolve_rejects_escapes() {
    let t = Tmp::new();
    let r = t.path();
    assert!(sync::resolve("../evil.url", r, false).is_none());
    assert!(sync::resolve("a/../../evil.url", r, false).is_none());
    assert!(sync::resolve("note.exe", r, false).is_none());
    assert!(sync::resolve("a\\b.url", r, false).is_none());
    assert!(sync::resolve("a//b.url", r, false).is_none());
    assert!(sync::resolve("/abs.url", r, false).is_none());
    assert!(sync::resolve("x.url.part", r, false).is_none());
    assert!(sync::resolve(".pinned.txt", r, false).is_none());
    assert!(sync::resolve("folder/note.url", r, false).is_some());
    assert!(sync::resolve("folder/.order.txt", r, false).is_some());
    assert!(sync::resolve("a/b/c", r, true).is_some());
    assert!(sync::resolve(&"a/".repeat(30), r, true).is_none());
}

#[cfg(unix)]
#[test]
fn resolve_rejects_symlink_escape() {
    let t = Tmp::new();
    let outside = Tmp::new();
    std::os::unix::fs::symlink(outside.path(), t.path().join("link")).unwrap();
    assert!(sync::resolve("link/evil.url", t.path(), false).is_none());
}

#[test]
fn manifest_round_trip() {
    let t = Tmp::new();
    let sub = store::add_folder(t.path(), "Klasör ş").unwrap();
    assert!(store::add_note(&sub, "merhaba dünya"));
    store::set_pinned(t.path(), &["x.url".into()], true); // .pinned.txt eşitlenmemeli
    let m = sync::local(t.path());
    assert!(m.keys().all(|k| !k.contains(".pinned")));
    let back = sync::parse_manifest(&sync::manifest_body(&m));
    assert_eq!(m, back);
    assert!(back.contains_key("Klasör ş") && back["Klasör ş"].dir);
}

#[test]
fn merge_sync_both_ways() {
    let (a, b, recv, trash) = (Tmp::new(), Tmp::new(), Tmp::new(), Tmp::new());
    assert!(store::add_note(a.path(), "sadece A'da"));
    let sub = store::add_folder(a.path(), "Ortak").unwrap();
    assert!(store::add_link(&sub, "Derin", "https://a.example.com"));
    assert!(store::add_note(b.path(), "sadece B'de"));
    let (srv, evs) = start(b.path(), recv.path(), trash.path());
    let out = sync::run(0, &[peer(&srv)], a.path(), trash.path());
    assert!(out.ok(), "{:?}", out);
    // gönderilen: A'nın notu + Ortak/Derin.url + Ortak/.order.txt; alınan: B'nin notu
    assert_eq!((out.peers, out.sent, out.got), (1, 3, 1));
    assert_eq!(names(a.path()), names(b.path()));
    assert!(names(b.path()).contains(&"Ortak/Derin.url".to_string()));
    assert!(evs.lock().unwrap().iter().any(|e| matches!(e, Event::NotesChanged)));
    // ikinci eşitleme: değişiklik yok
    let out = sync::run(0, &[peer(&srv)], a.path(), trash.path());
    assert_eq!((out.sent, out.got), (0, 0), "{:?}", out);
}

#[test]
fn newer_mtime_wins() {
    let (a, b, recv, trash) = (Tmp::new(), Tmp::new(), Tmp::new(), Tmp::new());
    fs::write(a.path().join("n.txt"), "eski").unwrap();
    fs::write(b.path().join("n.txt"), "yeni").unwrap();
    let old = std::time::SystemTime::now() - std::time::Duration::from_secs(3600);
    fs::OpenOptions::new().write(true).open(a.path().join("n.txt")).unwrap().set_modified(old).unwrap();
    let (srv, _) = start(b.path(), recv.path(), trash.path());
    let out = sync::run(0, &[peer(&srv)], a.path(), trash.path());
    assert_eq!((out.sent, out.got), (0, 1), "{:?}", out);
    assert_eq!(fs::read_to_string(a.path().join("n.txt")).unwrap(), "yeni");
}

#[test]
fn mirror_modes() {
    let (a, b, recv, trash_a, trash_b) = (Tmp::new(), Tmp::new(), Tmp::new(), Tmp::new(), Tmp::new());
    assert!(store::add_note(a.path(), "A notu"));
    let d = store::add_folder(a.path(), "Dir").unwrap();
    assert!(store::add_note(&d, "içeride"));
    assert!(store::add_note(b.path(), "B fazlalığı"));
    let bd = store::add_folder(b.path(), "Eski").unwrap();
    assert!(store::add_note(&bd, "gidecek"));
    let (srv, _) = start(b.path(), recv.path(), trash_b.path());

    // 1: karşıdaki (B) bu cihazın (A) aynısı olur; B'de fazlalıklar B'nin çöpüne gider
    let out = sync::run(1, &[peer(&srv)], a.path(), trash_a.path());
    assert!(out.ok(), "{:?}", out);
    let nb: Vec<String> = names(b.path()).into_iter().filter(|n| !n.starts_with("Eski")).collect();
    assert_eq!(names(a.path()), nb);
    assert!(!names(b.path()).iter().any(|n| n.starts_with("Eski") || n.contains("fazlalığı")));
    assert!(trash_b.path().join("Eski").is_dir());

    // 2: bu cihaz (A) karşıdakinin aynısı olur: önce A'ya fazlalık ekle
    assert!(store::add_note(a.path(), "A'ya sonradan"));
    let out = sync::run(2, &[peer(&srv)], a.path(), trash_a.path());
    assert!(out.ok(), "{:?}", out);
    assert_eq!(names(a.path()), names(b.path()));
    assert!(fs::read_dir(trash_a.path()).unwrap().count() >= 1);
}

#[test]
fn no_peers_and_unreachable() {
    let (a, trash) = (Tmp::new(), Tmp::new());
    let o = sync::run(0, &[], a.path(), trash.path());
    assert!(o.error.is_some());
    // kapalı port
    let l = std::net::TcpListener::bind("127.0.0.1:0").unwrap();
    let addr = l.local_addr().unwrap().to_string();
    drop(l);
    let o = sync::run(0, &[Peer { id: "x".into(), name: "ölü".into(), addr }], a.path(), trash.path());
    assert_eq!(o.peers, 0);
    assert!(!o.errors.is_empty());
}

#[test]
fn plain_file_receive_and_dedupe() {
    let (root, recv, trash, src) = (Tmp::new(), Tmp::new(), Tmp::new(), Tmp::new());
    let (srv, evs) = start(root.path(), recv.path(), trash.path());
    let f = src.path().join("rapor ş.pdf");
    fs::write(&f, vec![7u8; 3_000_000]).unwrap();
    let addr = format!("127.0.0.1:{}", srv.port);
    assert_eq!(send_files(&[f.clone(), f.clone()], &addr), 2);
    assert_eq!(fs::metadata(recv.path().join("rapor ş.pdf")).unwrap().len(), 3_000_000);
    assert!(recv.path().join("rapor ş (2).pdf").exists());
    let evs = evs.lock().unwrap();
    assert!(evs.iter().any(|e| matches!(e, Event::Received { name, .. } if name == "rapor ş.pdf")));
    // klasör zip'lenerek gider (zip/ditto yoksa atlanır)
    drop(evs);
    let dir = src.path().join("klasor");
    fs::create_dir(&dir).unwrap();
    fs::write(dir.join("a.txt"), "x").unwrap();
    if std::process::Command::new("zip").arg("-v").output().is_ok() {
        assert_eq!(send_files(&[dir], &addr), 1);
        assert!(recv.path().join("klasor.zip").exists());
    }
}

#[test]
fn server_rejects_bad_requests() {
    use std::io::{Read, Write};
    let (root, recv, trash) = (Tmp::new(), Tmp::new(), Tmp::new());
    let (srv, _) = start(root.path(), recv.path(), trash.path());
    let req = |r: &str| -> String {
        let mut s = std::net::TcpStream::connect(("127.0.0.1", srv.port)).unwrap();
        s.write_all(r.as_bytes()).unwrap();
        let _ = s.shutdown(std::net::Shutdown::Write);
        let mut out = String::new();
        let _ = s.read_to_string(&mut out);
        out
    };
    assert!(req("POST /u HTTP/1.1\r\nX-Name: a\r\n\r\n").starts_with("HTTP/1.1 400"));
    assert!(req("GET /nope HTTP/1.1\r\n\r\n").starts_with("HTTP/1.1 500"));
    // eşitleme yolu kökün dışına çıkamaz
    assert!(req("POST /u HTTP/1.1\r\nX-Sync: 1\r\nX-Name: ..%2Fevil.url\r\nContent-Length: 1\r\n\r\nx").starts_with("HTTP/1.1 400"));
    assert!(req("GET /f HTTP/1.1\r\nX-Name: ..%2F..%2Fetc%2Fpasswd\r\n\r\n").starts_with("HTTP/1.1 404"));
    // DELETE /x (eski sürüm uyumu): var olmayan öğe → 200
    assert!(req("DELETE /x HTTP/1.1\r\nX-Name: yok.url\r\nX-Dir: 0\r\n\r\n").starts_with("HTTP/1.1 200"));
    // eksik gövde: dosya bırakılmaz
    let _ = req("POST /u HTTP/1.1\r\nX-Name: yarim.bin\r\nContent-Length: 100\r\n\r\nabc");
    std::thread::sleep(std::time::Duration::from_millis(200));
    assert!(!recv.path().join("yarim.bin").exists());
    assert_eq!(fs::read_dir(recv.path()).unwrap().count(), 0);
}

#[test]
fn clean_name_and_unique() {
    use plan_core::quickshare::clean_name;
    assert_eq!(clean_name("../../etc/passwd"), "passwd");
    assert_eq!(clean_name("C:\\x\\y:z.txt"), "y_z.txt");
    assert_eq!(clean_name("...gizli"), "gizli");
    assert_eq!(clean_name(""), "file");
    assert_eq!(clean_name(&"a".repeat(200)).len(), 120);
}
