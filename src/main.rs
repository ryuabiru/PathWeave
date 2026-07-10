mod cli;
mod config;
mod matcher;
mod output;
mod scorer;
mod search;

use anyhow::Result;

fn main() {
    if let Err(error) = run() {
        eprintln!("pwv: {error}");
        std::process::exit(1);
    }
}

fn run() -> Result<()> {
    let cli = cli::Cli::parse_args();
    cli.execute()
}
