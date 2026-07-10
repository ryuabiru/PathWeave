use regex::Regex;

#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord)]
pub enum MatchKind {
    Exact,
    ExactWithoutPrefix,
    FileNamePrefix,
    WordBoundary,
    Substring,
    Fuzzy,
    PathFuzzy,
}

#[derive(Debug, Clone)]
pub struct MatchDetails {
    pub kind: MatchKind,
    pub score_bonus: i64,
}

pub fn normalize(input: &str) -> String {
    input.trim().replace('\\', "/").to_ascii_lowercase()
}

pub fn strip_prefixes(input: &str, patterns: &[Regex]) -> String {
    let mut result = input.to_string();
    for pattern in patterns {
        result = pattern.replace(&result, "").to_string();
    }
    result
}

pub fn detect_match(
    query: &str,
    file_name: &str,
    full_path: &str,
    stripped_file_name: &str,
    stripped_full_path: &str,
    fuzzy_name_score: Option<i64>,
    fuzzy_path_score: Option<i64>,
) -> Option<MatchDetails> {
    let query = normalize(query);
    let file_name = normalize(file_name);
    let full_path = normalize(full_path);
    let stripped_file_name = normalize(stripped_file_name);
    let stripped_full_path = normalize(stripped_full_path);

    if let Some(details) = detect_segment_match(&query, &full_path, &stripped_full_path) {
        return Some(details);
    }

    if file_name == query {
        return Some(MatchDetails {
            kind: MatchKind::Exact,
            score_bonus: 1_000,
        });
    }

    if !stripped_file_name.is_empty() && stripped_file_name == query {
        return Some(MatchDetails {
            kind: MatchKind::ExactWithoutPrefix,
            score_bonus: 950,
        });
    }

    if file_name.starts_with(&query) || stripped_file_name.starts_with(&query) {
        return Some(MatchDetails {
            kind: MatchKind::FileNamePrefix,
            score_bonus: 850,
        });
    }

    if (full_path.starts_with(&query) || stripped_full_path.starts_with(&query))
        && query.contains('/')
    {
        return Some(MatchDetails {
            kind: MatchKind::WordBoundary,
            score_bonus: 780,
        });
    }

    if file_name
        .split(|c: char| !c.is_alphanumeric())
        .any(|part| part == query)
        || full_path
            .split(|c: char| !c.is_alphanumeric())
            .any(|part| part == query)
    {
        return Some(MatchDetails {
            kind: MatchKind::WordBoundary,
            score_bonus: 760,
        });
    }

    if file_name.contains(&query)
        || stripped_file_name.contains(&query)
        || (query.contains('/') && stripped_full_path.contains(&query))
    {
        return Some(MatchDetails {
            kind: MatchKind::Substring,
            score_bonus: 680,
        });
    }

    if let Some(score) = fuzzy_name_score {
        return Some(MatchDetails {
            kind: MatchKind::Fuzzy,
            score_bonus: 500 + score,
        });
    }

    fuzzy_path_score.map(|score| MatchDetails {
        kind: MatchKind::PathFuzzy,
        score_bonus: 350 + score,
    })
}

fn detect_segment_match(
    query: &str,
    full_path: &str,
    stripped_full_path: &str,
) -> Option<MatchDetails> {
    if !query.contains('/') {
        return None;
    }

    let query_segments: Vec<_> = query
        .split('/')
        .filter(|segment| !segment.is_empty())
        .collect();
    let full_segments: Vec<_> = full_path
        .split('/')
        .filter(|segment| !segment.is_empty())
        .collect();
    let stripped_segments: Vec<_> = stripped_full_path
        .split('/')
        .filter(|segment| !segment.is_empty())
        .collect();

    if query_segments.len() != full_segments.len() || full_segments.len() != stripped_segments.len()
    {
        return None;
    }

    if query_segments.len() < 2 {
        return None;
    }

    for index in 0..query_segments.len() - 1 {
        if full_segments[index] != query_segments[index]
            && stripped_segments[index] != query_segments[index]
        {
            return None;
        }
    }

    let query_last = query_segments[query_segments.len() - 1];
    let full_last = full_segments[full_segments.len() - 1];
    let stripped_last = stripped_segments[stripped_segments.len() - 1];

    if full_last == query_last {
        return Some(MatchDetails {
            kind: MatchKind::Exact,
            score_bonus: 980,
        });
    }

    if stripped_last == query_last {
        return Some(MatchDetails {
            kind: MatchKind::ExactWithoutPrefix,
            score_bonus: 930,
        });
    }

    if full_last
        .split(|c: char| !c.is_alphanumeric())
        .any(|part| part == query_last)
        || stripped_last
            .split(|c: char| !c.is_alphanumeric())
            .any(|part| part == query_last)
    {
        return Some(MatchDetails {
            kind: MatchKind::WordBoundary,
            score_bonus: 790,
        });
    }

    if stripped_last.starts_with(query_last) || full_last.starts_with(query_last) {
        return Some(MatchDetails {
            kind: MatchKind::WordBoundary,
            score_bonus: 780,
        });
    }

    if stripped_last.contains(query_last) || full_last.contains(query_last) {
        return Some(MatchDetails {
            kind: MatchKind::Substring,
            score_bonus: 700,
        });
    }

    None
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn strips_prefixes() {
        let patterns = vec![Regex::new(r"^[0-9]+[-_ ]*").unwrap()];
        assert_eq!(strip_prefixes("00-Inbox", &patterns), "Inbox");
    }

    #[test]
    fn path_segments_match_prefix_stripped_last_segment() {
        let details =
            detect_segment_match("document/wiki", "document/md-wiki", "document/wiki").unwrap();
        assert!(matches!(details.kind, MatchKind::ExactWithoutPrefix));
    }

    #[test]
    fn normalizes_windows_path_separators() {
        assert_eq!(normalize(r"Document\Wiki"), "document/wiki");
    }
}
