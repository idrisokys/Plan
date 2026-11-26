//! C ABI: Hızlı Paylaş (alma sunucusu, gönderme) ve Notlarım eşitlemesi. Ayrıntı: `include/plan_core.h`.
//! Sayılar little-endian; hata/panikte null (ya da -1) döner.

use crate::ffi::{bytes, guard, leak, put_str, put_u32};
use crate::share::server::{Config, Event, Server, Sink};
use crate::share::{client, proto, sync};
use std::os::raw::c_void;
use std::panic::{catch_unwind, AssertUnwindSafe};
use std::path::{Path, PathBuf};
use std::sync::Arc;

type EventCb = Option<unsafe extern "C" fn(*mut c_void, u8, *const u8, usize, *const u8, usize)>;
type ProgressCb = Option<unsafe extern "C" fn(*mut c_void, u32, u64, u64)>;

fn string(p: *const u8, n: usize) -> String {
    String::from_utf8_lossy(unsafe { bytes(p, n) }).into_owned()
}

/// [u32 uzunluk + bayt]… listesini ayrıştırır.
fn str_list(data: &[u8]) -> Option<Vec<String>> {
    let mut i = 0;
    let mut out = Vec::new();
    while i < data.len() {
        let n = u32::from_le_bytes(data.get(i..i + 4)?.try_into().ok()?) as usize;
        i += 4;
        out.push(String::from_utf8_lossy(data.get(i..i + n)?).into_owned());
        i += n;
    }
    Some(out)
}

/// Arayüz dili: `true` = İngilizce, `false` = Türkçe (Rust'tan dönen hata/özet metinleri için).
#[no_mangle]
pub extern "C" fn plan_qs_set_lang(english: bool) {
    proto::set_english(english);
}

/// Alma sunucusunu başlatır; tutamaç döner (hata: null). `port` 0 ise boş port seçilir ve `out_port`'a yazılır.
/// `link_root_len` 0 ise Notlarım eşitleme uç noktaları kapalıdır.
/// Olay geri çağrısı farklı iş parçacıklarından çağrılır: kind 1=alınıyor(ad), 2=alındı(ad, klasör),
/// 3=alma yarım kaldı(ad), 4=Link içeriği eşitlemeyle değişti.
#[no_mangle]
pub unsafe extern "C" fn plan_qs_server_start(
    recv_dir: *const u8,
    recv_len: usize,
    link_root: *const u8,
    link_len: usize,
    port: u16,
    cb: EventCb,
    ctx: *mut c_void,
    out_port: *mut u16,
) -> *mut c_void {
    let recv = PathBuf::from(string(recv_dir, recv_len));
    let link = if link_len == 0 { None } else { Some(PathBuf::from(string(link_root, link_len))) };
    let ctx = ctx as usize;
    catch_unwind(AssertUnwindSafe(|| {
        let sink: Sink = Arc::new(move |e: Event| {
            let Some(f) = cb else { return };
            let c = ctx as *mut c_void;
            let none = std::ptr::null();
            unsafe {
                match &e {
                    Event::Receiving(n) => f(c, 1, n.as_ptr(), n.len(), none, 0),
                    Event::Received { name, folder } => {
                        let p = folder.to_string_lossy();
                        f(c, 2, name.as_ptr(), name.len(), p.as_ptr(), p.len())
                    }
                    Event::Failed(n) => f(c, 3, n.as_ptr(), n.len(), none, 0),
                    Event::NotesChanged => f(c, 4, none, 0, none, 0),
                    // Android'e özgü (Wi-Fi/CPU kilidi); macOS'ta karşılığı yok
                    Event::Busy(_) => {}
                }
            }
        });
        match Server::start(Config { recv_dir: recv, link_root: link, ..Default::default() }, port, sink) {
            Ok(s) => {
                if !out_port.is_null() {
                    *out_port = s.port();
                }
                Box::into_raw(Box::new(s)) as *mut c_void
            }
            Err(_) => std::ptr::null_mut(),
        }
    }))
    .unwrap_or(std::ptr::null_mut())
}

/// Sunucuyu durdurur ve tutamacı serbest bırakır (dinleyici kapanır; süren aktarımlar biter).
#[no_mangle]
pub unsafe extern "C" fn plan_qs_server_stop(handle: *mut c_void) {
    if !handle.is_null() {
        let _ = catch_unwind(AssertUnwindSafe(|| drop(Box::from_raw(handle as *mut Server))));
    }
}

