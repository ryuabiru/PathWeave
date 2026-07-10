#[path = "../src/matcher.rs"]
mod matcher;

use fuzzy_matcher::{FuzzyMatcher, skim::SkimMatcherV2};
use regex::Regex;

#[test]
fn inbox_matches_prefixed_name() {
    let matcher_engine = SkimMatcherV2::default().ignore_case();
    let stripped = matcher::strip_prefixes("00-Inbox", &[Regex::new(r"^[0-9]+[-_ ]*").unwrap()]);
    let details = matcher::detect_match(
        "inbox",
        "00-Inbox",
        "00-Inbox",
        &stripped,
        &stripped,
        matcher_engine.fuzzy_match("00-Inbox", "inbox"),
        matcher_engine.fuzzy_match("00-Inbox", "inbox"),
    )
    .unwrap();

    assert!(matches!(
        details.kind,
        matcher::MatchKind::ExactWithoutPrefix
    ));
}

#[test]
fn matching_is_case_insensitive() {
    let matcher_engine = SkimMatcherV2::default().ignore_case();
    let details = matcher::detect_match(
        "INBOX",
        "00-Inbox",
        "00-Inbox",
        "Inbox",
        "Inbox",
        matcher_engine.fuzzy_match("00-Inbox", "INBOX"),
        None,
    )
    .unwrap();

    assert!(details.score_bonus >= 950);
}

#[test]
fn fuzzy_matching_finds_myinb() {
    let matcher_engine = SkimMatcherV2::default().ignore_case();
    let details = matcher::detect_match(
        "myinb",
        "my-inbox",
        "my-inbox",
        "my-inbox",
        "my-inbox",
        matcher_engine.fuzzy_match("my-inbox", "myinb"),
        None,
    )
    .unwrap();

    assert!(matches!(details.kind, matcher::MatchKind::Fuzzy));
}
