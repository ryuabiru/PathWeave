use std::{cmp::Ordering, path::Path};

use serde::Serialize;

use crate::matcher::MatchKind;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize)]
#[serde(rename_all = "lowercase")]
pub enum EntryKind {
    File,
    Directory,
}

#[derive(Debug, Clone, Serialize)]
pub struct SearchResult {
    pub path: String,
    pub display: String,
    pub kind: EntryKind,
    pub score: i64,
}

#[derive(Debug, Clone)]
pub struct ScoreInput<'a> {
    pub relative_path: &'a str,
    pub file_name: &'a str,
    pub kind: EntryKind,
    pub depth: usize,
    pub match_kind: MatchKind,
    pub match_score: i64,
}

pub fn score_candidate(input: &ScoreInput<'_>) -> i64 {
    let mut score = input.match_score;

    if input.relative_path == input.file_name {
        score += 40;
    }

    score += match input.kind {
        EntryKind::Directory => 15,
        EntryKind::File => 0,
    };

    score -= input.depth as i64 * 12;
    score -= input.relative_path.len() as i64 / 3;

    score += match input.match_kind {
        MatchKind::Exact => 120,
        MatchKind::ExactWithoutPrefix => 100,
        MatchKind::FileNamePrefix => 80,
        MatchKind::WordBoundary => 60,
        MatchKind::Substring => 40,
        MatchKind::Fuzzy => 0,
        MatchKind::PathFuzzy => -30,
    };

    score
}

pub fn sort_results(results: &mut [SearchResult]) {
    results.sort_by(compare_results);
}

fn compare_results(left: &SearchResult, right: &SearchResult) -> Ordering {
    right
        .score
        .cmp(&left.score)
        .then_with(|| left.path.len().cmp(&right.path.len()))
        .then_with(|| left.path.cmp(&right.path))
}

pub fn path_kind(path: &Path) -> EntryKind {
    if path.is_dir() {
        EntryKind::Directory
    } else {
        EntryKind::File
    }
}
