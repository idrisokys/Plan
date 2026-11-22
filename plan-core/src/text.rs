//! Metin yardımcıları: ad temizleme, Türkçe/aksan duyarsız karşılaştırma, yüzde kodlama.
//!
//! Yalnızca standart kütüphane kullanıldığı için tam Unicode NFC/NFD yoktur; Latin-1 ve
//! Latin Genişletilmiş-A'daki (Türkçe dahil) yaygın harfler için küçük bir birleştirme tablosu vardır.
//! macOS dosya adları NFD olabilir (ör. "ş" = "s" + U+0327); bu tablo onları NFC'ye çevirir.

use std::collections::HashMap;
use std::sync::OnceLock;

/// (birleştirici işaret, temel harfler, bileşik harfler) — iki dizgenin karakter sayısı eşittir.
const TABLE: &[(u32, &str, &str)] = &[
    (0x0300, "aeiouAEIOU", "àèìòùÀÈÌÒÙ"),
    (0x0301, "aeiouyAEIOUYcnszlrCNSZLR", "áéíóúýÁÉÍÓÚÝćńśźĺŕĆŃŚŹĹŔ"),
    (0x0302, "aeiouAEIOUcghjswyCGHJSWY", "âêîôûÂÊÎÔÛĉĝĥĵŝŵŷĈĜĤĴŜŴŶ"),
    (0x0303, "anoiuANOIU", "ãñõĩũÃÑÕĨŨ"),
    (0x0304, "aeiouAEIOU", "āēīōūĀĒĪŌŪ"),
    (0x0306, "aegiouAEGIOU", "ăĕğĭŏŭĂĔĞĬŎŬ"),
    (0x0307, "cegzICEGZ", "ċėġżİĊĖĠŻ"),
    (0x0308, "aeiouyAEIOUY", "äëïöüÿÄËÏÖÜŸ"),
    (0x030A, "auAU", "åůÅŮ"),
    (0x030B, "ouOU", "őűŐŰ"),
    (0x030C, "cdenrstzCDENRSTZ", "čďěňřšťžČĎĚŇŘŠŤŽ"),
    (0x0327, "cgklnrstCGKLNRST", "çģķļņŗşţÇĢĶĻŅŖŞŢ"),
    (0x0328, "aeiuAEIU", "ąęįųĄĘĮŲ"),
];

fn compose_map() -> &'static HashMap<(char, u32), char> {
    static M: OnceLock<HashMap<(char, u32), char>> = OnceLock::new();
    M.get_or_init(|| {
        let mut m = HashMap::new();
        for (mark, bases, composed) in TABLE {
            for (b, c) in bases.chars().zip(composed.chars()) {
                m.insert((b, *mark), c);
            }
        }
        m
    })
}

fn strip_map() -> &'static HashMap<char, char> {
    static M: OnceLock<HashMap<char, char>> = OnceLock::new();
    M.get_or_init(|| {
        let mut m = HashMap::new();
        for (_, bases, composed) in TABLE {
            for (b, c) in bases.chars().zip(composed.chars()) {
                m.insert(c, b);
            }
        }
        m
    })
}

fn is_combining(c: char) -> bool {
    ('\u{0300}'..='\u{036F}').contains(&c)
}

/// Temel NFC: "s" + U+0327 → "ş" gibi.
pub fn nfc(s: &str) -> String {
    let m = compose_map();
    let mut out = String::with_capacity(s.len());
    for c in s.chars() {
        if is_combining(c) {
            if let Some(prev) = out.chars().last() {
                if let Some(&comp) = m.get(&(prev, c as u32)) {
                    out.pop();
                    out.push(comp);
                    continue;
                }
            }
        }
        out.push(c);
    }
    out
}

/// Ad karşılaştırma anahtarı: NFC + küçük harf (büyük/küçük harfe duyarsız disklerde çakışmayı yakalar).
pub fn norm(s: &str) -> String {
    nfc(s).to_lowercase()
}

