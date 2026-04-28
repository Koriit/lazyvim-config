# neogit-hunk-preview

Side-by-side preview of a [Neogit](https://github.com/NeogitOrg/neogit) hunk —
the diff on the left, the post-change file content rendered with the file's
real filetype on the right. Designed for reviewing large new sections
(especially markdown) where the `+`/`-` line-by-line diff layout makes prose
hard to read.

```
┌──────────── diff ────────────┐  ┌──── README.md  42-58 ────┐
│ @@ -41,1 +42,17 @@           │  │                          │
│  ## Heading                  │  │ ## Heading               │
│ +                            │  │                          │
│ +Some long paragraph that    │  │ Some long paragraph that │
│ +reads as wrapped prose...   │  │ reads as wrapped prose…  │
│ +                            │  │                          │
│ +- bullet one                │  │ • bullet one             │
│ +- bullet two                │  │ • bullet two             │
└──────────────────────────────┘  └──────────────────────────┘
```

The left pane uses Neogit's own highlight groups (`NeogitDiffAdd`,
`NeogitDiffDelete`, `NeogitDiffContext`, `NeogitHunkHeader`), word-level
inline diffs (`NeogitDiffAddInline` / `NeogitDiffDeleteInline`), and
treesitter syntax — visually identical to Neogit's status buffer.

The right pane gets the file's filetype set, so `render-markdown.nvim`,
treesitter, and any other filetype-attached rendering plugin engages
automatically.

## Installation

Local plugin loaded via lazy.nvim:

```lua
return {
  dir = vim.fn.stdpath("config") .. "/lua/neogit-hunk-preview",
  name = "neogit-hunk-preview",
  dev = true,
  dependencies = { "NeogitOrg/neogit" },
  event = "FileType NeogitStatus",
  config = function()
    require("neogit-hunk-preview").setup()
  end,
}
```

## Usage

### In a NeogitStatus buffer

| Mode   | Key         | Action                                     |
| ------ | ----------- | ------------------------------------------ |
| normal | `<leader>p` | Preview the hunk under the cursor          |
| visual | `<leader>p` | Preview the selected sub-range of the hunk |

In normal mode the cursor must be inside a hunk (the `@@` header or any of
its content lines). In visual mode the selection determines which slice of
the hunk gets shown — useful for huge hunks where you only care about a
specific section.

### Inside the preview float

| Key         | Action                                  |
| ----------- | --------------------------------------- |
| `q`, `<Esc>` | Close both panes                        |
| `<Tab>`     | Toggle focus between the diff and the rendered pane |

Cursor movement in either pane mirrors to the other through a precomputed
line map. Mouse-wheel and `<C-d>`/`<C-u>` scroll are kept in sync via vim's
built-in `scrollbind`.

## Configuration

```lua
require("neogit-hunk-preview").setup({
  key = "<leader>p",  -- default
})
```

`key` is the buffer-local mapping installed on every NeogitStatus buffer.
Pass any lhs you like, or set it to `false` if you want to wire your own
mapping to `require("neogit-hunk-preview").peek()`.

## How it works

* Reads the hunk under cursor via Neogit's internal
  `Ui:get_hunk_or_filename_under_cursor()` (and `Ui:item_hunks(.., partial=true)`
  for visual selections — the same primitive Neogit uses for partial staging).
* The right pane reads the post-change line range from the worktree file at
  `disk_from..disk_from+disk_len-1`. The left-to-right line map is built by
  walking `hunk.lines` and counting non-`-` entries.
* Highlight stack on the left pane (priority order):
  - `190` — line backgrounds (`hl_eol = true` extmarks, mirroring
    `Buffer:add_line_highlight` in Neogit's source so they don't bury overlays)
  - `210` — treesitter `@capture` extmarks parsed from the stripped content
  - `220` — `word_diff_spans` inline word-level diffs (reuses Neogit's
    `lib.diff_highlights.word_diff_spans` helper directly)

## Caveats

* The right pane reads the worktree file, not the index. For unstaged hunks
  (the typical pre-commit review) those are identical. For hunks shown under
  *Staged Changes* where the worktree has diverged from the staged version,
  the right pane reflects the worktree.
* `scrollbind` syncs by line count, not by mapping. On deletion-heavy hunks
  the panes will visually drift in the deletion regions. Cursor sync (which
  uses the precomputed map) still lands on the correct line in both panes.
* No public Neogit API is used — everything goes through internal modules
  (`neogit.buffers.status`, `neogit.lib.git`, `neogit.lib.diff_highlights`).
  Breakage on a Neogit upgrade is possible.
