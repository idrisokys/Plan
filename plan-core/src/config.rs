//! Kalıcı ayarlar (macOS UserDefaults karşılığı): düz `anahtar=değer` dosyası.

use std::collections::BTreeMap;
use std::path::{Path, PathBuf};

pub const MIN_FONT: f64 = 10.0;
pub const MAX_FONT: f64 = 32.0;
pub const DEFAULT_FONT: f64 = 16.0;

pub fn config_dir() -> PathBuf {
    if let Some(d) = std::env::var_os("PLAN_CONFIG_DIR") {
        return PathBuf::from(d);
    }
    let home = crate::store::home_dir();
    if cfg!(target_os = "macos") {
        home.join("Library/Application Support/Plan")
    } else if cfg!(windows) {
        std::env::var_os("APPDATA").map(|a| PathBuf::from(a).join("Plan")).unwrap_or_else(|| home.join("Plan"))
    } else {
        std::env::var_os("XDG_CONFIG_HOME").map(|x| PathBuf::from(x).join("plan")).unwrap_or_else(|| home.join(".config/plan"))
    }
}

#[derive(Debug, Clone)]
pub struct Settings {
    path: PathBuf,
    map: BTreeMap<String, String>,
}

impl Settings {
    pub fn load_from(path: &Path) -> Settings {
        let mut map = BTreeMap::new();
        if let Ok(s) = std::fs::read_to_string(path) {
            for l in s.lines() {
                if let Some((k, v)) = l.split_once('=') {
                    map.insert(k.trim().to_string(), v.trim().to_string());
                }
            }
        }
        Settings { path: path.to_path_buf(), map }
    }

    pub fn load() -> Settings {
        Self::load_from(&config_dir().join("settings.conf"))
    }

    fn save(&self) {
        if let Some(d) = self.path.parent() {
            let _ = std::fs::create_dir_all(d);
        }
        let body: String = self.map.iter().map(|(k, v)| format!("{k}={v}\n")).collect();
        let _ = crate::store::atomic_write(&self.path, body.as_bytes());
    }

    pub fn get(&self, k: &str) -> Option<&str> {
        self.map.get(k).map(|s| s.as_str())
    }
    pub fn set(&mut self, k: &str, v: &str) {
        self.map.insert(k.into(), v.into());
        self.save();
    }
    pub fn get_bool(&self, k: &str) -> bool {
        self.get(k) == Some("1")
    }
    pub fn set_bool(&mut self, k: &str, v: bool) {
        self.set(k, if v { "1" } else { "0" });
    }

    /// Hızlı Paylaş kimliği (ilk çağrıda üretilip saklanır).
    pub fn qs_id(&mut self) -> String {
        if let Some(i) = self.get("qsId") {
            if !i.is_empty() {
                return i.to_string();
            }
        }
        let id = random_hex32();
        self.set("qsId", &id);
        id
    }

    pub fn qs_on(&self) -> bool {
        self.get_bool("qsOn")
    }
    pub fn set_qs_on(&mut self, v: bool) {
        self.set_bool("qsOn", v);
    }
    pub fn always_on_top(&self) -> bool {
        self.get_bool("alwaysOnTop")
    }
    pub fn set_always_on_top(&mut self, v: bool) {
        self.set_bool("alwaysOnTop", v);
    }

    /// Paylaşımla gelen dosyaların klasörü (varsayılan: İndirilenler).
    pub fn receive_dir(&self) -> PathBuf {
        let d =
            self.get("recvDir").filter(|s| !s.is_empty()).map(PathBuf::from).unwrap_or_else(|| crate::store::home_dir().join("Downloads"));
        let _ = std::fs::create_dir_all(&d);
        d
    }
    pub fn set_receive_dir(&mut self, p: &Path) {
        self.set("recvDir", &p.to_string_lossy());
    }

    pub fn font_size(&self) -> f64 {
        self.get("fontSize")
            .and_then(|v| v.parse::<f64>().ok())
            .filter(|v| *v != 0.0)
            .map(|v| v.clamp(MIN_FONT, MAX_FONT))
            .unwrap_or(DEFAULT_FONT)
    }
    pub fn bump_font(&mut self, delta: f64) -> f64 {
        let v = (self.font_size() + delta).clamp(MIN_FONT, MAX_FONT);
        self.set("fontSize", &v.to_string());
        v
    }
}

/// 32 onaltılık karakterlik rastgele kimlik (std'nin rastgele tohumlu hash'inden).
pub fn random_hex32() -> String {
    use std::collections::hash_map::RandomState;
    use std::hash::{BuildHasher, Hasher};
    let mut out = String::new();
    for i in 0..2u8 {
        let mut h = RandomState::new().build_hasher();
        h.write_u8(i);
        h.write_u32(std::process::id());
        if let Ok(d) = std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH) {
            h.write_u128(d.as_nanos());
        }
        out.push_str(&format!("{:016x}", h.finish()));
    }
    out
}
