//! Hızlı Paylaş — Android'deki ile aynı protokol:
//!  - mDNS: `_qshare._tcp`, servis adı "QS"+kimlik[0..10], TXT: n=cihaz adı, i=kimlik
//!    (mDNS keşfi çekirdekte yok; GUI katmanı `mdns-sd` ile yapar, burada yalnızca sabitler var)
//!  - Alma: düz TCP, `POST /u` + `X-Name` (URL kodlu ad) + `Content-Length`, yanıt `HTTP/1.1 200 OK`
//!  - Eşitleme uç noktaları: GET /m, GET /f, POST /d, DELETE /x, POST /u + X-Sync

use crate::net::{find_sep, Conn, Head, MAX_HEAD};
use crate::store::{self, unique_suffix};
use crate::sync;
use crate::text::{dec, enc, l};
use std::fs;
use std::io::{Read, Write};
use std::net::{Shutdown, TcpListener, TcpStream};
use std::path::{Path, PathBuf};
use std::process::Command;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;
use std::thread::JoinHandle;
use std::time::Duration;

pub const SERVICE_TYPE: &str = "_qshare._tcp";

/// mDNS servis adı: "QS" + kimliğin ilk 10 karakteri.
pub fn service_name(id: &str) -> String {
    format!("QS{}", id.chars().take(10).collect::<String>())
}

#[derive(Debug, Clone)]
pub enum Event {
    Receiving(String),
    Received {
        name: String,
        folder: PathBuf,
    },
    /// Eşitleme ~/Link içeriğini değiştirdi: açık pencere listeyi yenilemeli.
    NotesChanged,
    Failed(String),
}

#[derive(Clone)]
pub struct ServerConfig {
    pub root: PathBuf,
    pub receive_dir: PathBuf,
    /// Eşitlemeyle silinen öğelerin taşındığı klasör.
    pub trash_dir: PathBuf,
}

pub struct Server {
    pub port: u16,
    stop: Arc<AtomicBool>,
    handle: Option<JoinHandle<()>>,
}

impl Server {
    /// `port` 0 ise boş bir port seçilir (`Server::port` ile okunur; mDNS'e bu yayınlanır).
    pub fn start(cfg: ServerConfig, port: u16, on_event: Arc<dyn Fn(Event) + Send + Sync>) -> std::io::Result<Server> {
        let listener = TcpListener::bind(("0.0.0.0", port))?;
        let port = listener.local_addr()?.port();
        let stop = Arc::new(AtomicBool::new(false));
        let stop2 = stop.clone();
        let handle = std::thread::spawn(move || {
            for conn in listener.incoming() {
                if stop2.load(Ordering::SeqCst) {
                    break;
                }
                let Ok(s) = conn else { continue };
                let cfg = cfg.clone();
                let ev = on_event.clone();
                std::thread::spawn(move || handle_conn(s, &cfg, &*ev));
            }
        });
        Ok(Server { port, stop, handle: Some(handle) })
    }

    pub fn stop(&mut self) {
        self.stop.store(true, Ordering::SeqCst);
        // accept()'i uyandır
        let _ = TcpStream::connect(("127.0.0.1", self.port));
        if let Some(h) = self.handle.take() {
            let _ = h.join();
        }
    }
}

impl Drop for Server {
    fn drop(&mut self) {
        if self.handle.is_some() {
            self.stop();
        }
    }
}

// MARK: Sunucu (alma tarafı)

fn reply(s: &mut TcpStream, status: &str) {
    let r = format!("HTTP/1.1 {status}\r\nContent-Length: 0\r\nConnection: close\r\n\r\n");
    let _ = s.write_all(r.as_bytes());
    let _ = s.shutdown(Shutdown::Both);
}

fn respond(s: &mut TcpStream, status: &str, extra: &str, body: &[u8]) {
    let head = format!("HTTP/1.1 {status}\r\nContent-Length: {}\r\n{extra}Connection: close\r\n\r\n", body.len());
    let _ = s.write_all(head.as_bytes());
    let _ = s.write_all(body);
    let _ = s.shutdown(Shutdown::Both);
}

/// Android ile aynı temizleme: yol parçaları atılır, \u0000-\u001f : * ? " < > | → _, baştaki noktalar, en çok 120 karakter.
pub fn clean_name(s: &str) -> String {
    let n = s.rsplit('/').next().unwrap_or(s);
    let n = n.rsplit('\\').next().unwrap_or(n);
    let n: String = n.chars().map(|c| if (c as u32) < 32 || ":*?\"<>|".contains(c) { '_' } else { c }).collect();
    let n: String = n.trim_start_matches('.').chars().take(120).collect();
    if n.is_empty() {
        "file".into()
    } else {
        n
    }
}

