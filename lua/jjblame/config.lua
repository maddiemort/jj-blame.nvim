local M = {}

---@type SetupOptions
M.default_opts = {
    enabled = true,
    template = 'jjblame_default_template()',
    highlight_group = "Comment",
    set_extmark_options = {},
    display_virtual_text = true,
    ignored_filetypes = {},
    delay = 250,
    virtual_text_column = nil,
    use_blame_commit_file_urls = false,
    schedule_event = "CursorMoved",
    clear_event = "CursorMovedI",
    clipboard_register = "+",
    max_commit_description_length = 0,
    remote_domains = {
        ["git.sr.ht"] = "sourcehut",
        ["dev.azure.com"] = "azure",
        ["bitbucket.org"] = "bitbucket",
        ["codeberg.org"] = "forgejo"
    }
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
