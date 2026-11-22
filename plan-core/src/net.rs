//! Hızlı Paylaş'ın kullandığı küçük HTTP/1.1 yardımcıları (düz TCP, `Connection: close`).

use std::collections::HashMap;
use std::io::{self, Read, Write};
use std::net::{TcpStream, ToSocketAddrs};
use std::time::Duration;

#[derive(Debug, Clone)]
pub struct NetError(pub String);
impl std::fmt::Display for NetError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str(&self.0)
    }
}
impl From<io::Error> for NetError {
    fn from(e: io::Error) -> Self {
        let t = match e.kind() {
            io::ErrorKind::TimedOut | io::ErrorKind::WouldBlock => crate::text::l("zaman aşımı", "timeout"),
            _ => e.to_string(),
        };
        NetError(t)
    }
}
pub type NetResult<T> = Result<T, NetError>;

pub const MAX_HEAD: usize = 16384;

pub fn find_sep(buf: &[u8]) -> Option<usize> {
    buf.windows(4).position(|w| w == b"\r\n\r\n")
}

/// Ayrıştırılmış başlık bloğu (istek ya da yanıt). Anahtarlar küçük harftir.
#[derive(Debug, Default, Clone)]
pub struct Head {
    pub first: Vec<String>,
    pub headers: HashMap<String, String>,
}

impl Head {
    pub fn parse(head: &[u8]) -> Head {
        let s = String::from_utf8_lossy(head);
        let mut lines = s.split("\r\n");
        let first = lines.next().unwrap_or("").split(' ').filter(|x| !x.is_empty()).map(str::to_string).collect();
        let mut headers = HashMap::new();
        for l in lines {
            if let Some((k, v)) = l.split_once(':') {
                headers.insert(k.to_lowercase(), v.trim().to_string());
            }
        }
        Head { first, headers }
    }
    pub fn status(&self) -> i32 {
        self.first.get(1).and_then(|x| x.parse().ok()).unwrap_or(0)
    }
    pub fn method(&self) -> &str {
        self.first.first().map(|s| s.as_str()).unwrap_or("")
    }
    pub fn target(&self) -> &str {
        self.first.get(1).map(|s| s.as_str()).unwrap_or("")
    }
    pub fn get(&self, k: &str) -> Option<&str> {
        self.headers.get(k).map(|s| s.as_str())
    }
}

/// İstemci bağlantısı (eşzamanlı; arka plan iş parçacığında kullanılır).
pub struct Conn {
    s: TcpStream,
    buf: Vec<u8>,
}

impl Conn {
    /// `addr`: "host:port". 8 sn bağlantı, 30 sn okuma/yazma zaman aşımı.
    pub fn connect(addr: &str) -> NetResult<Conn> {
        let mut last = None;
        for a in addr.to_socket_addrs().map_err(|_| NetError(crate::text::l("bağlantı kurulamadı", "could not connect")))? {
            match TcpStream::connect_timeout(&a, Duration::from_secs(8)) {
                Ok(s) => {
                    s.set_read_timeout(Some(Duration::from_secs(30)))?;
                    s.set_write_timeout(Some(Duration::from_secs(30)))?;
                    let _ = s.set_nodelay(true);
                    return Ok(Conn { s, buf: vec![] });
                }
                Err(e) => last = Some(e),
            }
        }
        let _ = last;
        Err(NetError(crate::text::l("bağlantı kurulamadı", "could not connect")))
    }

    pub fn send(&mut self, data: &[u8]) -> NetResult<()> {
        self.s.write_all(data)?;
        Ok(())
    }

    /// Ağdan biraz okuyup tampona ekler; bağlantı kapandıysa false.
    fn fill(&mut self) -> NetResult<bool> {
        let mut tmp = [0u8; 64 * 1024];
        let n = self.s.read(&mut tmp)?;
        if n == 0 {
            return Ok(false);
        }
        self.buf.extend_from_slice(&tmp[..n]);
        Ok(true)
    }

    pub fn read_head(&mut self) -> NetResult<Head> {
        loop {
            if let Some(i) = find_sep(&self.buf) {
                let head = Head::parse(&self.buf[..i]);
                self.buf.drain(..i + 4);
                return Ok(head);
            }
            if self.buf.len() > MAX_HEAD {
                return Err(NetError(crate::text::l("geçersiz yanıt", "invalid response")));
            }
            if !self.fill()? {
                return Err(NetError(crate::text::l("bağlantı beklenmedik şekilde kapandı", "connection closed unexpectedly")));
            }
        }
    }

    pub fn read_body(&mut self, len: usize, sink: &mut dyn FnMut(&[u8]) -> io::Result<()>) -> NetResult<()> {
        let mut left = len;
        while left > 0 {
            if self.buf.is_empty() && !self.fill()? {
                return Err(NetError(crate::text::l("alma yarım kaldı", "incomplete")));
            }
            let n = self.buf.len().min(left);
            sink(&self.buf[..n])?;
            self.buf.drain(..n);
            left -= n;
        }
        Ok(())
    }
}
