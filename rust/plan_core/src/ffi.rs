//! C ABI. Tüm dönüş tamponları `plan_free` ile serbest bırakılmalıdır. Hata/panik → null.
//! Sayılar little-endian; ayrıntı için `include/plan_core.h`.

use crate::{fold, tree};
use std::os::raw::c_void;
use std::panic::{catch_unwind, AssertUnwindSafe};

pub(crate) unsafe fn bytes<'a>(p: *const u8, n: usize) -> &'a [u8] {
    if p.is_null() || n == 0 { &[] } else { std::slice::from_raw_parts(p, n) }
}

pub(crate) fn leak(v: Vec<u8>, out_len: *mut usize) -> *mut u8 {
    let b = v.into_boxed_slice();
    let n = b.len();
    if !out_len.is_null() {
        unsafe { *out_len = n };
    }
    Box::into_raw(b) as *mut u8
}

/// Panik FFI sınırını geçmesin.
pub(crate) fn guard(f: impl FnOnce() -> *mut u8) -> *mut u8 {
    catch_unwind(AssertUnwindSafe(f)).unwrap_or(std::ptr::null_mut())
}

#[cfg(test)]
struct Reader<'a>(&'a [u8], usize);
#[cfg(test)]
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

pub(crate) fn put_u32(v: &mut Vec<u8>, x: u32) {
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

pub(crate) fn put_str(v: &mut Vec<u8>, s: &str) {
    put_u32(v, s.len() as u32);
    v.extend_from_slice(s.as_bytes());
}

fn put_entry(v: &mut Vec<u8>, e: &tree::TreeEntry) {
    put_str(v, &e.name);
    put_str(v, &e.path);
    v.push(e.is_dir as u8);
    v.push(e.pinned as u8);
}

/// Klasör ağacını dolaşır (sıralama/sabitleme kurallarıyla) ve paralel arar.
/// Çıktı: [sayı u32] + her isabet için
///   [bayrak u8: 1=not, 2=başlıkta][detay: str][öğe][üst klasör sayısı u32][üst klasörler: öğe…]
/// str = u32 uzunluk + bayt; öğe = [ad: str][yol: str][klasör u8][sabit u8].
/// `alive` null değilse sık sık çağrılır; false dönerse arama bırakılır.
#[no_mangle]
pub unsafe extern "C" fn plan_search_tree(
    root: *const u8,
    root_len: usize,
    query: *const u8,
    query_len: usize,
    alive: Option<unsafe extern "C" fn(*mut c_void) -> bool>,
    ctx: *mut c_void,
    out_len: *mut usize,
) -> *mut u8 {
    let root = String::from_utf8_lossy(bytes(root, root_len)).into_owned();
    let query = String::from_utf8_lossy(bytes(query, query_len)).into_owned();
    let ctx = ctx as usize;
    guard(|| {
        let alive_fn = move || match alive {
            Some(f) => unsafe { f(ctx as *mut c_void) },
            None => true,
        };
        let hits = tree::search_tree(std::path::Path::new(&root), &query, &alive_fn);
        let mut out = Vec::new();
        put_u32(&mut out, hits.len() as u32);
        for h in hits {
            out.push(h.hit.is_note as u8 | (h.hit.title_match as u8) << 1);
            put_str(&mut out, &h.hit.detail);
            put_entry(&mut out, &h.entry);
            put_u32(&mut out, h.ancestors.len() as u32);
            for a in &h.ancestors {
                put_entry(&mut out, a);
            }
        }
        leak(out, out_len)
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn roundtrip_search_tree_through_ffi() {
        let d = std::env::temp_dir().join(format!("plan_core_ffi_{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&d);
        std::fs::create_dir_all(d.join("Alt")).unwrap();
        std::fs::write(d.join("Alt/n.txt"), "Merhaba Dünya").unwrap();
        let root = d.to_string_lossy().into_owned();
        unsafe extern "C" fn yes(_: *mut c_void) -> bool { true }
        let mut n = 0usize;
        let q = "dunya";
        let ptr = unsafe {
            plan_search_tree(root.as_ptr(), root.len(), q.as_ptr(), q.len(), Some(yes), std::ptr::null_mut(), &mut n)
        };
        assert!(!ptr.is_null());
        let out = unsafe { std::slice::from_raw_parts(ptr, n) }.to_vec();
        unsafe { plan_free(ptr, n) };
        let mut r = Reader(&out, 0);
        assert_eq!(r.u32(), Some(1));
        assert_eq!(r.u8(), Some(1)); // not, başlıkta değil
        assert_eq!(r.str().as_deref(), Some("Merhaba Dünya"));
        assert_eq!(r.str().as_deref(), Some("n.txt"));
        let _ = std::fs::remove_dir_all(d);
    }

    #[test]
    fn empty_query_gives_zero_hits() {
        let mut n = 0usize;
        let root = "/tmp";
        let ptr = unsafe { plan_search_tree(root.as_ptr(), 4, b" ".as_ptr(), 1, None, std::ptr::null_mut(), &mut n) };
        assert!(!ptr.is_null());
        let out = unsafe { std::slice::from_raw_parts(ptr, n) }.to_vec();
        unsafe { plan_free(ptr, n) };
        assert_eq!(out, vec![0, 0, 0, 0]);
    }
}
