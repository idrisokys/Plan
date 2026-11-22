//! Büyük/küçük harf, Türkçe i/ı/İ/I ve Latin aksan farkını yok sayan sadeleştirme.
//!
//! Swift'teki `NotesStore.fold` ile aynı sonucu verir (NFD + birleşik işaretleri at + küçült).
//! Tam Unicode kanonik ayrışımı kullanılır (`unicode.rs`).

use crate::unicode::{is_nonspacing_mark, nfd};

#[inline]
fn push_lower(c: char, f: &mut impl FnMut(char)) {
    for l in c.to_lowercase() {
        f(l);
    }
}

/// Tek karakteri sadeleştirip `f`'e verir: Türkçe harfler, sonra NFD + birleşik işaretleri at + küçült.
fn fold_char(c: char, f: &mut impl FnMut(char)) {
    match c {
        'İ' | 'ı' | 'I' => f('i'),
        'ş' | 'Ş' => f('s'),
        'ğ' | 'Ğ' => f('g'),
        'ü' | 'Ü' => f('u'),
        'ö' | 'Ö' => f('o'),
        'ç' | 'Ç' => f('c'),
        _ if c.is_ascii() => f(c.to_ascii_lowercase()),
        _ => {
            let mut buf = [0u8; 4];
            for d in nfd(c.encode_utf8(&mut buf)).chars() {
                if !is_nonspacing_mark(d) {
                    push_lower(d, f);
                }
            }
        }
    }
}

pub fn fold(s: &str) -> String {
    let mut out = String::with_capacity(s.len());
    for c in s.chars() {
        fold_char(c, &mut |x| out.push(x));
    }
    out
}

/// Sadeleştirilmiş metin + her sadeleştirilmiş karakterin özgün metindeki karakter (scalar) sırası.
pub fn fold_mapped(s: &str) -> (String, Vec<u32>) {
    let mut out = String::with_capacity(s.len());
    let mut map = Vec::with_capacity(s.len());
    for (i, c) in s.chars().enumerate() {
        fold_char(c, &mut |x| {
            out.push(x);
            map.push(i as u32);
        });
    }
    (out, map)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn turkish_and_accents() {
        assert_eq!(fold("İstanbul"), "istanbul");
        assert_eq!(fold("ŞĞÜÖÇı"), "sguoci");
        assert_eq!(fold("Café"), "cafe");
        assert_eq!(fold("Çalışma Notları"), "calisma notlari");
        assert_eq!(fold("ÀÉÎõÜ ñ Ł Œ ệ й"), "aeiou n ł œ e и");
    }

    #[test]
    fn combining_marks_are_dropped() {
        assert_eq!(fold("e\u{0301}"), "e");
        assert_eq!(fold("Cafe\u{0301}"), "cafe");
    }

    #[test]
    fn mapped_indices_follow_original() {
        let (f, m) = fold_mapped("Ae\u{0301}Z");
        assert_eq!(f, "aez");
        assert_eq!(m, vec![0, 1, 3]);
    }
}
