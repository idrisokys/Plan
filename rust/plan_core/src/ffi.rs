//! C ABI. Tüm dönüş tamponları `plan_free` ile serbest bırakılmalıdır. Hata/panik → null.
//! Sayılar little-endian; ayrıntı için `include/plan_core.h`.

use crate::{fold, hash, image, scan, search};
use std::os::raw::c_void;
use std::panic::{catch_unwind, AssertUnwindSafe};

unsafe fn bytes<'a>(p: *const u8, n: usize) -> &'a [u8] {
    if p.is_null() || n == 0 { &[] } else { std::slice::from_raw_parts(p, n) }
}

fn leak(v: Vec<u8>, out_len: *mut usize) -> *mut u8 {
    let b = v.into_boxed_slice();
    let n = b.len();
    if !out_len.is_null() {
        unsafe { *out_len = n };
    }
    Box::into_raw(b) as *mut u8
}

/// Panik FFI sınırını geçmesin.
fn guard(f: impl FnOnce() -> *mut u8) -> *mut u8 {
    catch_unwind(AssertUnwindSafe(f)).unwrap_or(std::ptr::null_mut())
}

struct Reader<'a>(&'a [u8], usize);
impl<'a> Reader<'a> {
    fn u8(&mut self) -> Option<u8> {
        let v = *self.0.get(self.1)?;
        self.1 += 1;
        Some(v)
    }
    fn u32(&mut self) -> Option<u32> {
        let b = self.0.get(self.1..self.1 + 4)?;
        self.1 += 4;
        Some(u32::from_le_bytes([b[0], b[1], b[2], b[3]]))
    }
    fn str(&mut self) -> Option<String> {
        let n = self.u32()? as usize;
        let b = self.0.get(self.1..self.1 + n)?;
        self.1 += n;
        Some(String::from_utf8_lossy(b).into_owned())
    }
}

fn put_u32(v: &mut Vec<u8>, x: u32) {
    v.extend_from_slice(&x.to_le_bytes());
}

#[no_mangle]
pub unsafe extern "C" fn plan_free(ptr: *mut u8, len: usize) {
    if !ptr.is_null() {
        drop(Box::from_raw(std::ptr::slice_from_raw_parts_mut(ptr, len)));
    }
}

/// UTF-8 metni sadeleştirir (`fold::fold`).
#[no_mangle]
pub unsafe extern "C" fn plan_fold(s: *const u8, len: usize, out_len: *mut usize) -> *mut u8 {
    let s = bytes(s, len);
    guard(|| leak(fold::fold(&String::from_utf8_lossy(s)).into_bytes(), out_len))
}

/// Girdi: [kind u8][path: u32 uzunluk + bayt][title: u32 uzunluk + bayt]…  (kind 0=.url 1=.txt 2=klasör)
/// Çıktı: [sayı u32] + her isabet için [indeks u32][bayrak u8: 1=not, 2=başlıkta][detay: u32 uzunluk + bayt]
/// `alive` null değilse sık sık çağrılır; false dönerse arama bırakılır.
#[no_mangle]
pub unsafe extern "C" fn plan_search(
    items: *const u8,
    items_len: usize,
    query: *const u8,
    query_len: usize,
    alive: Option<unsafe extern "C" fn(*mut c_void) -> bool>,
    ctx: *mut c_void,
    out_len: *mut usize,
) -> *mut u8 {
    let (items, query) = (bytes(items, items_len), bytes(query, query_len));
    let ctx = ctx as usize;
    guard(|| {
        let mut r = Reader(items, 0);
        let mut list = Vec::new();
        while r.1 < items.len() {
            let (Some(kind), Some(path), Some(title)) = (r.u8(), r.str(), r.str()) else {
                return std::ptr::null_mut();
            };
            list.push(search::Item { kind, path, title });
        }
        let alive_fn = move || match alive {
            Some(f) => unsafe { f(ctx as *mut c_void) },
            None => true,
        };
        let hits = search::search(&list, &String::from_utf8_lossy(query), &alive_fn);
        let mut out = Vec::new();
        put_u32(&mut out, hits.len() as u32);
        for h in hits {
            put_u32(&mut out, h.index as u32);
            out.push(h.is_note as u8 | (h.title_match as u8) << 1);
            put_u32(&mut out, h.detail.len() as u32);
            out.extend_from_slice(h.detail.as_bytes());
        }
        leak(out, out_len)
    })
}

