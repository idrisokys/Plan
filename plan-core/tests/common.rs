#![allow(dead_code)]
use std::path::{Path, PathBuf};

pub struct Tmp(pub PathBuf);
impl Tmp {
    pub fn new() -> Tmp {
        let p = std::env::temp_dir().join(format!("plan-test-{}", plan_core::store::unique_suffix()));
        std::fs::create_dir_all(&p).unwrap();
        Tmp(p)
    }
    pub fn path(&self) -> &Path {
        &self.0
    }
}
impl Drop for Tmp {
    fn drop(&mut self) {
        let _ = std::fs::remove_dir_all(&self.0);
    }
}