/// Dosyaları `addr` (`ip:port`) adresine gönderir; klasörler zip'lenir. Girdi: [yol: u32 uzunluk + bayt]…
/// Dosyalar paralel (en çok 4 bağlantı) gider. Dönüş: başarıyla giden dosya sayısı (panik: -1).
/// `progress(ctx, dosya_sırası, gönderilen, toplam)` boş olabilir; farklı iş parçacıklarından çağrılır.
/// Engelleyicidir: arka plan iş parçacığından çağrılmalıdır.
#[no_mangle]
pub unsafe extern "C" fn plan_qs_send(
    addr: *const u8,
    addr_len: usize,
    paths: *const u8,
    paths_len: usize,
    progress: ProgressCb,
    ctx: *mut c_void,
) -> i32 {
    let addr = string(addr, addr_len);
    let Some(list) = str_list(bytes(paths, paths_len)) else { return -1 };
    let files: Vec<PathBuf> = list.into_iter().map(PathBuf::from).collect();
    let ctx = ctx as usize;
    catch_unwind(AssertUnwindSafe(|| {
        let p = |i: usize, s: u64, t: u64| {
            if let Some(f) = progress {
                unsafe { f(ctx as *mut c_void, i as u32, s, t) }
            }
        };
        let pr: Option<&(dyn Fn(usize, u64, u64) + Sync)> = if progress.is_some() { Some(&p) } else { None };
        client::send_files(&addr, &files, pr) as i32
    }))
    .unwrap_or(-1)
}

/// Dosyaları `addr` adresindeki cihazın Link klasörüne gönderir (`X-Sync: 1`). `link_root` içindeki dosyalar göreli
/// yollarıyla gider; `link_len` 0 ise yalnızca adlarıyla Link köküne. Klasörler atlanır. Dönüş: giden dosya sayısı (panik: -1).
#[no_mangle]
pub unsafe extern "C" fn plan_qs_send_link(
    addr: *const u8,
    addr_len: usize,
    paths: *const u8,
    paths_len: usize,
    link_root: *const u8,
    link_len: usize,
    progress: ProgressCb,
    ctx: *mut c_void,
) -> i32 {
    let addr = string(addr, addr_len);
    let Some(list) = str_list(bytes(paths, paths_len)) else { return -1 };
    let files: Vec<PathBuf> = list.into_iter().map(PathBuf::from).collect();
    let root = if link_len == 0 { None } else { Some(PathBuf::from(string(link_root, link_len))) };
    let ctx = ctx as usize;
    catch_unwind(AssertUnwindSafe(|| {
        let p = |i: usize, s: u64, t: u64| {
            if let Some(f) = progress {
                unsafe { f(ctx as *mut c_void, i as u32, s, t) }
            }
        };
        let pr: Option<&(dyn Fn(usize, u64, u64) + Sync)> = if progress.is_some() { Some(&p) } else { None };
        client::send_files_link(&addr, &files, root.as_deref(), pr) as i32
    }))
    .unwrap_or(-1)
}

/// Link eşitlemesi. mode: 0 iki cihazda aynı, 1 bu cihaza göre, 2 karşıdakine göre.
/// peers: [ad: str][adres `ip:port`: str]… Engelleyicidir.
/// Çıktı: [başarılı u8: 1=hatasız][gönderilen u32][alınan u32][silinen u32][cihaz u32][özet: str]
///        [hata sayısı u32][hata: str…]
#[no_mangle]
pub unsafe extern "C" fn plan_qs_sync(
    mode: u32,
    link_root: *const u8,
    link_len: usize,
    peers: *const u8,
    peers_len: usize,
    out_len: *mut usize,
) -> *mut u8 {
    let root = if link_len == 0 { None } else { Some(PathBuf::from(string(link_root, link_len))) };
    let Some(list) = str_list(bytes(peers, peers_len)) else { return std::ptr::null_mut() };
    let targets: Vec<sync::Peer> = list.chunks(2).filter(|c| c.len() == 2).map(|c| sync::Peer { name: c[0].clone(), addr: c[1].clone() }).collect();
    // macOS: yalnızca Link kapsamı (kalıcı silme, gizli klasörler atlanır)
    let scope = root.map(sync::Scope::link);
    guard(|| {
        let r = sync::run(mode, scope.as_ref(), &targets);
        let mut out = vec![(r.error.is_none() && r.errors.is_empty()) as u8];
        for v in [r.sent, r.got, r.deleted, r.peers] {
            put_u32(&mut out, v);
        }
        put_str(&mut out, &r.message());
        put_u32(&mut out, r.errors.len() as u32);
        for e in &r.errors {
            put_str(&mut out, e);
        }
        leak(out, out_len)
    })
}

/// Karşı taraftan gelen göreli yolu `root` içinde güvenli bir yola çevirir (`..`, kontrol karakteri, Link dışı → null).
/// `dir` false ise son bölüm .url/.txt olmalıdır.
#[no_mangle]
pub unsafe extern "C" fn plan_qs_resolve(
    rel: *const u8,
    rel_len: usize,
    root: *const u8,
    root_len: usize,
    dir: bool,
    out_len: *mut usize,
) -> *mut u8 {
    let rel = string(rel, rel_len);
    let root = string(root, root_len);
    guard(|| match proto::resolve(&rel, Path::new(&root), dir) {
        Some(p) => leak(p.to_string_lossy().into_owned().into_bytes(), out_len),
        None => std::ptr::null_mut(),
    })
}
