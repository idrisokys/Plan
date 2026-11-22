//! Büyük/küçük harf, Türkçe i/ı/İ/I ve Latin aksan farkını yok sayan sadeleştirme.
//!
//! Swift'teki `NotesStore.fold` ile aynı sonucu verir (NFD + birleşik işaretleri at + küçült).
//! Tam Unicode NFD tablosu yerine Latin-1 / Latin Genişletilmiş-A tablosu ve U+0300–036F birleşik
//! işaretleri kullanılır; Türkçe ve Avrupa dilleri için yeterlidir.

const LATIN1: &str = "AAAAAA?CEEEEIIII?NOOOOO??UUUUY??aaaaaa?ceeeeiiii?nooooo??uuuuy?y";
const EXT_A: [&str; 8] = [
    "AaAaAaCcCcCcCcDd",
    "??EeEeEeEeEeGgGg",
    "GgGgHh??IiIiIiIi",
    "Ii??JjKk?LlLlLl?",
    "???NnNnNn???OoOo",
    "Oo??RrRrRrSsSsSs",
    "SsTtTt??UuUuUuUu",
    "UuUuWwYyYZzZzZz?",
];

/// Aksansız taban harfi (varsa).
fn base_letter(c: char) -> Option<char> {
    let cp = c as u32;
    let b = match cp {
        0xC0..=0xFF => LATIN1.as_bytes()[(cp - 0xC0) as usize] as char,
        0x100..=0x17F => {
            let o = (cp - 0x100) as usize;
            EXT_A[o / 16].as_bytes()[o % 16] as char
        }
        0x419 => return Some('и'), // Й
        0x439 => return Some('и'), // й
        0x401 | 0x451 => return Some('е'), // Ё ё
        _ => return None,
    };
    if b == '?' { None } else { Some(b) }
}

#[inline]
fn is_combining(c: char) -> bool {
    matches!(c as u32, 0x0300..=0x036F)
}

#[inline]
fn push_lower(c: char, mut f: impl FnMut(char)) {
    for l in c.to_lowercase() {
        f(l);
    }
}

/// Tek karakteri sadeleştirip `f`'e verir.
fn fold_char(c: char, f: &mut impl FnMut(char)) {
    match c {
        'İ' | 'ı' | 'I' => f('i'),
        'ş' | 'Ş' => f('s'),
        'ğ' | 'Ğ' => f('g'),
        'ü' | 'Ü' => f('u'),
        'ö' | 'Ö' => f('o'),
        'ç' | 'Ç' => f('c'),
        _ if is_combining(c) => {}
        _ => match base_letter(c) {
            Some(b) => push_lower(b, f),
            None => push_lower(c, f),
        },
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
        assert_eq!(fold("ÀÉÎõÜ ñ Ł Œ"), "aeiou n ł œ");
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
