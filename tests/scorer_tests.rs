#[path = "../src/matcher.rs"]
mod matcher;
#[path = "../src/scorer.rs"]
mod scorer;

use matcher::MatchKind;
use scorer::{EntryKind, ScoreInput, SearchResult, score_candidate, sort_results};

#[test]
fn exact_prefixless_match_scores_above_substring() {
    let exact = score_candidate(&ScoreInput {
        relative_path: "00-Inbox",
        file_name: "00-Inbox",
        kind: EntryKind::Directory,
        depth: 1,
        match_kind: MatchKind::ExactWithoutPrefix,
        match_score: 950,
    });
    let substring = score_candidate(&ScoreInput {
        relative_path: "archive/old-inbox",
        file_name: "old-inbox",
        kind: EntryKind::Directory,
        depth: 2,
        match_kind: MatchKind::Substring,
        match_score: 680,
    });

    assert!(exact > substring);
}

#[test]
fn sorting_is_deterministic() {
    let mut results = vec![
        SearchResult {
            path: ".\\archive\\inbox-copy".into(),
            display: "archive/inbox-copy".into(),
            kind: EntryKind::Directory,
            score: 700,
        },
        SearchResult {
            path: ".\\00-Inbox\\".into(),
            display: "00-Inbox".into(),
            kind: EntryKind::Directory,
            score: 950,
        },
        SearchResult {
            path: ".\\my-inbox.md".into(),
            display: "my-inbox.md".into(),
            kind: EntryKind::File,
            score: 800,
        },
    ];

    sort_results(&mut results);
    assert_eq!(results[0].display, "00-Inbox");
    assert_eq!(results[1].display, "my-inbox.md");
}
