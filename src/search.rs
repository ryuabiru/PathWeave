use std::path::{Path, PathBuf};

use anyhow::Result;
use fuzzy_matcher::{FuzzyMatcher, skim::SkimMatcherV2};
use regex::Regex;
use walkdir::{DirEntry, WalkDir};

use crate::{
    cli::{OutputArg, SearchArgs, SearchKindArg},
    config::Config,
    matcher::{detect_match, strip_prefixes},
    scorer::{EntryKind, ScoreInput, SearchResult, path_kind, score_candidate, sort_results},
};

#[derive(Debug, Clone)]
pub struct SearchOptions {
    pub query: String,
    pub cwd: PathBuf,
    pub kind: SearchKindArg,
    pub max_results: usize,
    pub max_depth: usize,
    pub hidden: bool,
    pub follow_links: bool,
    pub format: OutputArg,
    pub exclude: Vec<String>,
    pub ignored_prefix_patterns: Vec<Regex>,
}

impl SearchOptions {
    pub fn from_search_args(args: SearchArgs, config: &Config) -> Self {
        Self {
            query: args.query,
            cwd: args.cwd,
            kind: args.kind,
            max_results: args.max_results,
            max_depth: args.max_depth,
            hidden: args.hidden || config.include_hidden,
            follow_links: args.follow_links || config.follow_links,
            format: args.format,
            exclude: config.exclude.clone(),
            ignored_prefix_patterns: config
                .ignored_prefix_patterns
                .iter()
                .filter_map(|pattern| Regex::new(pattern).ok())
                .collect(),
        }
    }
}

pub fn search_paths(options: &SearchOptions) -> Result<Vec<SearchResult>> {
    let matcher = SkimMatcherV2::default().ignore_case();
    let mut results = Vec::new();
    let retention_limit = options
        .max_results
        .saturating_mul(4)
        .max(options.max_results);

    let walker = WalkDir::new(&options.cwd)
        .max_depth(options.max_depth)
        .follow_links(options.follow_links)
        .into_iter()
        .filter_entry(|entry| should_include_entry(entry, options));

    for entry in walker {
        let entry = match entry {
            Ok(entry) => entry,
            Err(_) => continue,
        };

        if entry.depth() == 0 {
            continue;
        }

        let path = entry.path();
        let kind = path_kind(path);

        if !matches_kind(kind, options.kind) {
            continue;
        }

        let relative = relative_display(&options.cwd, path);
        let file_name = entry.file_name().to_string_lossy().to_string();
        let stripped_name = strip_prefixes(&file_name, &options.ignored_prefix_patterns);
        let fuzzy_name_score = matcher.fuzzy_match(&file_name, &options.query);
        let fuzzy_path_score = matcher.fuzzy_match(&relative, &options.query);

        let Some(details) = detect_match(
            &options.query,
            &file_name,
            &relative,
            &stripped_name,
            fuzzy_name_score,
            fuzzy_path_score,
        ) else {
            continue;
        };

        let score = score_candidate(&ScoreInput {
            relative_path: &relative,
            file_name: &file_name,
            kind,
            depth: entry.depth(),
            match_kind: details.kind,
            match_score: details.score_bonus,
        });

        results.push(SearchResult {
            path: to_windows_relative(&relative, kind),
            display: relative.clone(),
            kind,
            score,
        });

        if retention_limit > 0 && results.len() > retention_limit * 2 {
            sort_results(&mut results);
            results.truncate(retention_limit);
        }
    }

    sort_results(&mut results);
    results.truncate(options.max_results);
    Ok(results)
}

fn matches_kind(kind: EntryKind, requested: SearchKindArg) -> bool {
    match requested {
        SearchKindArg::Any => true,
        SearchKindArg::File => kind == EntryKind::File,
        SearchKindArg::Dir => kind == EntryKind::Directory,
    }
}

fn should_include_entry(entry: &DirEntry, options: &SearchOptions) -> bool {
    if entry.depth() == 0 {
        return true;
    }

    let Some(name) = entry.path().file_name().and_then(|value| value.to_str()) else {
        return true;
    };

    if !options.hidden && name.starts_with('.') {
        return false;
    }

    !options.exclude.iter().any(|excluded| excluded == name)
}

fn relative_display(base: &Path, path: &Path) -> String {
    path.strip_prefix(base)
        .unwrap_or(path)
        .to_string_lossy()
        .replace('\\', "/")
}

fn to_windows_relative(relative: &str, kind: EntryKind) -> String {
    let mut path = format!(".\\{}", relative.replace('/', "\\"));
    if kind == EntryKind::Directory && !path.ends_with('\\') {
        path.push('\\');
    }
    path
}

#[cfg(test)]
mod tests {
    use super::*;
    use tempfile::tempdir;

    #[test]
    fn excludes_hidden_when_not_requested() {
        let dir = tempdir().unwrap();
        std::fs::create_dir(dir.path().join(".secret")).unwrap();

        let options = SearchOptions {
            query: "secret".into(),
            cwd: dir.path().to_path_buf(),
            kind: SearchKindArg::Any,
            max_results: 50,
            max_depth: 4,
            hidden: false,
            follow_links: false,
            format: OutputArg::Json,
            exclude: vec![],
            ignored_prefix_patterns: vec![],
        };

        let results = search_paths(&options).unwrap();
        assert!(results.is_empty());
    }
}
