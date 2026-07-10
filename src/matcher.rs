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
    input.trim().to_ascii_lowercase()
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
    fuzzy_name_score: Option<i64>,
    fuzzy_path_score: Option<i64>,
) -> Option<MatchDetails> {
    let query = normalize(query);
    let file_name = normalize(file_name);
    let full_path = normalize(full_path);
    let stripped_file_name = normalize(stripped_file_name);

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

    if file_name.contains(&query) || stripped_file_name.contains(&query) {
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

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn strips_prefixes() {
        let patterns = vec![Regex::new(r"^[0-9]+[-_ ]*").unwrap()];
        assert_eq!(strip_prefixes("00-Inbox", &patterns), "Inbox");
    }
}
