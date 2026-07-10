use std::fs;

use assert_cmd::Command;
use tempfile::tempdir;

#[test]
fn finds_expected_matches_in_rank_order() {
    let dir = tempdir().unwrap();
    fs::create_dir(dir.path().join("00-Inbox")).unwrap();
    fs::write(dir.path().join("my-inbox.md"), "").unwrap();
    fs::create_dir_all(dir.path().join("archive").join("inbox-copy")).unwrap();
    fs::create_dir(dir.path().join("old-inbox-backup")).unwrap();

    let results = run_search_json(
        dir.path(),
        &[
            "search",
            "--query",
            "inbox",
            "--cwd",
            dir.path().to_str().unwrap(),
        ],
    );
    let displays: Vec<_> = results
        .iter()
        .map(|result| result["display"].as_str().unwrap())
        .collect();

    assert_eq!(displays[0], "00-Inbox");
    assert!(displays.iter().any(|value| *value == "my-inbox.md"));
    assert!(displays.iter().any(|value| *value == "old-inbox-backup"));
    assert!(displays.iter().any(|value| *value == "archive/inbox-copy"));
}

#[test]
fn respects_max_depth() {
    let dir = tempdir().unwrap();
    fs::create_dir_all(dir.path().join("a").join("b").join("c").join("deep-inbox")).unwrap();

    let results = run_search_json(
        dir.path(),
        &[
            "search",
            "--query",
            "inbox",
            "--cwd",
            dir.path().to_str().unwrap(),
            "--max-depth",
            "2",
        ],
    );
    assert!(results.is_empty());
}

#[test]
fn can_find_unicode_names() {
    let dir = tempdir().unwrap();
    fs::create_dir(dir.path().join("日本語Inbox")).unwrap();

    let results = run_search_json(
        dir.path(),
        &[
            "search",
            "--query",
            "inbox",
            "--cwd",
            dir.path().to_str().unwrap(),
        ],
    );
    assert_eq!(results[0]["display"].as_str().unwrap(), "日本語Inbox");
}

#[test]
fn filters_by_type_and_emits_windows_style_paths() {
    let dir = tempdir().unwrap();
    fs::create_dir(dir.path().join("00-Inbox")).unwrap();
    fs::write(dir.path().join("00-Inbox.md"), "").unwrap();

    let results = run_search_json(
        dir.path(),
        &[
            "search",
            "--query",
            "inbox",
            "--cwd",
            dir.path().to_str().unwrap(),
            "--type",
            "dir",
        ],
    );

    assert_eq!(results.len(), 1);
    assert_eq!(results[0]["kind"].as_str().unwrap(), "directory");
    assert_eq!(results[0]["path"].as_str().unwrap(), ".\\00-Inbox\\");
}

#[test]
fn short_subcommand_returns_json_by_default() {
    let dir = tempdir().unwrap();
    fs::create_dir(dir.path().join("01-Projects")).unwrap();

    let results = run_search_json(
        dir.path(),
        &["s", "proj", "--cwd", dir.path().to_str().unwrap()],
    );
    assert_eq!(results[0]["display"].as_str().unwrap(), "01-Projects");
}

#[test]
fn plain_output_writes_only_paths() {
    let dir = tempdir().unwrap();
    fs::create_dir(dir.path().join("00-Inbox")).unwrap();

    let mut command = Command::cargo_bin("pwv").unwrap();
    let output = command
        .args([
            "search",
            "--query",
            "inbox",
            "--cwd",
            dir.path().to_str().unwrap(),
            "--format",
            "plain",
        ])
        .assert()
        .success()
        .get_output()
        .stdout
        .clone();

    let stdout = String::from_utf8(output).unwrap();
    assert_eq!(stdout.trim(), ".\\00-Inbox\\");
}

#[test]
fn invalid_type_argument_fails_as_cli() {
    let dir = tempdir().unwrap();

    let mut command = Command::cargo_bin("pwv").unwrap();
    command
        .args([
            "search",
            "--query",
            "inbox",
            "--cwd",
            dir.path().to_str().unwrap(),
            "--type",
            "invalid",
        ])
        .assert()
        .failure();
}

#[test]
fn caps_large_result_sets_to_requested_max_results() {
    let dir = tempdir().unwrap();
    fs::create_dir(dir.path().join("00-Inbox")).unwrap();
    for index in 0..300 {
        fs::write(dir.path().join(format!("bulk-inbox-{index:03}.md")), "").unwrap();
    }

    let results = run_search_json(
        dir.path(),
        &[
            "search",
            "--query",
            "inbox",
            "--cwd",
            dir.path().to_str().unwrap(),
            "--max-results",
            "5",
        ],
    );

    assert_eq!(results.len(), 5);
    assert_eq!(results[0]["display"].as_str().unwrap(), "00-Inbox");
}

#[test]
fn matches_path_queries_against_prefix_stripped_segments() {
    let dir = tempdir().unwrap();
    fs::create_dir_all(dir.path().join("document").join("00-wiki")).unwrap();
    fs::create_dir_all(dir.path().join("document").join("wiki-archive")).unwrap();

    let results = run_search_json(
        dir.path(),
        &[
            "search",
            "--query",
            "document/wiki",
            "--cwd",
            dir.path().to_str().unwrap(),
        ],
    );

    let displays: Vec<_> = results
        .iter()
        .map(|result| result["display"].as_str().unwrap())
        .collect();

    assert!(!displays.is_empty());
    assert_eq!(displays[0], "document/00-wiki");
}

#[test]
fn path_queries_accept_windows_separators() {
    let dir = tempdir().unwrap();
    fs::create_dir_all(dir.path().join("document").join("md-wiki")).unwrap();
    fs::create_dir_all(dir.path().join("document").join("wiki-archive")).unwrap();

    let results = run_search_json(
        dir.path(),
        &[
            "search",
            "--query",
            r"document\wiki",
            "--cwd",
            dir.path().to_str().unwrap(),
        ],
    );

    assert_eq!(results[0]["display"].as_str().unwrap(), "document/md-wiki");
}

#[test]
fn path_queries_prefer_exact_last_segment_over_prefix_stripped_match() {
    let dir = tempdir().unwrap();
    fs::create_dir_all(dir.path().join("document").join("wiki")).unwrap();
    fs::create_dir_all(dir.path().join("document").join("00-wiki")).unwrap();

    let results = run_search_json(
        dir.path(),
        &[
            "search",
            "--query",
            "document/wiki",
            "--cwd",
            dir.path().to_str().unwrap(),
        ],
    );

    assert_eq!(results[0]["display"].as_str().unwrap(), "document/wiki");
}

#[test]
fn path_queries_prefer_matching_parent_directory_context() {
    let dir = tempdir().unwrap();
    fs::create_dir_all(dir.path().join("docs").join("00-Inbox")).unwrap();
    fs::create_dir_all(dir.path().join("archive").join("00-Inbox")).unwrap();

    let results = run_search_json(
        dir.path(),
        &[
            "search",
            "--query",
            "docs/inbox",
            "--cwd",
            dir.path().to_str().unwrap(),
        ],
    );

    assert_eq!(results[0]["display"].as_str().unwrap(), "docs/00-Inbox");
}

fn run_search_json(cwd: &std::path::Path, args: &[&str]) -> Vec<serde_json::Value> {
    let mut command = Command::cargo_bin("pwv").unwrap();
    let output = command
        .current_dir(cwd)
        .args(args)
        .assert()
        .success()
        .get_output()
        .stdout
        .clone();

    serde_json::from_slice(&output).unwrap()
}
