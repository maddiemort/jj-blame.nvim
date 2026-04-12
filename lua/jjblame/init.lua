local jj = require("jjblame.jj")
local utils = require("jjblame.utils")
local M = {}

---@alias file_path string
---@alias change_id string
---@alias commit_id string

---@type table<string, string>
local TEMPLATE_ALIASES = {
    ['jjblame_default_template()'] = table.concat {
        '"  " ++ separate(" • ", ',
            'jjblame_author(), ',
            'jjblame_author_date(), ',
            'jjblame_change_id(), ',
            'jjblame_description(),',
        ')',
    },
    ['jjblame_author()'] = 'commit.author().name()',
    ['jjblame_author_date()'] = 'format_timestamp(commit.author().timestamp())',
    ['jjblame_committer()'] = 'commit.committer().name()',
    ['jjblame_committer_date()'] = 'format_timestamp(commit.committer().timestamp())',
    ['jjblame_change_id()'] = 'commit.change_id().short(7)',
    ['jjblame_commit_id()'] = 'commit.commit_id().short(7)',
    ['jjblame_description()'] = 'coalesce(commit.description().first_line(), "(no description set)")',
}

---@type integer
local NAMESPACE_ID = vim.api.nvim_create_namespace("jj-blame-virtual-text")

---@type PositionInfo
local last_position = {
    file_path = nil,
    line = -1,
    is_on_same_line = false,
}

---@type table<change_id, ChangeInfo>
local changes = {}

---@class ChangeInfo
---@field change_id string
---@field commit_id string
---@field committer_timestamp number
---@field formatted string

---@type table<file_path, boolean>
local files_data_loading = {}

---@type table<file_path, FileInfo>
local files_data = {}

---@class FileInfo
---@field lines table<number, change_id>
---@field jj_repo_path string?

---@type boolean
local need_update_after_horizontal_move = false

---@type string?
local current_info_text

local function clear_virtual_text()
    vim.api.nvim_buf_del_extmark(0, NAMESPACE_ID, 1)
end

-- A luv timer object. Used exclusively for debouncing in `debounce`.
local debounce_timer = nil

-- Debounces `func` by `delay` milliseconds.
-- **IMPORTANT:** This refers to a single timer object (`debounce_timer`) for the debounce; beware!
---@param func function the function which will be wrapped
---@param delay integer time in milliseconds
---@return function debounced_func the debounced function which you can execute
local function debounce(func, delay)
    return function(...)
        local args = { ... }
        if debounce_timer then
            debounce_timer:stop()
            debounce_timer = nil
        end

        debounce_timer = vim.defer_fn(function()
            func(unpack(args))
            debounce_timer = nil
        end, delay)
    end
end

