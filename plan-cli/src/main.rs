//! `plan` — Plan / Notlarım komut satırı arayüzü (aynı çekirdek, GUI'siz).

use plan_core::config::{self, Settings};
use plan_core::engines::{self, UrlAction};
use plan_core::quickshare::{self, Event, Server, ServerConfig};
use plan_core::store::{self, SubmitResult};
use plan_core::sync::{self, Peer};
use plan_core::text::l;
use plan_core::{search, Entry};
use std::path::{Path, PathBuf};
use std::sync::Arc;

fn usage() -> ! {
    eprintln!(
        "{}",
        l(
            "plan — Notlarım komut satırı\n\n\
             KULLANIM: plan <komut> [argümanlar]\n\n\
             \x20 add <metin|link>           Ekle (link → .url, kısa metin → not, uzun → .txt)\n\
             \x20 ls [klasör]                Listele (göreli yol, kök: ~/Link)\n\
             \x20 search <kelimeler…>        Tüm klasörlerde ara\n\
             \x20 cat <klasör/ad>            Bir kaydın içeriğini yaz\n\
             \x20 mkdir <ad>                 Klasör ekle\n\
             \x20 mv <ad> <hedef-klasör>     Taşı\n\
             \x20 rename <ad> <yeni-ad>      Yeniden adlandır\n\
             \x20 pin|unpin <ad>             Sabitle / kaldır\n\
             \x20 rm <ad>                    Sil (~/.onemsiz'e taşır)\n\
             \x20 open <plan://…>            Adres şeması (add / search)\n\
             \x20 serve [--port N]           Hızlı Paylaş: dosya al + eşitleme sunucusu\n\
             \x20 send --peer host:port <dosya…>   Dosya gönder\n\
             \x20 sync --peer host:port [--mode 0|1|2]   Link klasörünü eşitle\n\
             \x20       (0 iki cihazda aynı, 1 bu cihaza göre, 2 karşıdakine göre)\n\n\
             Ortam: PLAN_ROOT (varsayılan ~/Link), PLAN_CONFIG_DIR",
            "plan — My Notes command line\n\n\
             USAGE: plan <command> [args]\n\n\
             \x20 add <text|link>            Add (link → .url, short text → note, long → .txt)\n\
             \x20 ls [folder]                List (relative path, root: ~/Link)\n\
             \x20 search <words…>            Search all folders\n\
             \x20 cat <folder/name>          Print a record's content\n\
             \x20 mkdir <name>               Add a folder\n\
             \x20 mv <name> <target-folder>  Move\n\
             \x20 rename <name> <new-name>   Rename\n\
             \x20 pin|unpin <name>           Pin / unpin\n\
             \x20 rm <name>                  Delete (moves to ~/.onemsiz)\n\
             \x20 open <plan://…>            URL scheme (add / search)\n\
             \x20 serve [--port N]           Quick Share: receive files + sync server\n\
             \x20 send --peer host:port <file…>    Send files\n\
             \x20 sync --peer host:port [--mode 0|1|2]   Sync the Link folder\n\
             \x20       (0 same on both, 1 follow this device, 2 follow the other)\n\n\
             Env: PLAN_ROOT (default ~/Link), PLAN_CONFIG_DIR"
        )
    );
    std::process::exit(2)
}

fn flag(args: &mut Vec<String>, name: &str) -> Option<String> {
    let i = args.iter().position(|a| a == name)?;
    args.remove(i);
    if i < args.len() {
        Some(args.remove(i))
    } else {
        None
    }
}

fn peers(args: &mut Vec<String>) -> Vec<Peer> {
    let mut v = vec![];
    while let Some(a) = flag(args, "--peer") {
        v.push(Peer { id: a.clone(), name: a.clone(), addr: a });
    }
    v
}

fn fail(msg: &str) -> ! {
    eprintln!("{msg}");
    std::process::exit(1)
}

