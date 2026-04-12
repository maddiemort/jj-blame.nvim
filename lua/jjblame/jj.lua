local utils = require("jjblame.utils")
local M = {}

---@param url string
---@return string
local function get_http_domain(url)
    local domain = string.match(url, "https%:%/%/.*%@([^/]*)%/.*") or string.match(url, "https%:%/%/([^/]*)%/.*")
    return domain and domain:lower()
end

---@param commit_id string
---@param repo_url string
---@return string
local function get_commit_path(commit_id, repo_url)
    local domain = get_http_domain(repo_url)

    local forge = vim.g.jjblame_remote_domains[domain]
    if forge == "bitbucket" then
        return "/commits/" .. commit_id
    end

    return "/commit/" .. commit_id
end

---@param url string
---@return string
local function get_azure_url(url)
    -- HTTPS has a different URL format
    local org, project, repo = string.match(url, "(.*)/(.*)/_git/(.*)")
    if org and project and repo then
        return "https://dev.azure.com/" .. org .. "/" .. project .. "/_git/" .. repo
    end

    org, project, repo = string.match(url, "(.*)/(.*)/(.*)")
    if org and project and repo then
        return "https://dev.azure.com/" .. org .. "/" .. project .. "/_git/" .. repo
    end

    return url
end

---@param remote_url string
---@return string
local function get_repo_url(remote_url)
    remote_url = string.gsub(remote_url, "/$", "")

    local domain, path = string.match(remote_url, ".*git%@(.*)%:(.*)%.git")
    if domain and path then
        return "https://" .. domain .. "/" .. path
    end

    local url = string.match(remote_url, ".*git@*ssh.dev.azure.com:v[0-9]/(.*)")
    if url then
        return get_azure_url(url)
    end

    local https_url = string.match(remote_url, ".*@dev.azure.com/(.*)")
    if https_url then
        return get_azure_url(https_url)
    end

    url = string.match(remote_url, ".*git%@(.*)%.git")
    if url then
        return "https://" .. url
    end

    https_url = string.match(remote_url, "(https%:%/%/.*)%.git")
    if https_url then
        return https_url
    end

    domain, path = string.match(remote_url, ".*git%@(.*)%:(.*)")
    if domain and path then
        return "https://" .. domain .. "/" .. path
    end

    url = string.match(remote_url, ".*git%@(.*)")
    if url then
        return "https://" .. url
    end

    https_url = string.match(remote_url, "(https%:%/%/.*)")
    if https_url then
        return https_url
    end

    return remote_url
end

---URL-encode a given string URI.
---@param url string
---@return string
local function url_encode(url)
    -- only includes opening/closing square bracket for now,
    -- more can be added as needed later
    local pattern = "[][]"
    local encoded, _ = string.gsub(url, pattern, function(c)
        return string.format("%%%02X", string.byte(c))
    end)
    return encoded
end

---@param remote_url string
---@param commit_id commit_id
---@param filepath string
---@param line1 number?
---@param line2 number?
---@return string
local function get_file_url(remote_url, commit_id, filepath, line1, line2)
    local repo_url = get_repo_url(remote_url)
    local domain = get_http_domain(repo_url)

    local forge = vim.g.jjblame_remote_domains[domain]

    local file_path = url_encode("/blob/" .. commit_id .. "/" .. filepath)
    if forge == "sourcehut" then
        file_path = url_encode("/tree/" .. commit_id .. "/" .. filepath)
    end
    if forge == "forgejo" then
        file_path = "/src/" .. "commit" .. "/" .. commit_id .. "/" .. filepath
    end
    if forge == "bitbucket" then
        file_path = "/src/" .. commit_id .. "/" .. filepath
    end
    if forge == "azure" then
        -- Can't use ref here if it's a commit ID
        file_path = "?path=%2F" .. filepath
    end

    if line1 == nil then
        return repo_url .. file_path
    elseif line2 == nil or line1 == line2 then
        if forge == "azure" then
            return repo_url
                .. file_path
                .. "&line="
                .. line1
                .. "&lineEnd="
                .. line1 + 1
                .. "&lineStartColumn=1&lineEndColumn=1"
        end

        if forge == "bitbucket" then
            return repo_url .. file_path .. "#lines-" .. line1
        end

        return repo_url .. file_path .. "#L" .. line1
    else
        if forge == "sourcehut" then
            return repo_url .. file_path .. "#L" .. line1 .. "-" .. line2
        end

        if forge == "azure" then
            return repo_url
                .. file_path
                .. "&line="
                .. line1
                .. "&lineEnd="
                .. line2 + 1
                .. "&lineStartColumn=1&lineEndColumn=1"
        end

        if forge == "bitbucket" then
            return repo_url .. file_path .. "#lines-" .. line1 .. ":" .. line2
        end

        return repo_url .. file_path .. "#L" .. line1 .. "-L" .. line2
    end
end

---@param filepath string
---@param commit_id string
---@param line1 number?
---@param line2 number?
---@param callback fun(url: string)
function M.get_file_url(filepath, commit_id, line1, line2, callback)
    M.get_repo_root(function(root)
        -- if outside a repository, return the filepath
        -- so we can still copy the path or open the file
        if root == "" then
            callback(filepath)
            return
        end

        local relative_filepath = string.sub(filepath, #root + 2)

        M.get_remote_url(function(remote_url)
            local url = get_file_url(remote_url, commit_id, relative_filepath, line1, line2)
            callback(url)
        end)
    end)
end

---@param commit_id string
---@param remote_url string
---@return string
function M.get_commit_url(commit_id, remote_url)
    local repo_url = get_repo_url(remote_url)
    local commit_path = get_commit_path(commit_id, repo_url)

    return repo_url .. commit_path
end

---@param filepath string
---@param commit_id string
---@param line1 number?
---@param line2 number?
function M.open_file_in_browser(filepath, commit_id, line1, line2)
    M.get_file_url(filepath, commit_id, line1, line2, function(url)
        utils.launch_url(url)
    end)
end

---@param commit_id string
function M.open_commit_in_browser(commit_id)
    M.get_remote_url(function(remote_url)
        local commit_url = M.get_commit_url(commit_id, remote_url)
        utils.launch_url(commit_url)
    end)
end

---@param callback fun(url: string)
function M.get_remote_url(callback)
    if not utils.get_filepath() then
        return
    end
    local remote_name = vim.g.jjblame_remote_name
    if remote_name == nil then
        remote_name = "origin"
    end
    local remote_url_command = utils.make_local_command("jj git remote list")

    utils.start_job(remote_url_command, {
        on_stdout = function(lines)
            for _, line in ipairs(lines) do
                if line:match("^" .. remote_name .. " ") then
                    local url = line:gsub("^" .. remote_name .. " ", "")
                    callback(url)
                    return
                end
            end
            callback("")
        end,
    })
end

---@param callback fun(repo_root: string)
function M.get_repo_root(callback)
    if not utils.get_filepath() then
        return
    end
    local command = utils.make_local_command("jj workspace root")

    utils.start_job(command, {
        on_stdout = function(data)
            callback(data[1])
        end,
    })
end

return M
