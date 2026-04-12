# Changelog

## v0.1.0 (2026-04-12)

### Features

* add support for copying change IDs to the clipboard
([6251937](https://github.com/maddiemort/jj-blame.nvim/commit/6251937b624ad6319cfdb5a0f3ed40e50fc31ccc))
* set default virtual text highlight mode to combine, simplify default
highlight groups
([26c39f3](https://github.com/maddiemort/jj-blame.nvim/commit/26c39f388c3437bb505ccf0f3802b9970559bd18))
* allow for multiple virtual text highlight groups
([44f7af8](https://github.com/maddiemort/jj-blame.nvim/commit/44f7af86ba673ebfbf8b735ed17df1b03d16541b))
* fully convert original plugin from Git to Jujutsu
([7e8ea4b](https://github.com/maddiemort/jj-blame.nvim/commit/7e8ea4b12d1257c72d5b5db42637ccfc12d73085))
* replace git commands with jujutsu commands
([f2b4282](https://github.com/maddiemort/jj-blame.nvim/commit/f2b4282ef749d39c678face967f9cdffa0bdd1f3))

### Fixes

* correctly parse git remote URLs from Jujutsu's output
([4cbba20](https://github.com/maddiemort/jj-blame.nvim/commit/4cbba20abc69aa19c8fed2b6635b5ce9e8f135ca))
* show info immediately when enabling blame
([ac89282](https://github.com/maddiemort/jj-blame.nvim/commit/ac8928274263a494eafd796a28137e38743161da))
* allow remote name to be set from Lua
([033da6e](https://github.com/maddiemort/jj-blame.nvim/commit/033da6e12a7cdb2a826e0033f93d276dac496afe))
* clear the current info text if there's no file, no buftype, etc.
([33e447e](https://github.com/maddiemort/jj-blame.nvim/commit/33e447e8d00db2e32d5b322c8d8fa8120910d5ea))
* handle possibly changed text on BufWritePost and FocusGained events
([fbeeb9d](https://github.com/maddiemort/jj-blame.nvim/commit/fbeeb9d6d1f7f08999f1b5713f9475d5a9028627))