fn root_or_die() -> PathBuf {
    store::root().unwrap_or_else(|| fail(&l("Link klasörü yok ya da yazılamıyor", "Link folder missing or not writable")))
}

/// "a/b/c" → (klasör yolu, ad). Kök altında çözülür; ".." reddedilir.
fn locate(root: &Path, rel: &str) -> (PathBuf, String) {
    if rel.split('/').any(|s| s == "..") {
        fail(&l("Geçersiz yol", "Invalid path"));
    }
    let mut d = root.to_path_buf();
    let mut parts: Vec<&str> = rel.split('/').filter(|s| !s.is_empty()).collect();
    let name = parts.pop().unwrap_or_else(|| fail(&l("Ad gerekli", "Name required"))).to_string();
    for p in parts {
        d.push(p);
    }
    (d, name)
}

/// Ada (uzantılı ya da uzantısız / başlık) göre öğeyi bulur.
fn find_entry(root: &Path, rel: &str) -> Entry {
    let (d, name) = locate(root, rel);
    store::list(&d)
        .into_iter()
        .find(|e| e.name == name || e.title == name)
        .unwrap_or_else(|| fail(&format!("{}: {rel}", l("Bulunamadı", "Not found"))))
}

fn print_entry(e: &Entry) {
    let icon = if e.is_dir {
        "📁"
    } else if e.is_txt {
        "📄"
    } else if store::read_link(&e.path).0.is_some() {
        "🔗"
    } else {
        "📝"
    };
    println!("{}{} {}", if e.pinned { "📌" } else { "  " }, icon, e.title);
}

