use std::path::PathBuf;

use anyhow::{Context, Result};
use clap::{Parser, Subcommand, ValueEnum};

use crate::config::Config;
use crate::output::{OutputFormat, emit_results};
use crate::search::{SearchOptions, search_paths};

#[derive(Debug, Parser)]
#[command(
    name = "pwv",
    version,
    about = "Fuzzy path search for PowerShell completion"
)]
pub struct Cli {
    #[command(subcommand)]
    command: Commands,
}

#[derive(Debug, Subcommand)]
enum Commands {
    Search(SearchArgs),
    S(ShortSearchArgs),
}

#[derive(Debug, Clone, Parser)]
pub struct SearchArgs {
    #[arg(long, short = 'q')]
    pub query: String,
    #[arg(long, default_value = ".")]
    pub cwd: PathBuf,
    #[arg(long = "type", value_enum, default_value_t = SearchKindArg::Any)]
    pub kind: SearchKindArg,
    #[arg(long, default_value_t = 50)]
    pub max_results: usize,
    #[arg(long, default_value_t = 4)]
    pub max_depth: usize,
    #[arg(long, default_value_t = false)]
    pub hidden: bool,
    #[arg(long, default_value_t = false)]
    pub follow_links: bool,
    #[arg(long, value_enum, default_value_t = OutputArg::Json)]
    pub format: OutputArg,
}

#[derive(Debug, Clone, Parser)]
pub struct ShortSearchArgs {
    pub query: String,
    #[arg(long, default_value = ".")]
    pub cwd: PathBuf,
    #[arg(long = "type", value_enum, default_value_t = SearchKindArg::Any)]
    pub kind: SearchKindArg,
    #[arg(long)]
    pub max_results: Option<usize>,
    #[arg(long)]
    pub max_depth: Option<usize>,
    #[arg(long, default_value_t = false)]
    pub hidden: bool,
    #[arg(long, default_value_t = false)]
    pub follow_links: bool,
    #[arg(long, value_enum, default_value_t = OutputArg::Json)]
    pub format: OutputArg,
}

#[derive(Debug, Clone, Copy, ValueEnum)]
pub enum SearchKindArg {
    Any,
    File,
    Dir,
}

#[derive(Debug, Clone, Copy, ValueEnum)]
pub enum OutputArg {
    Plain,
    Json,
    Jsonl,
}

impl Cli {
    pub fn parse_args() -> Self {
        <Self as Parser>::parse()
    }

    pub fn execute(self) -> Result<()> {
        match self.command {
            Commands::Search(args) => execute_search(args),
            Commands::S(args) => execute_short_search(args),
        }
    }
}

fn execute_search(args: SearchArgs) -> Result<()> {
    let config = Config::load_default();
    let options = SearchOptions::from_search_args(args, &config);
    let results = search_paths(&options)
        .with_context(|| format!("failed to search from {}", options.cwd.display()))?;
    emit_results(&results, OutputFormat::from(options.format));
    Ok(())
}

fn execute_short_search(args: ShortSearchArgs) -> Result<()> {
    let config = Config::load_default();
    let search_args = SearchArgs {
        query: args.query,
        cwd: args.cwd,
        kind: args.kind,
        max_results: args.max_results.unwrap_or(config.max_results),
        max_depth: args.max_depth.unwrap_or(config.max_depth),
        hidden: args.hidden,
        follow_links: args.follow_links,
        format: args.format,
    };

    execute_search(search_args)
}
