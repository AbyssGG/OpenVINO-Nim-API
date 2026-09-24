# Development tools

Tools used by `nimble` tasks and CI. They are development aids, not part of
the published package surface, and nothing under `src/` may import them.

Every tool here is written in Nim so that contributors need no toolchain
beyond the one the package already requires.

| Tool | Purpose | Invoked by |
|---|---|---|
| `mdcheck.nim` | Checks the mechanically verifiable Markdown rules from `STYLE_GUIDE.md`: one ATX H1 per document, balanced fences, a language tag on every fence, LF endings, a final newline, no placeholder link text. Also requires `DEVLOG.md` to exist and to carry the same number of entries in its English and Chinese halves | `nimble lint` |

Run a tool directly during development:

```shell
nim r --hints:off tools/mdcheck.nim
```

Tools follow the same style rules as production code. They are formatted by
`nimble format` and type-checked with `--styleCheck:error` by `nimble lint`.

If a binding generator is adopted later, it lands here together with its
pinned input version and a note stating that its output must never be
hand-edited.
