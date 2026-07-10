# Architecture

PathWeave is split into two layers:

- Rust CLI: file walking, matching, ranking, and result formatting
- PowerShell module: command line inspection, invoking `pwv`, menu display, and line insertion

The Rust binary never mutates the parent PowerShell process. It only returns ranked search results.
