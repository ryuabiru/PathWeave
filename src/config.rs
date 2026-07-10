use std::{fs, path::PathBuf};

use serde::Deserialize;

#[derive(Debug, Clone, Deserialize)]
pub struct Config {
    pub max_depth: usize,
    pub max_results: usize,
    pub include_hidden: bool,
    pub follow_links: bool,
    pub exclude: Vec<String>,
    pub ignored_prefix_patterns: Vec<String>,
}

impl Default for Config {
    fn default() -> Self {
        Self {
            max_depth: 4,
            max_results: 50,
            include_hidden: false,
            follow_links: false,
            exclude: vec![
                ".git".into(),
                "node_modules".into(),
                "target".into(),
                ".venv".into(),
            ],
            ignored_prefix_patterns: vec![
                r"^[0-9]+[-_ ]*".into(),
                r"^@[a-zA-Z]*".into(),
                r"^_+".into(),
                r"^[0-9]{4}[-_][0-9]{2}[-_]?".into(),
            ],
        }
    }
}

impl Config {
    pub fn load_default() -> Self {
        Self::config_path()
            .and_then(|path| fs::read_to_string(path).ok())
            .and_then(|content| toml::from_str::<Self>(&content).ok())
            .unwrap_or_default()
    }

    fn config_path() -> Option<PathBuf> {
        dirs::config_dir().map(|dir| dir.join("PathWeave").join("config.toml"))
    }
}
