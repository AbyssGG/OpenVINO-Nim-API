# Documentation

This directory is the English documentation set for OpenVINO Nim API. The
repository keeps the API and implementation vocabulary in English so that
code, diagnostics and links remain searchable; [the Chinese README](../README_zh-CN.md)
provides a bilingual entry point.

## Choose a path

| Question | Document |
|---|---|
| I am new to the project | [Getting started](getting-started.md) |
| I need the public types and functions | [API overview](api-overview.md) |
| I need the generated symbol pages | [API site](https://abyssgg.github.io/OpenVINO-Nim-API/) once Pages is enabled, or local `build/docs/index.html` after `nimble docs` |
| I need to know what really works | [Compatibility](compatibility.md) |
| I need to diagnose a loader or runtime failure | [Troubleshooting](troubleshooting.md) |
| I need the C binding boundary | [C API coverage](c-api-coverage.md) |
| I am planning a feature | [Roadmap](roadmap.md) |
| I need ownership details | [Ownership](ownership.md) |
| I am migrating from the prototype | [Migration guide](resonance-migration.md) |

## Documentation commands

From the repository root:

```shell
nimble docs
```

The task generates a page for every public managed module, the explicit raw
entry point, and a merged symbol index under `build/docs`. The output is an
artifact in CI and can also be opened locally at `build/docs/index.html`.

## Optional GitHub Pages deployment

The `docs-pages` workflow runs `nim doc --project --index:on --outdir:htmldocs`
on the main module (with `--path:src`), then adds the curated public-module
pages and index from `nimble docs`. It deploys the result to
GitHub Pages. A maintainer must first enable Pages for GitHub Actions and allow
the `github-pages` environment; until then, the normal CI artifact remains the
supported hosted copy. Publishing runs on pushes to `main` or manual dispatch,
separately from required CI. The site documents `main`, not a frozen release.

Markdown is checked by `nimble lint`. New documents need one H1 heading,
language-tagged fenced blocks, descriptive links and a final newline.

## Scope rule

Documentation distinguishes three states: implemented and tested, available in
the raw layer but not wrapped by the managed API, and planned. Device discovery
or a successful compile is never treated as proof of inference support on a
device that has not been tested.
