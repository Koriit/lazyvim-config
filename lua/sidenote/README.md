# sidenote.nvim

Sidenotes and inline comments for markdown files in Neovim, **bit-for-bit
compatible** with the Obsidian [SideNote](https://github.com/mofukuru/SideNote)
plugin. Open the same vault in Neovim or Obsidian — comments round-trip
without conversion.

A note attaches to a span of text (visual selection), is highlighted in
the buffer, and lives in `<vault>/.obsidian/plugins/side-note/data.json`
alongside Obsidian's own state.

## Highlights

- **Vault-native storage** — same `data.json` schema as Obsidian SideNote.
  Comments, settings, and unknown forward-compat keys are preserved on
  every write.
- **Hash-anchored** — each note carries a SHA-256 of the selected text;
  re-resolution finds the new location even after edits, or marks the
  note orphaned when the text is gone.
- **Markdown-only**, with a filetype gate on every keymap.
- **Browse picker** — auto-detects `snacks.picker` → `telescope` →
  `fzf-lua` → `vim.ui.select`. Preview shows the anchor in source,
  with the comment pinned above as virtual lines.
- **Quicklook** floating popup for the note under cursor.
- **Resolved / orphaned** filtering (`R`/`O` flag column in browse).
- **`]n` / `[n`** navigation between visible notes.

## Keymaps

All under `<leader>cn`:

| key            | mode | action                                          |
| -------------- | ---- | ----------------------------------------------- |
| `<leader>cnc`  | x    | create/edit on visual selection                 |
| `<leader>cnc`  | n    | edit the comment under cursor                   |
| `<leader>cnk`  | n    | quicklook the comment(s) at cursor              |
| `<leader>cnl`  | n    | browse all comments in current file             |
| `<leader>cnd`  | n    | delete the comment under cursor                 |
| `<leader>cnr`  | n    | toggle show-resolved (filter)                   |
| `<leader>cnR`  | n    | mark the comment under cursor resolved/unresolved |
| `]n` / `[n`    | n    | next / prev visible note in buffer              |

In the browse picker:

| key       | action                                  |
| --------- | --------------------------------------- |
| `<CR>`    | jump to anchor + open edit float        |
| `<C-d>`   | delete (with confirm)                   |
| `<C-r>`   | mark resolved/unresolved                |
| `<C-x>`   | toggle show-resolved                    |

## Storage

Single JSON at `<vault>/.obsidian/plugins/side-note/data.json`. Vault
discovery walks upward from the buffer's directory looking for
`.obsidian/`; if none is found, on first note creation the plugin
creates `.obsidian/plugins/side-note/data.json` under
`vim.fn.getcwd()` and seeds it with Obsidian SideNote's defaults.

Each comment carries `id` (UUIDv4), `filePath` (vault-relative POSIX),
`startLine` / `startChar` / `endLine` / `endChar` (0-indexed),
`selectedText`, `selectedTextHash` (lowercase SHA-256 hex),
`comment`, `timestamp` (epoch ms), and optional `isOrphaned`,
`commentPath` (sidecar — read-only), `resolved`, `resolvedAt`.

Multiple comments per range are allowed; the picker shows them all.

## Anchor resolution

On every `BufWritePost` of a markdown file under the vault, each
comment for that file is re-resolved:

1. **Neighborhood + hash verify** — search ±10 lines around
   `startLine` for a literal match of `selectedText`; accept only if
   the match's SHA-256 equals `selectedTextHash`. Closest hit wins.
2. **Full-file hash scan** — sliding-window hashes across every line.
   On match, `selectedText` is rewritten to the new substring (so
   anchors survive small edits).
3. **Regex fallback** — only for legacy comments without a hash.
   Hashed comments that lose their hash match are flagged
   `isOrphaned`, never silently re-bound.

Multi-line visual selections are stored as-is, with `selectedText`
preserving embedded `\n` and `endLine` distinct from `startLine`.
This is **less broken** than upstream Obsidian SideNote — its
re-resolution stages collapse `endLine` to `startLine` on every save,
which orphans multi-line notes after the first write. Sidenote.nvim's
Stage 1 catches nearby cases by extending the joined neighborhood to
cover the needle's line span; Stage 2 (on save) does the heavy lifting
for widely-collapsed multi-line notes by hashing across the full file.

The browse preview runs only Stage 1 to keep the UI responsive.
Stage 2 happens on save where a brief blip is acceptable.

## Highlight color

The buffer highlight blends `highlightColor` (default `#FFC800`) at
`highlightOpacity` (default `0.2`) against your colorscheme's
`Normal.bg`. Both values come from `data.json`, so changing them in
Obsidian carries over to Neovim.

## Limitations

- **Multi-line via Obsidian**: multi-line notes work in both
  directions, but if a multi-line note is edited in Obsidian and
  saved, Obsidian's resolver collapses `endLine = startLine` on
  write — re-opening the file in Neovim will then highlight only the
  first line. Re-creating the selection in Neovim restores the full
  range.
- **Concurrent writers**: opening the same vault in Obsidian and
  Neovim and editing notes simultaneously is last-writer-wins. The
  plugin re-reads `data.json` immediately before each save to
  minimize the window, but there's no locking on either side.
- **External renames** (e.g. `git mv` outside Neovim): the comment's
  `filePath` is not updated; affected notes effectively orphan.
  Renames done inside Neovim (`BufFilePost`) are tracked.
- **Sidecar `.md` files**: when Obsidian's markdown-storage mode is
  enabled, comment bodies live in
  `<vault>/<markdownFolder>/<file__path>-sidenote.md`. Sidenote.nvim
  reads these for display compatibility but never writes them — that
  remains Obsidian's responsibility.

## Layout

```
lua/plugins/sidenote.lua    -- lazy.nvim spec + keymaps
lua/sidenote/
  init.lua                  -- public API, autocmds, orchestration
  vault.lua                 -- vault discovery + bootstrap
  storage.lua               -- atomic, key-preserving JSON I/O
  anchor.lua                -- SHA-256 hashing + 3-stage resolver
  highlight.lua             -- extmark management
  ui/float.lua              -- floating-window note editor
  ui/hover.lua              -- quicklook popup
  ui/browse.lua             -- picker integration + custom preview
```