fn main() {
    let mut args: Vec<String> = std::env::args().skip(1).collect();
    if args.is_empty() {
        usage();
    }
    let cmd = args.remove(0);
    match cmd.as_str() {
        "add" => {
            let text = args.join(" ");
            let root = root_or_die();
            match store::submit(&root, &text, None) {
                SubmitResult::Added => println!("{}", l("Eklendi", "Added")),
                SubmitResult::TextFile => println!("{}", l("Metin dosyası eklendi", "Text file added")),
                SubmitResult::Failed => fail(&l("Kaydedilemedi", "Couldn't save")),
            }
        }
        "ls" => {
            let root = root_or_die();
            let dir = match args.first() {
                Some(p) => {
                    let (d, n) = locate(&root, p);
                    d.join(n)
                }
                None => root,
            };
            for e in store::list(&dir) {
                print_entry(&e);
            }
        }
        "search" => {
            let root = root_or_die();
            let hits = search::search(&root, &args.join(" "), &|| true);
            for h in &hits {
                let path: Vec<&str> = h.path.iter().map(|e| e.name.as_str()).collect();
                let where_ = if path.is_empty() { String::new() } else { format!("{}/", path.join("/")) };
                println!("{where_}{}\n    {}", h.entry.title, h.detail);
            }
            eprintln!("{} {}", hits.len(), l("sonuç", "results"));
        }
        "cat" => {
            let root = root_or_die();
            let e = find_entry(&root, args.first().map(|s| s.as_str()).unwrap_or_else(|| usage()));
            if e.is_dir {
                fail(&l("Klasör", "Is a folder"));
            }
            if e.is_txt {
                print!("{}", store::read_plain(&e.path).unwrap_or_default());
            } else {
                let (u, t) = store::read_link(&e.path);
                println!("{}", u.or(t).unwrap_or_default());
            }
        }
        "mkdir" => {
            let root = root_or_die();
            let (d, n) = locate(&root, args.first().map(|s| s.as_str()).unwrap_or_else(|| usage()));
            if store::add_folder(&d, &n).is_none() {
                fail(&l("Klasör eklenemedi", "Couldn't add folder"));
            }
        }
        "mv" => {
            if args.len() != 2 {
                usage()
            }
            let root = root_or_die();
            let e = find_entry(&root, &args[0]);
            let (d, n) = locate(&root, &args[1]);
            if !store::move_entry(&e, &d.join(n)) {
                fail(&l("Taşınamadı", "Couldn't move"));
            }
        }
        "rename" => {
            if args.len() != 2 {
                usage()
            }
            let root = root_or_die();
            let e = find_entry(&root, &args[0]);
            let dir = e.path.parent().unwrap().to_path_buf();
            if !store::rename(&dir, &e, &args[1]) {
                fail(&l("Ad değiştirilemedi (aynı adda öğe olabilir)", "Couldn't rename (an item with that name may exist)"));
            }
        }
        "pin" | "unpin" => {
            let root = root_or_die();
            let e = find_entry(&root, args.first().map(|s| s.as_str()).unwrap_or_else(|| usage()));
            store::set_pinned(e.path.parent().unwrap(), &[e.name.clone()], cmd == "pin");
        }
        "rm" => {
            let root = root_or_die();
            let e = find_entry(&root, args.first().map(|s| s.as_str()).unwrap_or_else(|| usage()));
            if store::trash(&e.path) {
                println!("{}", l(".onemsiz klasörüne taşındı", "Moved to .onemsiz"));
            } else {
                fail(&l("Taşınamadı", "Couldn't move"));
            }
        }
        "open" => {
            let root = root_or_die();
            match args.first().and_then(|u| engines::parse_plan_url(u)) {
                Some(UrlAction::Add { text, subject }) => {
                    let r = store::submit(&root, &text, subject.as_deref());
                    println!("{r:?}");
                }
                Some(UrlAction::Search(q)) => {
                    for h in search::search(&root, &q, &|| true) {
                        println!("{}", h.entry.title);
                    }
                }
                Some(UrlAction::Send(f)) => println!("{}", f.join("\n")),
                None => usage(),
            }
        }
        "serve" => {
            let port: u16 = flag(&mut args, "--port").and_then(|p| p.parse().ok()).unwrap_or(0);
            let root = root_or_die();
            let mut st = Settings::load();
            let cfg = ServerConfig { root, receive_dir: st.receive_dir(), trash_dir: store::onemsiz_dir() };
            let srv = Server::start(
                cfg,
                port,
                Arc::new(|e| match e {
                    Event::Receiving(n) => println!("{} {n}", l("Alınıyor:", "Receiving:")),
                    Event::Received { name, folder } => println!("{} {name} → {}", l("Alındı:", "Received:"), folder.display()),
                    Event::NotesChanged => println!("{}", l("Notlar eşitlemeyle değişti", "Notes changed by sync")),
                    Event::Failed(m) => eprintln!("{m}"),
                }),
            )
            .unwrap_or_else(|e| fail(&format!("{}: {e}", l("Paylaşım açılamadı", "Couldn't start sharing"))));
            println!(
                "{} :{} ({} {})",
                l("Dinleniyor", "Listening on"),
                srv.port,
                l("mDNS servis adı", "mDNS service name"),
                quickshare::service_name(&st.qs_id())
            );
            loop {
                std::thread::sleep(std::time::Duration::from_secs(3600));
            }
        }
        "send" => {
            let ps = peers(&mut args);
            let Some(p) = ps.first() else { usage() };
            let files: Vec<PathBuf> = args.iter().map(PathBuf::from).collect();
            if files.is_empty() {
                usage()
            }
            let ok = quickshare::send_files(&files, &p.addr);
            if ok == files.len() {
                println!("{} {ok}", l("Gönderildi:", "Sent:"));
            } else {
                fail(&format!("{} ({})", l("Gönderilemedi", "Send failed"), files.len() - ok));
            }
        }
        "sync" => {
            let mode: i32 = flag(&mut args, "--mode").and_then(|m| m.parse().ok()).unwrap_or(0);
            let ps = peers(&mut args);
            let root = root_or_die();
            let out = sync::run(mode, &ps, &root, &store::onemsiz_dir());
            println!("{}", out.message());
            if !out.ok() {
                std::process::exit(1);
            }
        }
        "config-dir" => println!("{}", config::config_dir().display()),
        _ => usage(),
    }
}
