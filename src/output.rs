use crate::scorer::SearchResult;

#[derive(Debug, Clone, Copy)]
pub enum OutputFormat {
    Plain,
    Json,
    Jsonl,
}

impl From<crate::cli::OutputArg> for OutputFormat {
    fn from(value: crate::cli::OutputArg) -> Self {
        match value {
            crate::cli::OutputArg::Plain => Self::Plain,
            crate::cli::OutputArg::Json => Self::Json,
            crate::cli::OutputArg::Jsonl => Self::Jsonl,
        }
    }
}

pub fn emit_results(results: &[SearchResult], format: OutputFormat) {
    match format {
        OutputFormat::Plain => {
            for result in results {
                println!("{}", result.path);
            }
        }
        OutputFormat::Json => {
            println!(
                "{}",
                serde_json::to_string_pretty(results).unwrap_or_else(|_| "[]".into())
            );
        }
        OutputFormat::Jsonl => {
            for result in results {
                println!(
                    "{}",
                    serde_json::to_string(result).unwrap_or_else(|_| "{}".into())
                );
            }
        }
    }
}
