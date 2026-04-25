local M = {}

local uv = vim.uv or vim.loop

local function path_exists(path)
  local stat = uv.fs_stat(path)
  return stat ~= nil
end

local function is_dir(path)
  local stat = uv.fs_stat(path)
  return stat ~= nil and stat.type == "directory"
end

local function dirname(path)
  return vim.fn.fnamemodify(path, ":h")
end

local function join(a, b)
  if a:sub(-1) == "/" then
    return a .. b
  end
  return a .. "/" .. b
end

local function mkdir_p(path)
  vim.fn.mkdir(path, "p")
end

local function walk_up_for_obsidian(start_dir)
  local dir = start_dir
  local prev = nil
  while dir and dir ~= prev do
    local candidate = join(dir, ".obsidian")
    if is_dir(candidate) then
      return dir
    end
    prev = dir
    dir = dirname(dir)
  end
  return nil
end

function M.to_posix(path)
  return (path:gsub("\\", "/"))
end

function M.find_for_buffer(bufnr)
  bufnr = bufnr or 0
  local name = vim.api.nvim_buf_get_name(bufnr)
  if name == nil or name == "" then
    return nil
  end
  local abs = vim.fn.fnamemodify(name, ":p")
  local dir = vim.fn.fnamemodify(abs, ":h")
  return walk_up_for_obsidian(dir)
end

function M.find_for_path(path)
  if not path or path == "" then
    return nil
  end
  local abs = vim.fn.fnamemodify(path, ":p")
  local dir = vim.fn.fnamemodify(abs, ":h")
  return walk_up_for_obsidian(dir)
end

function M.cwd_fallback()
  return vim.fn.getcwd()
end

function M.plugin_dir(vault_root)
  return join(join(vault_root, ".obsidian"), join("plugins", "side-note"))
end

function M.data_path(vault_root)
  return join(M.plugin_dir(vault_root), "data.json")
end

function M.default_settings()
  return {
    commentSortOrder = "position",
    showHighlights = true,
    markdownFolder = "side-note-comments",
    highlightColor = "#FFC800",
    highlightOpacity = 0.2,
    showResolvedComments = false,
    comments = {},
  }
end

function M.ensure_initialized(vault_root)
  local plugin_dir = M.plugin_dir(vault_root)
  if not is_dir(plugin_dir) then
    mkdir_p(plugin_dir)
  end
  local data_path = M.data_path(vault_root)
  if not path_exists(data_path) then
    local storage = require("sidenote.storage")
    storage.save(data_path, M.default_settings())
  end
  return data_path
end

function M.resolve_for_buffer(bufnr, opts)
  opts = opts or {}
  bufnr = bufnr or 0
  local vault = M.find_for_buffer(bufnr)
  if vault then
    return vault, false
  end
  if opts.create_on_miss then
    local fallback = M.cwd_fallback()
    M.ensure_initialized(fallback)
    return fallback, true
  end
  return nil, false
end

function M.relative_path(vault_root, abs_path)
  local v = M.to_posix(vault_root)
  local p = M.to_posix(vim.fn.fnamemodify(abs_path, ":p"))
  if v:sub(-1) ~= "/" then
    v = v .. "/"
  end
  if p:sub(1, #v) == v then
    return p:sub(#v + 1)
  end
  return p
end

return M