/// Aynı adlı dosya varsa üzerine yazmak yerine "ad (2).uzantı" olarak kaydeder.
pub fn unique_path(dir: &Path, name: &str) -> PathBuf {
    let mut u = dir.join(name);
    let (base, ext) = match name.rsplit_once('.') {
        Some((b, e)) if !b.is_empty() => (b.to_string(), Some(e.to_string())),
        _ => (name.to_string(), None),
    };
    let mut i = 2;
    while u.exists() {
        u = dir.join(match &ext {
            Some(e) => format!("{base} ({i}).{e}"),
            None => format!("{base} ({i})"),
        });
        i += 1;
    }
    u
}

fn handle_conn(mut s: TcpStream, cfg: &ServerConfig, ev: &(dyn Fn(Event) + Send + Sync)) {
    let _ = s.set_read_timeout(Some(Duration::from_secs(30)));
    let _ = s.set_write_timeout(Some(Duration::from_secs(30)));
    // Başlık bloğunu oku
    let mut buf: Vec<u8> = vec![];
    let mut tmp = [0u8; 64 * 1024];
    let sep = loop {
        if let Some(i) = find_sep(&buf) {
            break i;
        }
        if buf.len() > MAX_HEAD {
            return reply(&mut s, "400 Bad Request");
        }
        match s.read(&mut tmp) {
            Ok(0) | Err(_) => return,
            Ok(n) => buf.extend_from_slice(&tmp[..n]),
        }
    };
    let head = Head::parse(&buf[..sep]);
    let rest = buf[sep + 4..].to_vec();
    let (method, target) = (head.method().to_string(), head.target().to_string());
    let len: i64 = head.get("content-length").and_then(|v| v.parse().ok()).unwrap_or(-1);
    let name = head.get("x-name").map(dec).unwrap_or_else(|| "file".into());
    let is_sync = head.get("x-sync") == Some("1");
    let mtime: i64 = head.get("x-mtime").and_then(|v| v.parse().ok()).unwrap_or(-1);
    let is_dir = head.get("x-dir") == Some("1");

    // Notlarım eşitleme uç noktaları (Android ile aynı)
    if (method == "GET" && (target == "/m" || target == "/f"))
        || (method == "DELETE" && target == "/x")
        || (method == "POST" && target == "/d")
    {
        return serve_sync(&mut s, cfg, ev, &target, &name, is_dir);
    }
    if method != "POST" || target != "/u" || len < 0 {
        return reply(&mut s, if target == "/u" { "400 Bad Request" } else { "500 Error" });
    }

    let (save_dir, part_name, sync_dest, mut disp_name);
    if is_sync {
        // Eşitleme: X-Name ~/Link içindeki göreli yoldur; zaman korunur, aynı yoldaki dosyanın üzerine yazılır
        let Some(dst) = sync::resolve(&name, &cfg.root, false) else { return reply(&mut s, "400 Bad Request") };
        save_dir = dst.parent().unwrap().to_path_buf();
        part_name = dst.file_name().unwrap().to_string_lossy().into_owned();
        disp_name = part_name.clone();
        sync_dest = Some(dst);
        let _ = fs::create_dir_all(&save_dir);
    } else {
        disp_name = clean_name(&name);
        part_name = disp_name.clone();
        save_dir = cfg.receive_dir.clone();
        sync_dest = None;
        let _ = fs::create_dir_all(&save_dir);
    }
    let part = save_dir.join(format!("{part_name}.{}.part", unique_suffix()));
    let Ok(mut file) = fs::File::create(&part) else { return reply(&mut s, "500 Error") };
    if sync_dest.is_none() {
        ev(Event::Receiving(disp_name.clone()));
    }

    // Gövdeyi al
    let mut left = len as u64;
    let mut werr = false;
    let mut write = |d: &[u8], left: &mut u64, file: &mut fs::File| {
        let n = (d.len() as u64).min(*left) as usize;
        if n > 0 && file.write_all(&d[..n]).is_err() {
            werr = true;
        }
        *left -= n as u64;
    };
    if left > 0 && !rest.is_empty() {
        write(&rest, &mut left, &mut file);
    }
    while left > 0 {
        match s.read(&mut tmp) {
            Ok(0) | Err(_) => {
                drop(file);
                let _ = fs::remove_file(&part);
                return;
            }
            Ok(n) => write(&tmp[..n], &mut left, &mut file),
        }
    }
    drop(file);

    // Tamamla
    let mut ok = !werr;
    let mut final_dir = cfg.receive_dir.clone();
    if ok {
        if let Some(d) = &sync_dest {
            if mtime > 0 {
                set_mtime(&part, mtime);
            }
            if d.exists() {
                ok = fs::remove_file(d).is_ok();
            }
            ok = ok && fs::rename(&part, d).is_ok();
        } else {
            let dest = unique_path(&save_dir, &disp_name);
            if fs::rename(&part, &dest).is_ok() {
                disp_name = dest.file_name().unwrap().to_string_lossy().into_owned();
                final_dir = dest.parent().unwrap().to_path_buf();
            } else {
                ok = false;
            }
        }
    }
    if !ok {
        let _ = fs::remove_file(&part);
        ev(Event::Failed(l(&format!("Alma yarım kaldı: {disp_name}"), &format!("Receive incomplete: {disp_name}"))));
    } else if sync_dest.is_none() {
        ev(Event::Received { name: disp_name, folder: final_dir });
    } else {
        ev(Event::NotesChanged);
    }
    reply(&mut s, if ok { "200 OK" } else { "500 Error" });
}

