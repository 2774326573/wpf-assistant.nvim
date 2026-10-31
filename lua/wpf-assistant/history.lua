-- WPF Assistant - 历史/偏好存储
-- 记录最近执行的任务（可按项目根分组）以及每个项目的少量偏好（启动项目、构建目标、配置）。

local M = {}

local state_path = vim.fn.stdpath("state") .. "/wpf-assistant.json"
local cache = nil

local function key(root)
  root = vim.fs.normalize(root or vim.fn.getcwd())
  if vim.fn.has("win32") == 1 then
    root = root:lower()
  end
  return root
end

local function load()
  if cache then
    return cache
  end
  cache = { projects = {} }
  local handle = io.open(state_path, "rb")
  if handle then
    local content = handle:read("*a")
    handle:close()
    if content and content ~= "" then
      local ok, decoded = pcall(vim.json.decode, content)
      if ok and type(decoded) == "table" and type(decoded.projects) == "table" then
        cache = decoded
      end
    end
  end
  return cache
end

local function save()
  local data = load()
  local ok, encoded = pcall(vim.json.encode, data)
  if not ok then
    return false
  end
  local dir = vim.fs.dirname(state_path)
  if dir and not vim.uv.fs_stat(dir) then
    pcall(vim.fn.mkdir, dir, "p")
  end
  local handle = io.open(state_path, "wb")
  if not handle then
    return false
  end
  handle:write(encoded)
  handle:close()
  return true
end

local function project_entry(root, create)
  local data = load()
  local k = key(root)
  local entry = data.projects[k]
  if not entry and create then
    entry = { history = {}, prefs = {} }
    data.projects[k] = entry
  end
  return entry
end

--- @return string
function M.state_path()
  return state_path
end

--- 记录一次任务
--- @param entry { root: string, title: string, args: string[], kind?: string, configuration?: string, target?: string }
function M.add(entry)
  if type(entry) ~= "table" or type(entry.args) ~= "table" then
    return
  end
  local project = project_entry(entry.root or vim.fn.getcwd(), true)
  local limit = require("wpf-assistant.config").get_value("history.limit", 20)
  local record = {
    title = entry.title or table.concat(entry.args, " "),
    args = entry.args,
    kind = entry.kind,
    configuration = entry.configuration,
    target = entry.target,
    root = entry.root,
    time = os.time(),
  }
  table.insert(project.history, 1, record)
  while #project.history > limit do
    table.remove(project.history)
  end
  save()
end

--- @return table[]
function M.list(root)
  local entry = project_entry(root or vim.fn.getcwd(), false)
  return entry and entry.history or {}
end

function M.clear(root)
  local entry = project_entry(root or vim.fn.getcwd(), false)
  if entry then
    entry.history = {}
    save()
  end
end

function M.get_pref(root, name, fallback)
  local entry = project_entry(root or vim.fn.getcwd(), false)
  if not entry or type(entry.prefs) ~= "table" then
    return fallback
  end
  local value = entry.prefs[name]
  if value == nil or value == vim.NIL then
    return fallback
  end
  return value
end

function M.set_pref(root, name, value)
  local entry = project_entry(root or vim.fn.getcwd(), true)
  entry.prefs = entry.prefs or {}
  entry.prefs[name] = value
  save()
  return value
end

--- 供 :WpfDoctor 展示
function M.summary()
  local data = load()
  local count = vim.tbl_count(data.projects or {})
  return { path = state_path, projects = count, cached = cache ~= nil }
end

return M
