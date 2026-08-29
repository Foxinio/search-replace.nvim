# search-replace.nvim

Project-wide, occurrence-by-occurrence search and replace with Vim regex and
`:substitute` semantics in Telescope. Search and replacement stay visible in
one protected composite prompt; the preview and edits use the same native
Neovim substitution operation.

## Requirements

- Neovim 0.10+
- [telescope.nvim](https://github.com/nvim-telescope/telescope.nvim)
- `rg` for ignore-aware file discovery only (a custom command may replace it)

## Setup

```lua
require("search_replace").setup({
  search = {
    debounce = 100,
    hidden = false,
    ignored = false,
    globs = {},
    -- command = { "my-file-lister" }, -- newline-delimited output
  },
  preview = { context = 3 },
  replace = { auto_save = false },
  mappings = {
    i = {
      replace_current = "<CR>",
      toggle_selection = "<Tab>",
      replace_selected_or_all = "<C-r>",
    },
  },
})
```

Open with `:SearchReplace [cwd]`, `require("search_replace").open({ cwd = ... })`,
or after `require("telescope").load_extension("search_replace")`:

```vim
:Telescope search_replace
```

The prompt is `Search: pattern  │  replacement`. Arrow keys cross the protected
separator in one step. `<CR>` replaces only the current occurrence and keeps the
picker open. `<Tab>` toggles selection. `<C-r>` replaces selected occurrences,
or every current occurrence when nothing is selected. Buffers remain modified
and are never automatically written.

## Behavior

- Matching uses `matchstrpos()` and replacement uses `substitute()` with the
  same Vim pattern. Effective `\zs`/`\ze` ranges, captures, magic/case modifiers,
  UTF-8 byte positions, and zero-width matches therefore retain Vim semantics.
- `rg --files --null` only discovers files. Loaded buffers, including unsaved
  changes, override disk contents.
- Bulk operations are planned before editing, reject overlap, validate original
  lines, and apply from later positions to earlier positions. Edits in each
  buffer are joined into one undo block where Neovim permits it.
- Invalid patterns appear in the picker. Stale occurrences are skipped and the
  search refreshes. Search generations cancel and discard obsolete work.
- Binary disk files are ignored. Multiline patterns (literal newlines or `\_`
  atoms) are rejected in this release. Replacement `\r` may create lines.

Run domain tests with `make test`. Telescope UI behavior is best checked using
the acceptance workflow in the project specification.
