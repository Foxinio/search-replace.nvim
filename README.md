# search&replace.nvim

Project-wide, occurrence-by-occurrence search and replace with Vim regex and
`:substitute` semantics in Telescope. The preview and edits use the same native
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
    max_results = 5000, -- picker display only; replace-all still uses every match
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
      replace_selected_or_all = "<C-R>",
    },
  },
})
```

Open with `:SearchReplace [cwd]`, `require("search_replace").open({ cwd = ... })`,
or after `require("telescope").load_extension("search_replace")`:

```vim
:Telescope search_replace
```

The normally editable prompt uses Vim-style delimiter syntax:

```vim
/pattern/replacement/g
#pattern#replacement#
```

Any single-byte, non-alphanumeric delimiter except `\`, `"`, and `|` works.
Escape a delimiter with `\`; that command-level escape is removed before the
pattern or replacement reaches Vim. The first delimiter starts live search, and
the second starts replacement preview, so `/foo/` is a valid empty replacement.
The closing delimiter is optional unless flags follow it. The only flag is `g`.

Each match, including several matches on one line, is a separate picker entry.
Without `g`, `<CR>` replaces only the current occurrence; with `g`, targeting any
occurrence replaces every match on its line. `<Tab>` toggles selection. `<C-R>`
replaces selected occurrences, or all current results when nothing is selected.
Buffers remain modified and are never automatically written.

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

## TODO

- `i` and `I` substitute flags
- Separate search-pattern and replacement histories
- Empty-pattern reuse
- Previous-replacement reuse
- Safe, non-mutating `\=` replacement expressions
- Multiline patterns
- Combined preview for multiple selected entries
