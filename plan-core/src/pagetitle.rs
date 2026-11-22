//! Bir web sayfasının <title> değerini indirir ve çözümler.
//! std'de TLS olmadığından indirme `curl` ile yapılır (macOS/Linux'ta hazır gelir);
//! ayrıştırma (`parse_title`) saf Rust'tır ve ayrıca test edilir.

use std::io::Read;
use std::process::{Command, Stdio};
use std::time::{Duration, Instant};

const BAD_TITLES: &[&str] = &[
    "just a moment",
    "access denied",
    "attention required",
    "403 forbidden",
    "robot check",
    "are you a robot",
    "verifying you are human",
    "bir dakika",
    "erişim engellendi",
];
const USER_AGENT: &str =
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15";
const MAX_BYTES: usize = 160_000;

/// Sayfanın <title> değerini getirir (en fazla 7 sn); olmazsa None.
pub fn fetch(url: &str) -> Option<String> {
    let mut target = url.to_string();
    if target.to_ascii_lowercase().starts_with("http://") {
        target = format!("https://{}", &target[7..]);
    }
    let mut child = Command::new("curl")
        .args([
            "-s",
            "-L",
            "-i",
            "--max-time",
            "7",
            "--connect-timeout",
            "3",
            "-A",
            USER_AGENT,
            "-H",
            "Accept-Language: tr,en;q=0.8",
            "--",
            &target,
        ])
        .stdout(Stdio::piped())
        .stderr(Stdio::null())
        .spawn()
        .ok()?;
    let mut out = child.stdout.take()?;
    let start = Instant::now();
    let mut buf: Vec<u8> = Vec::new();
    let mut chunk = [0u8; 16 * 1024];
    loop {
        match out.read(&mut chunk) {
            Ok(0) | Err(_) => break,
            Ok(n) => {
                buf.extend_from_slice(&chunk[..n]);
                if buf.len() >= MAX_BYTES || start.elapsed() > Duration::from_secs(8) {
                    break;
                }
                // </title> görüldüyse fazlasını indirme
                let tail = &buf[buf.len().saturating_sub(n + 8)..];
                if find_ci(tail, b"</title>").is_some() {
                    break;
                }
            }
        }
    }
    let _ = child.kill();
    let _ = child.wait();
    let (status, content_type, body) = split_response(&buf)?;
    if !(200..300).contains(&status) {
        return None;
    }
    parse_title(body, content_type.as_deref())
}

/// `curl -i -L` çıktısından son yanıtın (durum, Content-Type, gövde) değerlerini ayırır.
fn split_response(buf: &[u8]) -> Option<(u16, Option<String>, &[u8])> {
    let mut rest = buf;
    let mut status = 0u16;
    let mut ctype = None;
    while rest.starts_with(b"HTTP/") {
        let end = find_ci(rest, b"\r\n\r\n")?;
        let head = String::from_utf8_lossy(&rest[..end]).into_owned();
        let mut lines = head.split("\r\n");
        status = lines.next()?.split_whitespace().nth(1)?.parse().ok()?;
        ctype = lines
            .filter_map(|l| l.split_once(':'))
            .find(|(k, _)| k.eq_ignore_ascii_case("content-type"))
            .map(|(_, v)| v.trim().to_string());
        rest = &rest[end + 4..];
        // 1xx / yönlendirme blokları sonrası yeni başlık gelebilir; gelmezse gövde budur
    }
    if status == 0 {
        None
    } else {
        Some((status, ctype, rest))
    }
}

fn find_ci(hay: &[u8], needle: &[u8]) -> Option<usize> {
    if needle.is_empty() || hay.len() < needle.len() {
        return None;
    }
    (0..=hay.len() - needle.len()).find(|&i| hay[i..i + needle.len()].eq_ignore_ascii_case(needle))
}

fn charset_after(s: &str) -> Option<String> {
    let l = s.to_ascii_lowercase();
    let i = l.find("charset=")? + 8;
    let v: String =
        l[i..].trim_start_matches(['"', '\'']).chars().take_while(|c| c.is_ascii_alphanumeric() || *c == '-' || *c == '_').collect();
    if v.is_empty() {
        None
    } else {
        Some(v)
    }
}

/// Bayt dizisini karakter kümesine göre çözer (UTF-8, Latin-1, Türkçe ISO-8859-9 / Windows-1254).
fn decode(bytes: &[u8], cs: Option<&str>) -> String {
    match cs.map(|c| c.to_ascii_lowercase()).as_deref() {
        Some("iso-8859-1") | Some("latin1") | Some("windows-1252") | Some("iso-8859-15") => bytes.iter().map(|&b| b as char).collect(),
        Some("iso-8859-9") | Some("windows-1254") | Some("latin5") | Some("iso-8859-9-i") => bytes
            .iter()
            .map(|&b| match b {
                0xD0 => 'Ğ',
                0xDD => 'İ',
                0xDE => 'Ş',
                0xF0 => 'ğ',
                0xFD => 'ı',
                0xFE => 'ş',
                _ => b as char,
            })
            .collect(),
        _ => String::from_utf8_lossy(bytes).into_owned(),
    }
}

