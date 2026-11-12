# search&replace.nvim

Project-wide, occurrence-by-occurrence search and replace with Vim regex and
`:substitute` semantics in Telescope. The preview and edits use the same native
Neovim substitution operation.

## Requirements

- Neovim 0.10+
- [telescope.nvim](https://github.com/nvim-telescope/telescope.nvim)
- [editable-telescope.nvim](https://github.com/foxinio/editable-telescope.nvim),
  with `editable_picker`, strict `args.split`, `args.format` and
  `args.normalize_root`. Opening the picker reports a clear error when
  editable-telescope is missing or too old.
- `rg` for ignore-aware file discovery only (a custom command may replace it)

## Setup

Install `foxinio/editable-telescope.nvim` as a dependency alongside Telescope.
For lazy.nvim, add both to this plugin's `dependencies` list:

```lua
dependencies = {
  "nvim-telescope/telescope.nvim",
  "foxinio/editable-telescope.nvim",
},
```

Both dependencies must be on the runtime path before opening this picker.
The `editable` Telescope extension loads automatically when first used; its
built-in pickers and global configuration are left unchanged.

```lua
require("search_replace").setup({
  search = {
    debounce = 100,
    max_results = 5000, -- picker display only; replace-all still uses every match
    hidden = false,
    ignored = false,
    globs = {},
    args = {}, -- additional file-discovery arguments, e.g. { "-t", "lua" }
    -- command = { "my-file-lister" }, -- newline-delimited output
  },
  preview = { context = 3 },
  mappings = {
    i = {
      replace_current = "<CR>",
      toggle_selection = "<Tab>",
      replace_selected_or_all = "<C-R>",
      change_root = "<C-s>", -- insert and normal mode
      edit_search_args = "<C-a>", -- insert and normal mode
    },
  },
})
```

Open with `:SearchReplace [cwd]`, `require("search_replace").open({ cwd = ... })`,
or after `require("telescope").load_extension("search_replace")`:

```vim
:Telescope search_replace
```

Press `<C-s>` to edit the search root (with directory completion), or `<C-a>`
to edit `rg` file-discovery flags. Both close the picker, open `vim.ui.input`,
and reopen with your search/replacement prompt intact. Canceling preserves the
settings. Changing settings clears selections and discovers files again. The
root and additional flags appear in the title; settings last for this session.

For example, enter `-g '*.lua' -g '!vendor/**' --hidden` to include Lua files,
skip the vendor directory, and include hidden files. Quoting and backslash
escapes group arguments; no shell commands or expansions run.
Ripgrep's precedence rules apply: positive globs can include files normally
excluded by hidden-file or ignore rules.

Supported flags are `-g`/`--glob`, `--iglob`, `--hidden`, `--no-hidden`,
`--no-ignore`, `--ignore`, `-t`/`--type`, `-T`/`--type-not`, `-L`/`--follow`,
`--no-follow`, `--max-depth`, and `--max-filesize`. Long value options also accept
`--option=value`. Inverted globs exclude files or directories. Unsupported flags
and invalid arguments appear in the preview with no search results; press
`<C-a>` to correct them. Content-search flags are unavailable because Neovim,
rather than `rg`, performs matching. Custom discovery commands support root
editing but cannot use the argument editor (clear its input to dismiss the error).

Per-picker search settings override setup defaults without changing other pickers:

```lua
require("search_replace").open({
  cwd = "~/project",
  search = { globs = {}, args = { "-g", "*.lua", "-g", "!vendor/**" } },
})
```

List overrides replace defaults. Additional arguments follow the existing
`hidden`, `ignored`, and `globs` settings; clearing the editor removes only the
additional arguments.

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
  changes, override disk contents for discovered files. Excluded files and new
  files absent from discovery are not searched, even if open in a buffer.
- Bulk operations are planned before editing, reject overlap, validate original
  lines, and apply from later positions to earlier positions. Edits in each
  buffer are joined into one undo block where Neovim permits it.
- Invalid patterns appear in the picker. Stale occurrences are skipped and the
  search refreshes. Search generations cancel and discard obsolete work.
- Binary disk files are ignored. Multiline patterns (literal newlines or `\_`
  atoms) are rejected in this release. Replacement `\r` may create lines.

Run domain tests with `make test`, discovery tests with `make integration`, and
Telescope UI checks with `make smoke` (Telescope and Plenary in the standard lazy
data directory). Tests also load editable-telescope from that directory; set
`EDITABLE_TELESCOPE_PATH` to test against a different checkout, for example:

```sh
EDITABLE_TELESCOPE_PATH=../editable-telescope.nvim make test integration smoke
```

## TODO

- `i` and `I` substitute flags
- Separate search-pattern and replacement histories
- Empty-pattern reuse
- Previous-replacement reuse
- Safe, non-mutating `\=` replacement expressions
- Multiline patterns
- Combined preview for multiple selected entries