fn set_mtime(path: &Path, mt_ms: i64) {
    if let Ok(f) = fs::OpenOptions::new().write(true).open(path) {
        let _ = f.set_modified(std::time::UNIX_EPOCH + Duration::from_millis(mt_ms as u64));
    }
}

/// Eşitleme uç noktaları; hepsi `root` içinde çalışır.
fn serve_sync(s: &mut TcpStream, cfg: &ServerConfig, ev: &(dyn Fn(Event) + Send + Sync), target: &str, name: &str, is_dir: bool) {
    let root = &cfg.root;
    match target {
        "/m" => {
            let body = sync::manifest_body(&sync::local(root));
            respond(s, "200 OK", "", body.as_bytes());
        }
        "/f" => {
            let Some(f) = sync::resolve(name, root, false) else { return reply(s, "404 Not Found") };
            let Ok(data) = fs::read(&f) else { return reply(s, "404 Not Found") };
            let mt = sync::ms(fs::metadata(&f).ok().and_then(|m| m.modified().ok()));
            respond(s, "200 OK", &format!("X-Mtime: {mt}\r\n"), &data);
        }
        "/x" => {
            // Silinen öğe çöp klasörüne gider (geri alınabilir)
            let Some(f) = sync::resolve(name, root, is_dir) else { return reply(s, "500 Error") };
            let ok = !f.exists() || store::trash_to(&f, &cfg.trash_dir);
            if ok {
                ev(Event::NotesChanged);
            }
            reply(s, if ok { "200 OK" } else { "500 Error" });
        }
        _ => {
            let Some(d) = sync::resolve(name, root, true) else { return reply(s, "500 Error") };
            let ok = d.is_dir() || fs::create_dir_all(&d).is_ok();
            if ok {
                ev(Event::NotesChanged);
            }
            reply(s, if ok { "200 OK" } else { "500 Error" });
        }
    }
}

// MARK: İstemci (gönderme tarafı)

/// Klasörü geçici bir dizine "<ad>.zip" olarak sıkıştırır; (zip yolu, geçici dizin) döndürür.
fn zip_folder(dir: &Path) -> Option<(PathBuf, PathBuf)> {
    let tmp = std::env::temp_dir().join(format!("qs-{}", unique_suffix()));
    fs::create_dir_all(&tmp).ok()?;
    let name = dir.file_name()?.to_string_lossy().into_owned();
    let out = tmp.join(format!("{name}.zip"));
    let ok = if cfg!(target_os = "macos") {
        Command::new("/usr/bin/ditto")
            .args(["-c", "-k", "--sequesterRsrc", "--keepParent"])
            .arg(dir)
            .arg(&out)
            .status()
            .map(|s| s.success())
            .unwrap_or(false)
    } else {
        let parent = dir.parent().unwrap_or_else(|| Path::new("."));
        Command::new("zip").current_dir(parent).args(["-r", "-q"]).arg(&out).arg(&name).status().map(|s| s.success()).unwrap_or(false)
    };
    if ok {
        Some((out, tmp))
    } else {
        let _ = fs::remove_dir_all(&tmp);
        None
    }
}

/// Tek dosyayı gönderir: POST /u + X-Name + Content-Length. 200 dönerse true.
pub fn send_one(file: &Path, addr: &str) -> bool {
    let Ok(meta) = fs::metadata(file) else { return false };
    let Ok(mut fh) = fs::File::open(file) else { return false };
    let Ok(mut c) = Conn::connect(addr) else { return false };
    let name = file.file_name().map(|n| n.to_string_lossy().into_owned()).unwrap_or_else(|| "file".into());
    let head = format!(
        "POST /u HTTP/1.1\r\nHost: qs\r\nX-Name: {}\r\nContent-Type: application/octet-stream\r\nContent-Length: {}\r\nConnection: close\r\n\r\n",
        enc(&name),
        meta.len()
    );
    if c.send(head.as_bytes()).is_err() {
        return false;
    }
    let mut buf = vec![0u8; 1 << 20];
    loop {
        match fh.read(&mut buf) {
            Ok(0) => break,
            Ok(n) => {
                if c.send(&buf[..n]).is_err() {
                    return false;
                }
            }
            Err(_) => return false,
        }
    }
    matches!(c.read_head(), Ok(h) if h.status() == 200)
}

/// Dosyaları (klasörler zip'lenerek) bir cihaza gönderir; başarıyla giden sayısını döndürür.
pub fn send_files(files: &[PathBuf], addr: &str) -> usize {
    let mut ok = 0;
    for f in files {
        if f.is_dir() {
            let Some((z, tmp)) = zip_folder(f) else { continue };
            if send_one(&z, addr) {
                ok += 1;
            }
            let _ = fs::remove_dir_all(tmp);
        } else if send_one(f, addr) {
            ok += 1;
        }
    }
    ok
}