fn attr(tag: &str, name: &str) -> Option<String> {
    let l = tag.to_ascii_lowercase();
    let mut from = 0;
    while let Some(r) = l[from..].find(name) {
        let i = from + r;
        let before_ok = i == 0 || l.as_bytes()[i - 1].is_ascii_whitespace();
        let after = &tag[i + name.len()..];
        let after_trim = after.trim_start();
        if before_ok && after_trim.starts_with('=') {
            let v = after_trim[1..].trim_start();
            let q = v.chars().next()?;
            if q == '"' || q == '\'' {
                let inner = &v[1..];
                return inner.find(q).map(|e| inner[..e].to_string());
            }
            return Some(v.split(|c: char| c.is_whitespace() || c == '>').next()?.to_string());
        }
        from = i + name.len();
    }
    None
}

fn meta_title(html: &str) -> Option<String> {
    let l = html.to_ascii_lowercase();
    let mut from = 0;
    while let Some(r) = l[from..].find("<meta") {
        let s = from + r;
        let e = l[s..].find('>').map(|x| s + x)?;
        let tag = &html[s..e];
        let key = attr(tag, "property").or_else(|| attr(tag, "name")).unwrap_or_default().to_ascii_lowercase();
        if key == "og:title" || key == "twitter:title" {
            if let Some(c) = attr(tag, "content") {
                if !c.is_empty() {
                    return Some(c);
                }
            }
        }
        from = e;
    }
    None
}

pub fn parse_title(buf: &[u8], content_type: Option<&str>) -> Option<String> {
    let head: String = buf.iter().map(|&b| b as char).collect(); // Latin-1 görünümü (meta charset için)
    let cs = content_type.and_then(charset_after).or_else(|| {
        let l = head.to_ascii_lowercase();
        let i = l.find("<meta").filter(|_| l.contains("charset"))?;
        let _ = i;
        // <meta ... charset=...> etiketini bul
        let mut from = 0;
        while let Some(r) = l[from..].find("<meta") {
            let s = from + r;
            let e = l[s..].find('>').map(|x| s + x)?;
            if let Some(c) = charset_after(&head[s..e]) {
                return Some(c);
            }
            from = e;
        }
        None
    });
    let html = decode(buf, cs.as_deref());
    let lower = html.to_ascii_lowercase();
    let raw = lower
        .find("<title")
        .and_then(|s| {
            let open_end = lower[s..].find('>')? + s + 1;
            let close = lower[open_end..].find("</title")? + open_end;
            Some(html[open_end..close].to_string())
        })
        .or_else(|| meta_title(&html))?;
    let t = crate::text::collapse_ws(&decode_entities(&raw));
    let tl = t.to_lowercase();
    if t.is_empty() || BAD_TITLES.iter().any(|b| tl.starts_with(b)) {
        return None;
    }
    Some(t)
}

pub fn decode_entities(s: &str) -> String {
    // Sayısal: &#123; ve &#x1F;
    let mut out = String::with_capacity(s.len());
    let mut rest = s;
    while let Some(i) = rest.find("&#") {
        out.push_str(&rest[..i]);
        let tail = &rest[i + 2..];
        let (hex, body) = match tail.strip_prefix(['x', 'X']) {
            Some(b) => (true, b),
            None => (false, tail),
        };
        let n = body.find(|c: char| !c.is_ascii_hexdigit()).unwrap_or(body.len());
        if n > 0 && body[n..].starts_with(';') {
            if let Some(ch) = u32::from_str_radix(&body[..n], if hex { 16 } else { 10 }).ok().and_then(char::from_u32) {
                out.push(ch);
                rest = &body[n + 1..];
                continue;
            }
        }
        out.push_str("&#");
        rest = tail;
    }
    out.push_str(rest);
    let named = [
        ("&nbsp;", " "),
        ("&quot;", "\""),
        ("&apos;", "'"),
        ("&lt;", "<"),
        ("&gt;", ">"),
        ("&ccedil;", "ç"),
        ("&Ccedil;", "Ç"),
        ("&ouml;", "ö"),
        ("&Ouml;", "Ö"),
        ("&uuml;", "ü"),
        ("&Uuml;", "Ü"),
        ("&ndash;", "–"),
        ("&mdash;", "—"),
        ("&hellip;", "…"),
        ("&rsquo;", "’"),
        ("&lsquo;", "‘"),
        ("&ldquo;", "“"),
        ("&rdquo;", "”"),
        ("&amp;", "&"),
    ];
    for (k, v) in named {
        out = out.replace(k, v);
    }
    out
}