/// Girdi: [yol: u32 uzunluk + bayt]…  Çıktı: her yol için 49 bayt:
/// [durum u8: 1=tamam][boyut u64][mtime i64][sha256 32 bayt]
#[no_mangle]
pub unsafe extern "C" fn plan_analyze_files(paths: *const u8, len: usize, out_len: *mut usize) -> *mut u8 {
    let data = bytes(paths, len);
    guard(|| {
        let mut r = Reader(data, 0);
        let mut list = Vec::new();
        while r.1 < data.len() {
            match r.str() {
                Some(p) => list.push(p),
                None => return std::ptr::null_mut(),
            }
        }
        let mut out = Vec::with_capacity(list.len() * 49);
        for i in hash::analyze_many(&list) {
            out.push(i.ok as u8);
            out.extend_from_slice(&i.size.to_le_bytes());
            out.extend_from_slice(&i.mtime.to_le_bytes());
            out.extend_from_slice(&i.digest);
        }
        leak(out, out_len)
    })
}

/// Çıktı: her giriş için [tür u8: 0=dosya 1=klasör 2=diğer][boyut u64][mtime i64][yol: u32 uzunluk + bayt]
#[no_mangle]
pub unsafe extern "C" fn plan_scan(root: *const u8, root_len: usize, include_hidden: bool, out_len: *mut usize) -> *mut u8 {
    let root = String::from_utf8_lossy(bytes(root, root_len)).into_owned();
    guard(|| {
        let mut out = Vec::new();
        for e in scan::scan(&root, include_hidden) {
            out.push(e.kind);
            out.extend_from_slice(&e.size.to_le_bytes());
            out.extend_from_slice(&e.mtime.to_le_bytes());
            put_u32(&mut out, e.path.len() as u32);
            out.extend_from_slice(e.path.as_bytes());
        }
        leak(out, out_len)
    })
}

/// Premultiplied RGBA8 → en uzun kenarı `max_side` olan küçük resim (aynı biçim).
#[no_mangle]
pub unsafe extern "C" fn plan_thumbnail(
    rgba: *const u8,
    width: u32,
    height: u32,
    max_side: u32,
    out_w: *mut u32,
    out_h: *mut u32,
    out_len: *mut usize,
) -> *mut u8 {
    let n = (width as usize).saturating_mul(height as usize).saturating_mul(4);
    let src = bytes(rgba, n);
    guard(|| match image::thumbnail(src, width, height, max_side) {
        Some((w, h, v)) => {
            if !out_w.is_null() {
                *out_w = w;
            }
            if !out_h.is_null() {
                *out_h = h;
            }
            leak(v, out_len)
        }
        None => std::ptr::null_mut(),
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn roundtrip_search_through_ffi() {
        let p = std::env::temp_dir().join(format!("plan_core_ffi_{}.txt", std::process::id()));
        std::fs::write(&p, "Merhaba Dünya").unwrap();
        let path = p.to_string_lossy().into_owned();
        let mut items = vec![1u8];
        for s in [path.as_str(), "t"] {
            put_u32(&mut items, s.len() as u32);
            items.extend_from_slice(s.as_bytes());
        }
        unsafe extern "C" fn yes(_: *mut c_void) -> bool { true }
        let mut n = 0usize;
        let q = "dunya";
        let ptr = unsafe {
            plan_search(items.as_ptr(), items.len(), q.as_ptr(), q.len(), Some(yes), std::ptr::null_mut(), &mut n)
        };
        assert!(!ptr.is_null());
        let out = unsafe { std::slice::from_raw_parts(ptr, n) }.to_vec();
        unsafe { plan_free(ptr, n) };
        assert_eq!(u32::from_le_bytes(out[0..4].try_into().unwrap()), 1);
        assert_eq!(out[8], 1); // not, başlıkta değil
        assert_eq!(&out[13..], "Merhaba Dünya".as_bytes());
        let _ = std::fs::remove_file(p);
    }

    #[test]
    fn malformed_input_returns_null() {
        let mut n = 0usize;
        let bad = [1u8, 255, 255, 255, 255];
        let q = "a";
        let ptr = unsafe { plan_search(bad.as_ptr(), bad.len(), q.as_ptr(), 1, None, std::ptr::null_mut(), &mut n) };
        assert!(ptr.is_null());
    }
}