---Process the raw output of a `jj file annotate` command (`annotation_lines`) for the file at path
---`file_path`, and update both `changes` and `files_info` with data parsed from the output.
---
---@param file_path file_path
---@param annotation_lines string[]
local function process_annotations(file_path, annotation_lines)
    ---@type table<change_id, ChangeInfo>
    local seen_changes = {}

    ---@type table<number, change_id>
    local lines = {}

    ---@type number?
    local current_line = nil

    for _, line in ipairs(annotation_lines) do
        if line:match("^line_number ") then
            local line_number_str = line:gsub("^line_number ", "")
            current_line = tonumber(line_number_str)
        elseif current_line then
            if line:match("^change_id ") then
                local change_id = line:gsub("^change_id ", "")
                -- Record the change ID for this line.
                lines[current_line] = change_id
                if seen_changes[change_id] then
                    -- We already have the info for this change, so we'll skip processing lines
                    -- until we see the next line number.
                    current_line = nil
                else
                    -- We don't have the info for this change, so prepare an empty change info table
                    -- that we can put the info from the next few lines into.
                    seen_changes[change_id] = {
                        change_id = change_id,
                        commit_id = "",
                        committer_timestamp = 0,
                        formatted = "",
                    }
                end
            elseif line:match("^commit_id ") then
                -- We have a current_line, so we need to read the info for this change.
                local change_id = lines[current_line]
                seen_changes[change_id].commit_id = line:gsub("^commit_id ", "")
            elseif line:match("^committer_timestamp ") then
                -- We have a current_line, so we need to read the info for this change.
                local timestamp_str = line:gsub("^committer_timestamp ", "")
                local timestamp = tonumber(timestamp_str)
                if timestamp then
                    local change_id = lines[current_line]
                    seen_changes[change_id].committer_timestamp = timestamp
                end
            elseif line:match("^formatted ") then
                -- We have a current_line, so we need to read the info for this change.
                local change_id = lines[current_line]
                seen_changes[change_id].formatted = line:gsub("^formatted ", "")
            end
        end
    end

    -- Update the main table of changes, replacing the old or nonexistent info for any change IDs
    -- we saw in this annotation output with the newly parsed info.
    changes = vim.tbl_deep_extend("force", changes, seen_changes)

    -- Update the data for this file (or create a new one if it doesn't exist).
    local file_data = files_data[file_path]
    if file_data then
        file_data.lines = lines
    else
        files_data[file_path] = {
            lines = lines,
            jj_repo_path = nil,
        }
    end
end

---Load Jujutsu file annotations for the current file and set them into `files_data`, calling
---`callback` once complete.
---
---If the current file is empty, the file path or buftype can't be determined, the filetype is in
---the ignored filetypes list, or a command to load the data for this file is already running, then
---the file annotations will not be updated and the callback will not be called.
---
---@param callback fun()?
local function load_annotations(callback)
    local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
    if #lines == 0 then
        return
    end

    local file_path = vim.api.nvim_buf_get_name(0)
    if file_path == "" then
        return
    end

    local buftype = vim.api.nvim_get_option_value("bt", { buf = 0 })
    if buftype ~= "" then
        return
    end

    local filetype = vim.api.nvim_get_option_value("ft", { buf = 0 })
    if vim.tbl_contains(vim.g.jjblame_ignored_filetypes, filetype) then
        return
    end

    if files_data_loading[file_path] then
        return
    end

    files_data_loading[file_path] = true

    local command = "jj file annotate --color=never"
    for key, val in pairs(TEMPLATE_ALIASES) do
        command = command
            .. ' --config '
            .. vim.fn.shellescape(
                'template-aliases."'
                    .. key
                    .. '"="""'
                    .. val
                    .. '"""'
            )
    end
    command = command
        .. " --template " .. vim.fn.shellescape(
            'separate("\\n", '
            .. '"line_number " ++ line_number, '
            .. '"change_id " ++ commit.change_id(), '
            .. '"commit_id " ++ commit.commit_id(), '
            .. '"committer_timestamp " ++ commit.committer().timestamp().format("%s"), '
            .. '"formatted " ++ ' .. vim.g.jjblame_template .. ', '
            .. ') ++ "\\n"'
        ) .. " " .. vim.fn.shellescape(file_path)

    utils.start_job(command, {
        on_stdout = function(output)
            process_annotations(file_path, output)
            if callback then
                callback()
            end
        end,
        on_exit = function(_)
            files_data_loading[file_path] = nil
        end,
    })
end

---@param file_path file_path
---@param line_number number
---@return ChangeInfo?
local function get_line_info(file_path, line_number)
    local file_data = files_data[file_path]
    if not file_data then
        return nil
    end

    local change_id = file_data.lines[line_number]
    if not change_id then
        return nil
    end

    return changes[change_id]
end

---@param file_path file_path
---@param first_line number
---@param last_line number
---@return table<number, ChangeInfo>?
local function get_line_range_info(file_path, first_line, last_line)
    if not files_data[file_path] then
        return nil
    end

    ---@type table<number, ChangeInfo>
    local range_info = {}

    for line_number=first_line,last_line do
        local change_id = files_data[file_path].lines[line_number]
        if change_id and changes[change_id] then
            range_info[line_number] = changes[change_id]
        end
    end

    return range_info
end

---Return change information for the given line. If given a visual selection, return information
---for the most recently committed change that touched any of the lines.
---
---@param file_path file_path?
---@param first_line number
---@param last_line number?
---@return ChangeInfo?
local function get_info(file_path, first_line, last_line)
    if not file_path or not files_data[file_path] then
        return nil
    end

    if last_line and first_line ~= last_line then
        ---@type ChangeInfo?
        local latest_info = nil
        local info_range = get_line_range_info(file_path, first_line, last_line)

        if info_range then
            for _, info in ipairs(info_range) do
                if latest_info == nil or info.committer_timestamp > latest_info.committer_timestamp then
                    latest_info = info
                end
            end
        end

        return latest_info
    else
        return get_line_info(file_path, first_line)
    end
end

---@param info ChangeInfo?
---@param callback fun(blame_text: string?)
local function get_info_text(info, callback)
    if info then
        local truncated = utils.truncate_description(
            info.formatted,
            vim.g.jjblame_max_commit_description_length
        )
        callback(truncated)
    else
        callback(nil)
    end
end

---Updates `current_blame_text` and sets the virtual text if it should.
---
---@param info_text string?
local function update_info_text(info_text)
    clear_virtual_text()

    if not info_text then
        return
    end

    current_info_text = info_text

    local virt_text_disabled = vim.g.jjblame_virtual_text_enabled == false
        or vim.g.jjblame_virtual_text_enabled == 0

    if not virt_text_disabled then
        local virt_text_column = nil
        if vim.g.jjblame_virtual_text_column and utils.get_line_length() < vim.g.jjblame_virtual_text_column then
            virt_text_column = vim.g.jjblame_virtual_text_column
        end

        local options = {
            id = 1,
            virt_text = {
                { info_text, vim.g.jjblame_virtual_text_highlight },
            },
            virt_text_win_col = virt_text_column,
            hl_mode = "combine",
        }
        local user_options = vim.g.jjblame_set_extmark_options or {}

        if type(user_options) == "table" then
            utils.merge_map(user_options, options)
        elseif user_options then
            utils.log("jjblame_set_extmark_options should be a table")
        end

        local line = utils.get_line_number()
        vim.api.nvim_buf_set_extmark(0, NAMESPACE_ID, line - 1, 0, options)
    end

    if vim.g.jjblame_on_update then
        vim.g.jjblame_on_update()
    end
end

---@class PositionInfo
---@field file_path string?
---@field line integer
---@field is_on_same_line boolean

---@return PositionInfo
local function get_position_info()
    local file_path = utils.get_filepath()
    local line = utils.get_line_number()
    local is_on_same_line = last_position.file_path == file_path and last_position.line == line

    return {
        file_path = file_path,
        line = line,
        is_on_same_line = is_on_same_line,
    }
end

local function show_info()
    if not vim.g.jjblame_enabled then
        current_info_text = nil
        return
    end

    local position_info = get_position_info()

    local file_path = position_info.file_path
    local line = position_info.line

    if not file_path or not line then
        current_info_text = nil
        return
    end

    if not files_data[file_path] then
        load_annotations(show_info)
        return
    end
    if files_data[file_path].jj_repo_path == "" then
        return
    end
    if not files_data[file_path].lines then
        load_annotations(show_info)
        return
    end

    local info = get_info(file_path, line)
    get_info_text(info, function(info_text)
        update_info_text(info_text)
    end)
end

local function schedule_show_info_display()
    local position_info = get_position_info()

    if position_info.is_on_same_line then
        if not need_update_after_horizontal_move then
            return
        else
            need_update_after_horizontal_move = false
        end
    end

    if position_info.is_on_same_line then
        show_info()
    else
        clear_virtual_text()
        show_info()
    end

    last_position.file_path = position_info.file_path
    last_position.line = position_info.line
end

local function cleanup_file_data()
    -- TODO: Consider tracking the files that use each entry in changes, remove this file from all
    -- of those, and then remove the ones that were only referenced by this file.
    local file_path = vim.api.nvim_buf_get_name(0)
    files_data[file_path] = nil
end

local function clear_files_data()
    files_data = {}
end

local function clear_changes()
    changes = {}
end

local function handle_buf_enter()
    jj.get_repo_root(function(jj_repo_path)
        if jj_repo_path == "" then
            return
        end

        vim.schedule(function()
            show_info()
        end)
    end)
end

local function handle_text_changed()
    if get_position_info().is_on_same_line then
        need_update_after_horizontal_move = true
    end

    load_annotations(show_info)
end

local function handle_insert_leave()
    local timer = vim.loop.new_timer()
    if timer then
        timer:start(
            50,
            0,
            vim.schedule_wrap(function()
                handle_text_changed()
            end)
        )
    end
end

---Returns change ID for the current line or change ID for the latest change in visual selection
---@param callback fun(change_id: string)
---@param line1 number?
---@param line2 number?
M.get_change_id = function(callback, line1, line2)
    local file_path = utils.get_filepath()
    local line_number = line1 or utils.get_line_number()
    local info = get_info(file_path, line_number, line2)

    if info then
        callback(info.change_id)
    else
        load_annotations(function()
            local new_info = get_info(file_path, line_number, line2)
            callback(new_info and new_info.change_id or "")
        end)
    end
end

---Returns commit ID for the current line or commit ID for the latest commit in visual selection
---@param callback fun(commit_id: string)
---@param line1 number?
---@param line2 number?
M.get_commit_id = function(callback, line1, line2)
    local file_path = utils.get_filepath()
    local line_number = line1 or utils.get_line_number()
    local info = get_info(file_path, line_number, line2)

    if info then
        callback(info.commit_id)
    else
        load_annotations(function()
            local new_info = get_info(file_path, line_number, line2)
            callback(new_info and new_info.commit_id or "")
        end)
    end
end

M.open_commit_url = function()
    M.get_commit_id(function(commit_id)
        jj.open_commit_in_browser(commit_id)
    end)
end

-- See :h nvim_create_user_command for more information.
---@class CommandArgs
---@field line1 number
---@field line2 number

---@param args CommandArgs
M.open_file_url = function(args)
    local file_path = utils.get_filepath()
    if file_path == nil then
        return
    end

    ---@param commit_id commit_id
    local callback = function(commit_id)
        jj.open_file_in_browser(file_path, commit_id, args.line1, args.line2)
    end

    M.get_commit_id(callback, args.line1, args.line2)
end

---@return string?
M.get_current_blame_text = function()
    return current_info_text
end

---@return boolean
M.is_blame_text_available = function()
    return current_info_text ~= nil and current_info_text ~= ""
end

M.copy_change_id_to_clipboard = function()
    M.get_change_id(function(change_id)
        utils.copy_to_clipboard(change_id)
    end)
end

M.copy_commit_id_to_clipboard = function()
    M.get_commit_id(function(commit_id)
        utils.copy_to_clipboard(commit_id)
    end)
end

---@param args CommandArgs
M.copy_file_url_to_clipboard = function(args)
    local file_path = utils.get_filepath()
    if file_path == nil then
        return
    end

    ---@param commit_id commit_id
    local callback = function(commit_id)
        jj.get_file_url(file_path, commit_id, args.line1, args.line2, function(url)
            utils.copy_to_clipboard(url)
        end)
    end

    M.get_commit_id(callback, args.line1, args.line2)
end

M.copy_commit_url_to_clipboard = function()
    M.get_commit_id(function(commit_id)
        jj.get_remote_url(function(remote_url)
            local commit_url = jj.get_commit_url(commit_id, remote_url)
            utils.copy_to_clipboard(commit_url)
        end)
    end)
end

M.copy_pr_url_to_clipboard = function()
    M.get_commit_id(function(commit_id)
        local cmd = string.format('gh pr list --search "%s" --state merged --limit 1 --json url -q ".[0].url"', commit_id)
        utils.start_job(cmd, {
            on_stdout = function(data)
                if data and data[1] and data[1] ~= "" then
                    utils.copy_to_clipboard(data[1])
                    utils.log("PR URL copied to clipboard")
                else
                    utils.log("No PR found for commit " .. commit_id)
                end
            end,
            on_exit = function(code)
                if code ~= 0 then
                    utils.log("Failed to find PR (is gh CLI installed?)")
                end
            end
        })
    end)
end

local function clear_all_extmarks()
    local buffers = vim.api.nvim_list_bufs()

    for _, buffer_handle in ipairs(buffers) do
        vim.api.nvim_buf_del_extmark(buffer_handle, NAMESPACE_ID, 1)
    end
end

-- Validates the `parameter_name` against `available_values`. Returns an error message
-- if `parameter_name` doesn't match `available_values`.
--
---@param parameter_name string
---@param available_values string[]
---@return string?
local function validate_enum_parameter(parameter_name, available_values)
    local current_value = vim.g[parameter_name]

    if not vim.tbl_contains(available_values, current_value) then
        return string.format(
            "Invalid value for `%s`: %s. Available values are %s",
            parameter_name,
            current_value,
            vim.inspect(available_values)
        )
    end
end

-- Verifies the debounce configuration and displays an error message if it is invalid.
-- Returns `true` if the configuration is valid, `false` otherwise.
--
---@return boolean
local function verify_debounce_configuration()
    local error_message = validate_enum_parameter("jjblame_schedule_event", { "CursorMoved", "CursorHold" })
        or validate_enum_parameter("jjblame_clear_event", { "CursorMovedI", "CursorHoldI" })

    if type(vim.g.jjblame_delay) ~= "number" or vim.g.jjblame_delay < 0 then
        error_message =
            string.format("Invald value for `jjblame_delay`: %s. It should be a positive number", vim.g.jjblame_delay)
    end

    if error_message ~= nil then
        vim.notify(error_message, vim.log.levels.ERROR, {})
    end

    return error_message == nil
end

---@type function
local function maybe_clear_virtual_text_and_schedule_info_display()
    local position_info = get_position_info()

    if not position_info.is_on_same_line and not need_update_after_horizontal_move then
        clear_virtual_text()
    end

    debounce(schedule_show_info_display, math.floor(vim.g.jjblame_delay))()
end

local function set_autocmds()
    local autocmd = vim.api.nvim_create_autocmd
    local group = vim.api.nvim_create_augroup("jjblame", { clear = true })

    if not verify_debounce_configuration() then
        return
    end

    ---@type "CursorMoved" | "CursorHold"
    local event_schedule = vim.g.jjblame_schedule_event
    ---@type "CursorMovedI" | "CursorHoldI"
    local event_clear = vim.g.jjblame_clear_event

    ---@type function
    local func_schedule = schedule_show_info_display
    if event_schedule == "CursorMoved" then
        func_schedule = maybe_clear_virtual_text_and_schedule_info_display
    end

    ---@type function
    local func_clear = clear_virtual_text
    if event_clear == "CursorMovedI" then
        func_clear = debounce(clear_virtual_text, math.floor(vim.g.jjblame_delay))
    end

    autocmd(event_schedule, { callback = func_schedule, group = group })
    autocmd(event_clear, { callback = func_clear, group = group })
    autocmd("InsertEnter", { callback = clear_virtual_text, group = group })
    autocmd("TextChanged", { callback = handle_text_changed, group = group })
    autocmd("BufWritePost", { callback = handle_text_changed, group = group })
    autocmd("FocusGained", { callback = handle_text_changed, group = group })
    autocmd("InsertLeave", { callback = handle_insert_leave, group = group })
    autocmd("BufEnter", { callback = handle_buf_enter, group = group })
    autocmd("BufDelete", { callback = cleanup_file_data, group = group })
end

M.disable = function(force)
    if not vim.g.jjblame_enabled and not force then
        return
    end

    vim.g.jjblame_enabled = false
    pcall(vim.api.nvim_del_augroup_by_name, "jjblame")
    clear_all_extmarks()
    clear_files_data()
    clear_changes()
    last_position = {
        file_path = nil,
        line = -1,
        is_on_same_line = false,
    }
    current_info_text = nil
end

M.enable = function()
    if vim.g.jjblame_enabled then
        return
    end

    vim.g.jjblame_enabled = true
    set_autocmds()
    show_info()
end

M.toggle = function()
    if vim.g.jjblame_enabled then
        M.disable()
    else
        M.enable()
    end
end

local create_cmds = function()
    local command = vim.api.nvim_create_user_command

    command("JJBlameToggle", M.toggle, {})
    command("JJBlameEnable", M.enable, {})
    command("JJBlameDisable", M.disable, {})
    command("JJBlameOpenCommitURL", M.open_commit_url, {})
    command("JJBlameOpenFileURL", M.open_file_url, { range = true })
    command("JJBlameCopyChangeID", M.copy_change_id_to_clipboard, {})
    command("JJBlameCopyCommitID", M.copy_commit_id_to_clipboard, {})
    command("JJBlameCopyCommitURL", M.copy_commit_url_to_clipboard, {})
    command("JJBlameCopyFileURL", M.copy_file_url_to_clipboard, { range = true })
    command("JJBlameCopyPRURL", M.copy_pr_url_to_clipboard, {})
end

---@param opts SetupOptions?
M.setup = function(opts)
    require("jjblame.config").setup(opts)
    create_cmds()
    if vim.g.jjblame_enabled == 1 or vim.g.jjblame_enabled == true then
        set_autocmds()
    else
        M.disable(true)
    end
end

return M
