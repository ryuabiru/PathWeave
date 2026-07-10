# PathWeave

[日本語版 README](README_ja.md)

PathWeave is a fuzzy path completion helper for PowerShell.

It lets you type a meaningful part of a file or directory name and complete it anywhere a command argument accepts a path:

```powershell
nvim inbox<Tab>
Get-Content daily<Tab>
Copy-Item notes<Tab> .\backup\
rg keyword archive<Tab>
```

The project is split into two pieces:

- `pwv`: a Rust CLI that walks the filesystem, matches paths, scores candidates, and prints results
- `PathWeave`: a PowerShell module that reads the current PSReadLine buffer, calls `pwv`, and inserts the selected path

Rust never mutates the parent shell. PowerShell owns the prompt, cursor, key bindings, and insertion behavior.

License: MIT. See [LICENSE](LICENSE).

## Status

The current MVP supports:

- recursive search under the current directory
- partial, word-boundary, prefix-stripped, and fuzzy matching
- JSON output for robust PowerShell integration
- `Ctrl+Spacebar` explicit PathWeave completion
- optional `Tab` integration
- `Tab` to cycle forward through PathWeave matches
- `Shift+Tab` to cycle backward through PathWeave matches
- standard PowerShell completion first, PathWeave fallback only when standard completion has no matches
- self-contained Rust and PowerShell tests

## Build

From the repository root:

```bash
cargo build --release
```

This creates:

```text
target/release/pwv
```

On Windows the binary is:

```text
target\release\pwv.exe
```

During development the PowerShell module can find local builds in `target/release` and `target/debug`, so you do not need a formal install just to try it.

## Try It Without Installing

In PowerShell, from the repository root:

```powershell
Import-Module .\powershell\PathWeave.psd1 -Force
Enable-PathWeave -UseTab
```

Now try:

```powershell
nvim tom<Tab>
```

If standard PowerShell completion has no match, PathWeave searches below the current directory. Repeated `Tab` moves forward through PathWeave matches, and `Shift+Tab` moves backward.

For explicit PathWeave completion without touching `Tab`:

```powershell
Import-Module .\powershell\PathWeave.psd1 -Force
Enable-PathWeave
```

Then press `Ctrl+Spacebar` after a query:

```powershell
nvim inbox<Ctrl+Spacebar>
```

## Daily Use Setup

For everyday use, make sure both pieces are visible to PowerShell:

1. Put `pwv` on `PATH`, or keep using a repository-local build
2. Import the module from your PowerShell profile
3. Enable either explicit completion or `Tab` integration

Example profile snippet:

```powershell
Import-Module "C:\path\to\PathWeave\powershell\PathWeave.psd1"
Enable-PathWeave -UseTab
```

If you prefer to keep standard `Tab` untouched:

```powershell
Import-Module "C:\path\to\PathWeave\powershell\PathWeave.psd1"
Enable-PathWeave
```

## PowerShell Behavior

With `Enable-PathWeave -UseTab`, `Tab` behaves like this:

1. Ask PowerShell for standard completions
2. If standard completions exist, use normal PowerShell completion
3. If no standard completion exists, call `pwv search`
4. Insert the best PathWeave match into the active token
5. Repeated `Tab` cycles forward through PathWeave matches
6. `Shift+Tab` cycles backward through PathWeave matches

The insertion is token-scoped. For example:

```powershell
Copy-Item inbox .\backup\
```

Completing `inbox` changes only that argument and keeps `.\backup\` in place.

## CLI Usage

Search from the current directory:

```powershell
pwv search --query inbox --cwd . --format json
```

Short form:

```powershell
pwv s inbox --cwd .
```

Useful options:

```text
--query <QUERY>
--cwd <PATH>
--type <any|file|dir>
--max-results <NUMBER>
--max-depth <NUMBER>
--hidden
--follow-links
--format <plain|json|jsonl>
```

Example JSON:

```json
[
  {
    "path": ".\\00-Inbox\\",
    "display": "00-Inbox",
    "kind": "directory",
    "score": 1090
  }
]
```

## Matching And Ranking

PathWeave scores candidates deterministically. Higher ranked matches include:

- exact filename matches
- exact matches after weak organizer prefixes such as `00-`, `01_`, `@`, `_`, or date-like prefixes
- filename prefix matches
- word-boundary matches
- substring matches
- fuzzy matches
- full-path fuzzy matches

It also slightly prefers:

- paths closer to the current directory
- matches in the filename rather than only the full path
- shorter paths when scores tie

Hidden entries are excluded by default. The default excluded directories are:

```text
.git
node_modules
target
.venv
```

## Testing

Run the Rust test suite:

```bash
cargo test
```

Run the PowerShell self-tests without Pester:

```powershell
pwsh -NoProfile -File powershell\tests\run-tests.ps1
```

Build a Windows release zip:

```powershell
pwsh -NoProfile -File powershell\package-release.ps1
```

This creates a release-ready archive under `dist\`, containing `pwv.exe`, the PowerShell module, the sample profile, and the top-level documentation files.

The PowerShell tests cover:

- path quoting
- token extraction
- insertion range
- `Tab` fallback behavior
- repeated `Tab` cycling
- `Shift+Tab` reverse cycling
- real `pwv` CLI results feeding buffer replacement

## Lightweight Search Notes

PathWeave is intentionally simple:

- no background process
- no index database
- no long-lived cache
- no terminal UI in Rust
- bounded result retention during search

The CLI walks the current directory tree on demand and keeps only a bounded set of high-ranking candidates before final sorting. This keeps memory usage tied to `--max-results` rather than growing with every matching path.

There is also a CLI integration test that creates hundreds of matching files and verifies that `--max-results` is respected while the top-ranked match survives the bounded retention pass.

## Troubleshooting

If `Tab` does not use PathWeave, reload the module and enable `Tab` integration:

```powershell
Import-Module .\powershell\PathWeave.psd1 -Force
Enable-PathWeave -UseTab
```

If `pwv` cannot be found, build it:

```bash
cargo build --release
```

Then either keep using the repository-local build or put the release binary on `PATH`.

If standard PowerShell completion has candidates, PathWeave intentionally stays out of the way. Try a query that standard completion cannot resolve, such as a meaningful middle portion of a filename.

## Project Layout

```text
src/
  cli.rs
  config.rs
  matcher.rs
  output.rs
  scorer.rs
  search.rs
powershell/
  PathWeave.psd1
  PathWeave.psm1
  tests/run-tests.ps1
tests/
  matcher_tests.rs
  scorer_tests.rs
  search_tests.rs
docs/
  architecture.md
  completion-behavior.md
examples/
  Microsoft.PowerShell_profile.ps1
```
