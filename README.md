# `jj-blame.nvim`

A Jujutsu blame/annotation plugin for Neovim written in Lua. Adapted from
[`git-blame.nvim`][git-blame.nvim].

## Installation

### Using [`vim-plug`][vim-plug]

```vim
Plug 'maddiemort/jj-blame.nvim'
```

## Requirements

* `nvim` >= 0.5.0
* [`jj`][jj]

## Configuration

### Using Lua

You can use `setup` to configure the plugin in Lua. This is the recommended way if you're using Lua
for your configuration. Read the documentation below to learn more about specific options.

> [!NOTE]
> You don't have to call `setup` if you don't want to customize the default behavior.

```lua
require('jjblame').setup {
    enabled = false,
}
```

The following are the default options. See the [Template](#template) section for more information on
the template.

```lua
require('jjblame').setup {
    enabled = true,
    template = 'jjblame_default_template()',
    virtual_text_enabled = true,
    virtual_text_highlight = "Comment",
    virtual_text_column = nil,
    set_extmark_options = {},
    ignored_filetypes = {},
    delay = 250,
    schedule_event = "CursorMoved",
    clear_event = "CursorMovedI",
    on_update = nil,
    clipboard_register = "+",
    max_commit_description_length = 0,
    remote_domains = {
        ["git.sr.ht"] = "sourcehut",
        ["dev.azure.com"] = "azure",
        ["bitbucket.org"] = "bitbucket",
        ["codeberg.org"] = "forgejo"
    },
    remote_name = "origin",
}
```

### Using `lazy.nvim`

```lua
return {
    "maddiemort/jj-blame.nvim",
    -- Load the plugin at startup
    event = "VeryLazy",
    opts = {
        -- Your configuration goes here
        enabled = true,
    },
}
```

### Enabled

Enables `jj-blame.nvim` on Neovim startup. You can toggle blame messages on/off with the
`:JJBlameToggle` command.

Default: `1`

```vim
let g:jjblame_enabled = 0
```

### Template

The template for the blame message that will be shown. This is a [Jujutsu template
expression][jj-templates] that will be passed verbatim to the [`jj file annotate`][jj-file-annotate]
command.

> [!IMPORTANT]
> The configured template string must not contain newlines.

Default: `jjblame_default_template()`

You can use any of the following template aliases in your template, because `jj-blame.nvim` passes
them in `--config` args:

```toml
[template-aliases]
'jjblame_default_template()' = """
"  " ++ separate(" • ",
    jjblame_author(),
    jjblame_author_date(),
    jjblame_change_id(),
    jjblame_description(),
)
"""
'jjblame_author()' = 'commit.author().name()'
'jjblame_author_date()' = 'format_timestamp(commit.author().timestamp())'
'jjblame_committer()' = 'commit.committer().name()'
'jjblame_committer_date()' = 'format_timestamp(commit.committer().timestamp())'
'jjblame_change_id()' = 'commit.change_id().short(7)'
'jjblame_commit_id()' = 'commit.commit_id().short(7)'
'jjblame_description()' = 'coalesce(commit.description().first_line(), "(no description set)")'
```

Example:

```vim
let g:jjblame_message_template = =<< END
"  " ++ separate(
    " // ",
    jjblame_author(),
    jjblame_change_id(),
    jjblame_commit_id(),
    jjblame_description(),
)
END
```

### Virtual Text Enabled

If the blame message should be displayed as virtual text. You may want to disable this if you
display the blame message in your statusline instead.

Default: `1`

Example:

```vim
let g:jjblame_virtual_text_enabled = 0
```

### Virtual Text Highlight Group

The highlight group(s) for virtual text. If provided as a list, they will be applied in order from
lowest to highest priority.

Default: `Comment`

Example:

```vim
let g:jjblame_virtual_text_highlight = "Question"
```

### Start Virtual Text at Column

Have the blame message start at a given column instead of EOL. If the current line is longer than
the specified column value, the blame message will default to being displayed at EOL.

Default: `v:null`

Example:

```vim
let g:jjblame_virtual_text_column = 80
```

### `nvim_buf_set_extmark` Optional Parameters

`nvim_buf_set_extmark` is the function used for setting the virtual text. You can view an up-to-date
full list of options in the [Neovim documentation][nvim_buf_set_extmark].

**Warning**: overwriting `id` and `virt_text` will break the plugin behavior.

Example:

```vim
let g:jjblame_set_extmark_options = {
    \ 'priority': 7,
    \ }
```

### Ignore by Filetype

A list of filetypes for which Jujutsu blame information will not be displayed.

Default: `[]`

Example:

```vim
let g:jjblame_ignored_filetypes = ['lua', 'c']
```

### Visual Delay for Displaying the Blame Info

The delay in milliseconds after which the blame info will be displayed.

Note that this doesn't affect the performance of the plugin.

Default: `250`

Example:

```vim
let g:jjblame_delay = 1000 " 1 second
```

### Better Performance

If you are experiencing poor performance (e.g. in particularly large projects) you can use
`CursorHold` and `CursorHoldI` instead of the default `CursorMoved` and `CursorMovedI` autocommands
to limit the frequency of events being run.

- `g:jjblame_schedule_event` is used for scheduling events. See [`CursorMoved`][CursorMoved] and
  [`CursorHold`][CursorHold].
  - Default: `CursorMoved`
  - Options: `CursorMoved`, `CursorHold` 
- `g:jjblame_clear_event` is used for clearing virtual text. See [`CursorMovedI`][CursorMovedI] and
  [`CursorHoldI`][CursorHoldI].
  - Default: `CursorMovedI`
  - Options: `CursorMovedI`, `CursorHoldI`

### Configuring the Clipboard Register

By default the `:JJBlameCopyCommitID`, `:JJBlameCopyChangeID`, `:JJBlameCopyFileURL` and
`:JJBlameCopyCommitURL` commands use the `+` register. Set this value if you would like to use a
different register (such as `*`).

Default: `+`

```vim
let g:jjblame_clipboard_register = "*"
```

### Set Displayed Commit Description Length

The maximum length of the commit description shown in the blame message, or `0` to disable the
limit. If the commit description is longer than this value, it will be truncated.

Default: `0`

```vim
let g:jjblame_max_commit_description_length = 50
```

### Remote Forge Domains

A map of domain names to forge software. Set this so commit and file URLs are generated correctly
for your self-hosted instances.

Currently supported software:

- `github`
- `gitlab`
- `sourcehut`
- `forgejo`
- `azure`
- `bitbucket`

```lua
vim.g.jjblame_remote_domains = {
    "git.sr.ht" = "sourcehut"
}
```

### Multiple Remote Names

If your project tracks multiple remote repositories you can change remote name to one you want to
track.

Default: `origin`

```vim
let g:jjblame_remote_name = "upstream"
```

Tip: You can enable `.exrc` in your nvim config and set remote name per project.

## Commands

### Open the Commit URL in Browser

`:JJBlameOpenCommitURL` opens the commit URL of commit under the cursor. Tested to work with GitHub
and GitLab.

### Enable/Disable Jujutsu Blame Messages

* `:JJBlameToggle` toggles Jujutsu blame on/off
* `:JJBlameEnable` enables Jujutsu blame messages
* `:JJBlameDisable` disables Jujutsu blame messages

### Copy Change ID

`:JJBlameCopyChangeID` copies the change ID of the current line's revision into the system's
clipboard.

### Copy Commit ID

`:JJBlameCopyCommitID` copies the commit ID of the current line's commit into the system's
clipboard.

### Copy Commit URL

`:JJBlameCopyCommitURL` copies the commit URL of current line's commit into the system clipboard.

### Copy PR URL

`:JJBlameCopyPRURL` copies the pull request URL associated with the commit on the current line into
the system clipboard. This command requires the [GitHub CLI][github-cli] ([`gh`][gh]) to be
installed and authenticated.

### Open File URL in Browser

`:JJBlameOpenFileURL` opens a link to the select line(s) in the current file in the default browser.

### Copy File URL

`:JJBlameCopyFileURL` copies the file URL into the system clipboard.

## Statusline Integration

The plugin provides you with two functions which you can incorporate into your statusline of choice:

```lua
local jj_blame = require('jjblame')

-- Returns a boolean value indicating whether a blame message is available
jj_blame.is_blame_text_available()
-- Returns the blame message string
jj_blame.get_current_blame_text()
```

Here is an example of integrating with [`lualine.nvim`][lualine.nvim]:

```lua
vim.g.jjblame_virtual_text_enabled = 0

local jj_blame = require('jjblame')
require('lualine').setup {
    sections = {
        lualine_c = {
            { jj_blame.get_current_blame_text, cond = jj_blame.is_blame_text_available }
        }
    }
}
```

## Thanks To

* [`git-blame.nvim`][git-blame.nvim] for the original Git version of this plugin, and
  [`coc-git`][coc-git] and [`blamer.nvim`][blamer.nvim] in turn.
* [`entropitor`][entropitor] for beginning the [conversion of this plugin][entropitor-jj-blame.nvim]
  from Git to Jujutsu.
* [Everyone who contributed](https://github.com/f-person/git-blame.nvim/graphs/contributors) to the
  original plugin.

## Development

### Cutting a Release

This project uses [Conventional Commits][conventional-commits], and [`convco`][convco] is included
in the Nix devShell to assist with this.

The overall list of things that has to happen for each release is as follows:

- The commit that changes the version should use the message `release: v<version>`.
- That commit should include the updated `CHANGELOG.md`, generated with `convco changelog -u
  $(convco version --bump) > CHANGELOG.md`.
- That commit should be tagged with `v<version>`.
- The commit should be pushed to `main`, and the tag pushed as well.

[CursorHoldI]: https://neovim.io/doc/user/autocmd.html#CursorHoldI
[CursorHold]: https://neovim.io/doc/user/autocmd.html#CursorHold
[CursorMovedI]: https://neovim.io/doc/user/autocmd.html#CursorMovedI
[CursorMoved]: https://neovim.io/doc/user/autocmd.html#CursorMoved
[blamer.nvim]: https://github.com/APZelos/blamer.nvim
[coc-git]: https://github.com/neoclide/coc-git
[convco]: https://github.com/convco/convco
[conventional-commits]: https://www.conventionalcommits.org/en/v1.0.0/
[entropitor-jj-blame.nvim]: https://github.com/entropitor/jj-blame.nvim
[entropitor]: https://github.com/entropitor
[gh]: https://github.com/cli/cli
[git-blame.nvim]: https://github.com/f-person/git-blame.nvim
[github-cli]: https://cli.github.com
[jj-file-annotate]: https://www.jj-vcs.dev/latest/cli-reference/#jj-file-annotate
[jj-templates]: https://www.jj-vcs.dev/latest/templates/#templates
[jj]: https://github.com/jj-vcs/jj
[lualine.nvim]: https://github.com/nvim-lualine/lualine.nvim
[nvim_buf_set_extmark]: https://neovim.io/doc/user/api.html#nvim_buf_set_extmark()
[vim-plug]: https://github.com/junegunn/vim-plug
