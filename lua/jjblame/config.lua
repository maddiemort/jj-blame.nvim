local M = {}

---@class SetupOptions
---@field enabled boolean?
---@field template string?
---@field virtual_text_enabled boolean?
---@field virtual_text_highlight (string|string[])? The highlight group or list of highlight groups (lowest to highest priority) to use for the virtual text
---@field virtual_text_column number? The column on which to start displaying virtual text
---@field set_extmark_options table? @see vim.api.nvim_buf_set_extmark() to check what you can pass here
---@field ignored_filetypes string[]?
---@field delay number? Visual delay for displaying virtual text
---@field schedule_event string?
---@field clear_event string?
---@field on_update function? Callback when the info text is updated
---@field clipboard_register string? The clipboard register to use when copying commit/change IDs or file URLs
---@field max_commit_description_length number? The maximum allowable length for the displayed commit description; defaults to 0 (no limit)
---@field remote_domains table<string, string>?
---@field remote_name string?

---@type SetupOptions
M.default_opts = {
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

---@param opts SetupOptions?
M.setup = function(opts)
    opts = opts or {}

    local global_var_opts = {}
    for k, _ in pairs(M.default_opts) do
        global_var_opts[k] = vim.g["jjblame_" .. k]
    end

    opts = vim.tbl_deep_extend("force", M.default_opts, global_var_opts, opts)
    for k, v in pairs(opts) do
        vim.g["jjblame_" .. k] = v
    end
end

return M