/// Büyük/küçük harf, Türkçe i/ı/İ/I ve aksan (ş→s, ğ→g, é→e…) farkını yok sayar.
pub fn fold(s: &str) -> String {
    let strip = strip_map();
    let mut out = String::with_capacity(s.len());
    for c in s.chars() {
        match c {
            'İ' | 'ı' => out.push('i'),
            'ş' | 'Ş' => out.push('s'),
            'ğ' | 'Ğ' => out.push('g'),
            'ü' | 'Ü' => out.push('u'),
            'ö' | 'Ö' => out.push('o'),
            'ç' | 'Ç' => out.push('c'),
            _ if is_combining(c) => {}
            _ => {
                let base = strip.get(&c).copied().unwrap_or(c);
                out.extend(base.to_lowercase());
            }
        }
    }
    out
}

/// .txt içinde arama için sadeleştirme: karakter sayısını KORUR (konumlar metinle aynı kalır).
pub fn fk(s: &str) -> String {
    s.chars()
        .map(|c| match c {
            'ı' | 'İ' | 'I' => 'i',
            'ö' | 'Ö' => 'o',
            'ü' | 'Ü' => 'u',
            'ş' | 'Ş' => 's',
            'ç' | 'Ç' => 'c',
            'ğ' | 'Ğ' => 'g',
            _ => {
                let mut l = c.to_lowercase();
                match (l.next(), l.next()) {
                    (Some(x), None) => x,
                    _ => c,
                }
            }
        })
        .collect()
}

/// Boşlukları teke indirir ve kırpar (Swift'teki `\s+` → " " + trimmed).
pub fn collapse_ws(s: &str) -> String {
    s.split_whitespace().collect::<Vec<_>>().join(" ")
}

/// Dosya adında sorun çıkaran karakterleri temizler.
pub fn clean(s: &str, limit_chars: usize) -> String {
    // 1) \r \n \t → boşluk
    let t: String = s.chars().map(|c| if matches!(c, '\r' | '\n' | '\t') { ' ' } else { c }).collect();
    // 2) \s*[:|/\\]\s* → " - "
    let mut u = String::with_capacity(t.len());
    let mut skip_ws = false;
    for c in t.chars() {
        if matches!(c, ':' | '|' | '/' | '\\') {
            while u.ends_with(char::is_whitespace) {
                u.pop();
            }
            u.push_str(" - ");
            skip_ws = true;
        } else if skip_ws && c.is_whitespace() {
        } else {
            skip_ws = false;
            u.push(c);
        }
    }
    // 3) * ? " < > sil
    let u: String = u.chars().filter(|c| !matches!(c, '*' | '?' | '"' | '<' | '>')).collect();
    // 4) boşlukları teke indir, kırp
    let mut t = collapse_ws(&u);
    // 5) baştaki . boşluk - at
    while t.starts_with(['.', ' ', '-']) {
        t.remove(0);
    }
    let t: String = t.chars().take(limit_chars).collect();
    let t = fit_bytes(&t, 240).trim().to_string();
    if t.is_empty() {
        "link".to_string()
    } else {
        t
    }
}

/// Dosya sistemi adı 255 bayt ile sınırlı; ".url" ve " (2)" payı bırakarak bayt cinsinden kısaltır.
pub fn fit_bytes(s: &str, limit: usize) -> String {
    let mut bytes = 0;
    let mut out = String::new();
    for c in s.chars() {
        let n = c.len_utf8();
        if bytes + n > limit {
            break;
        }
        bytes += n;
        out.push(c);
    }
    out
}

/// Eşitleme ve başlık için: harf/rakam/işaret ve "-._~" dışındakileri %XX yapar
/// (Swift'teki `CharacterSet.alphanumerics` Unicode harflerini kodlamaz; tel biçimi aynı kalır).
pub fn enc(s: &str) -> String {
    let mut out = String::with_capacity(s.len());
    for c in s.chars() {
        if c.is_alphanumeric() || is_combining(c) || matches!(c, '-' | '.' | '_' | '~') {
            out.push(c);
        } else {
            let mut b = [0u8; 4];
            for x in c.encode_utf8(&mut b).bytes() {
                out.push_str(&format!("%{:02X}", x));
            }
        }
    }
    out
}

