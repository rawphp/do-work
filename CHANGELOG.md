# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [1.0.0] - 2026-03-14

### Added

- `/do-work start [brief]` — records brief, runs ideate, and decomposes into REQ files in one shot
- `/do-work go [UR-NNN]` — verifies REQ coverage and auto-runs if confidence >= 90%
- `/do-work intake [brief]` — records brief verbatim as next UR file
- `/do-work capture [UR-NNN]` — decomposes a UR into discrete REQ task files
- `/do-work ideate [UR-NNN]` — surfaces assumptions, risks, and connections before decomposition
- `/do-work verify [UR-NNN]` — scores REQ coverage against the original brief (0-100%)
- `/do-work run` — executes backlog with TDD loop, one REQ at a time, commit per REQ
- `/do-work install` — creates per-project `do-work/` folder structure
- `--no-ideate` flag for `start` to skip creative review
- `--force` flag for `go` to run regardless of confidence score
- `--auto-fix` flag for `go` and `verify` to auto-create missing REQs
- One-liner install script (`install.sh`)
- MIT license
- Contributing guide