/// Yüzde kodunu çözer; geçersizse None.
pub fn percent_decode(s: &str) -> Option<String> {
    let b = s.as_bytes();
    let mut out = Vec::with_capacity(b.len());
    let mut i = 0;
    while i < b.len() {
        if b[i] == b'%' {
            let h = s.get(i + 1..i + 3)?;
            out.push(u8::from_str_radix(h, 16).ok()?);
            i += 3;
        } else {
            out.push(b[i]);
            i += 1;
        }
    }
    String::from_utf8(out).ok()
}

/// Eşitleme başlığı çözümü: "+" → boşluk, sonra yüzde kodu (geçersizse olduğu gibi).
pub fn dec(s: &str) -> String {
    let t = s.replace('+', " ");
    percent_decode(&t).unwrap_or_else(|| s.to_string())
}

/// URL sorgusu için kodlama (Swift `.urlQueryAllowed` karşılığı).
pub fn encode_query(s: &str) -> String {
    let mut out = String::new();
    for c in s.chars() {
        if c.is_ascii_alphanumeric() || "-._~!$&'()*+,;=:@/?".contains(c) {
            out.push(c);
        } else {
            let mut b = [0u8; 4];
            for x in c.encode_utf8(&mut b).bytes() {
                out.push_str(&format!("%{:02X}", x));
            }
        }
    }
    out
}

/// Cihaz dili Türkçe mi? (LC_ALL / LC_MESSAGES / LANG)
pub fn is_turkish() -> bool {
    static T: OnceLock<bool> = OnceLock::new();
    *T.get_or_init(|| {
        for k in ["LC_ALL", "LC_MESSAGES", "LANG", "LANGUAGE"] {
            if let Ok(v) = std::env::var(k) {
                if !v.is_empty() {
                    return v.to_lowercase().starts_with("tr");
                }
            }
        }
        false
    })
}

/// Metnin Türkçe ve İngilizce karşılığı; cihaz diline göre uygun olanı döndürür.
pub fn l(turkish: &str, english: &str) -> String {
    if is_turkish() { turkish } else { english }.to_string()
}

/// Metindeki ilk linki bulur; sondaki noktalama işaretlerini atar.
pub fn extract_url(text: &str) -> Option<String> {
    let lower = text.to_ascii_lowercase();
    let mut from = 0;
    while let Some(rel) = lower[from..].find("http") {
        let i = from + rel;
        let rest = &lower[i..];
        let plen = if rest.starts_with("https://") {
            8
        } else if rest.starts_with("http://") {
            7
        } else {
            from = i + 4;
            continue;
        };
        let tail = &text[i + plen..];
        let n = tail.find(char::is_whitespace).unwrap_or(tail.len());
        if n == 0 {
            from = i + plen;
            continue;
        }
        let mut u = text[i..i + plen + n].to_string();
        while let Some(last) = u.chars().last() {
            let strip = ".,;:!?\"'>]}".contains(last) || (last == ')' && !u.contains('('));
            if strip {
                u.pop();
            } else {
                break;
            }
        }
        return if u.chars().count() > 8 { Some(u) } else { None };
    }
    None
}

/// "https://kullanici@host:8080/yol" → "host"
pub fn host_of(url: &str) -> Option<String> {
    let after = url.split_once("://")?.1;
    let auth = after.split(['/', '?', '#']).next()?;
    let auth = auth.rsplit('@').next()?;
    let host = if auth.starts_with('[') { auth.split(']').next()?.trim_start_matches('[') } else { auth.split(':').next()? };
    if host.is_empty() {
        None
    } else {
        Some(host.to_string())
    }
}

/// Boşlukları teke indirir ama baştaki/sondaki tek boşlukları korur (arama özetinde `\s+` → " " karşılığı).
pub fn collapse_ws_keep_edges(s: &str) -> String {
    let mut out = String::with_capacity(s.len());
    let mut prev_ws = false;
    for c in s.chars() {
        if c.is_whitespace() {
            if !prev_ws {
                out.push(' ');
            }
            prev_ws = true;
        } else {
            out.push(c);
            prev_ws = false;
        }
    }
    out
}
