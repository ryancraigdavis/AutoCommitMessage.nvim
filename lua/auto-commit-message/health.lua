-- Health check for AutoCommitMessage.nvim
-- Run with :checkhealth auto-commit-message

local M = {}

local health = vim.health
local start = health.start
local ok = health.ok
local warn = health.warn
local err = health.error
local info = health.info or health.ok

--- Run an async function synchronously for the health check.
--- Returns whether it completed in time, whether it ran without error, and the
--- result (or error message).
---@param fn function Async function to run (may yield via plenary.async)
---@param timeout number|nil Milliseconds to wait (default 8000)
---@return boolean completed, boolean call_ok, any result
local function run_async(fn, timeout)
  local has_async, async = pcall(require, "plenary.async")
  if not has_async then
    return false, false, "plenary.async not available"
  end

  local done, call_ok, result = false, false, nil
  async.run(function()
    return pcall(fn)
  end, function(o, r)
    call_ok, result, done = o, r, true
  end)

  local completed = vim.wait(timeout or 8000, function()
    return done
  end, 50)
  return completed, call_ok, result
end

--- Return the first line of an executable's version output, or nil if missing.
---@param exe string Executable name
---@param version_arg string Argument that prints the version
---@return string|nil
local function exe_version(exe, version_arg)
  if vim.fn.executable(exe) ~= 1 then
    return nil
  end
  local out = vim.fn.system({ exe, version_arg })
  if vim.v.shell_error ~= 0 then
    return exe
  end
  return vim.trim(vim.split(out, "\n")[1] or exe)
end

--- Locate the LazyGit config file (honouring `lazygit --print-config-dir`).
---@return string
local function lazygit_config_path()
  if vim.fn.executable("lazygit") == 1 then
    local out = vim.fn.system({ "lazygit", "--print-config-dir" })
    if vim.v.shell_error == 0 then
      return vim.trim(out) .. "/config.yml"
    end
  end
  return vim.fn.expand("~/.config/lazygit/config.yml")
end

--- Neovim version and required external tools.
local function check_system()
  start("AutoCommitMessage.nvim [system]")

  local v = vim.version()
  local vstr = string.format("%d.%d.%d", v.major, v.minor, v.patch)
  if vim.fn.has("nvim-0.10") == 1 then
    ok("Neovim " .. vstr .. " (>= 0.10)")
  else
    err("Neovim " .. vstr .. " is too old", {
      "AutoCommitMessage.nvim requires Neovim 0.10+ (uses vim.system)",
    })
  end

  local git = exe_version("git", "--version")
  if git then
    ok(git)
  else
    err("git not found", { "Install git; it is required to read the diff" })
  end

  local nvr = exe_version("nvr", "--version")
  if nvr then
    ok("neovim-remote (nvr): " .. nvr)
  else
    err("neovim-remote (nvr) not found", {
      "Install with: pip install neovim-remote",
      "Required for the LazyGit integration",
    })
  end

  local lazygit = exe_version("lazygit", "--version")
  if lazygit then
    ok("lazygit: " .. lazygit)
  else
    warn("lazygit not found", {
      "Install lazygit if you use the LazyGit commit workflow",
    })
  end
end

--- CopilotChat presence and the specific API this plugin depends on.
---@param cc table|nil Loaded CopilotChat module, or nil if missing
local function check_copilot_chat(cc)
  start("AutoCommitMessage.nvim [copilot chat]")

  if not cc then
    err("CopilotChat.nvim not found", {
      "Install CopilotC-Nvim/CopilotChat.nvim",
      "This plugin requires it to generate commit messages",
    })
    return
  end
  ok("CopilotChat.nvim: installed")

  if pcall(require, "copilot") then
    ok("copilot.lua: installed")
  else
    warn("copilot.lua not found", {
      "Install zbirenbaum/copilot.lua",
      "Required for GitHub Copilot authorization",
    })
  end

  -- The plugin feeds the diff via the `gitdiff` context provider. If a future
  -- CopilotChat removes or renames it, generation silently gets no diff.
  local functions = cc.config and cc.config.functions
  if functions and functions.gitdiff then
    ok("CopilotChat 'gitdiff' resource: available")
  else
    err("CopilotChat 'gitdiff' resource: missing", {
      "This plugin sends the diff via `gitdiff:staged`/`gitdiff:unstaged`",
      "Your CopilotChat version may be incompatible",
    })
  end

  for _, lang in ipairs({ "markdown", "markdown_inline" }) do
    if pcall(vim.treesitter.language.inspect, lang) then
      ok("Treesitter parser '" .. lang .. "': installed")
    else
      warn("Treesitter parser '" .. lang .. "' not found", {
        "Install with: :TSInstall " .. lang,
        "CopilotChat needs it to render its chat window",
      })
    end
  end
end

--- Copilot authorization and whether the configured model actually exists.
--- Both require a network round-trip, so they run async under vim.wait.
---@param cc table Loaded CopilotChat module
local function check_authorization_and_model(cc)
  start("AutoCommitMessage.nvim [authorization & model]")

  local client_ok, client = pcall(require, "CopilotChat.client")
  if not client_ok then
    err("Could not load CopilotChat.client", { tostring(client) })
    return
  end

  local completed, call_ok, headers = run_async(function()
    return client:authenticate("copilot")
  end, 8000)
  if not completed then
    warn("Copilot authorization: check timed out", {
      "Network issue, or Copilot did not respond within 8s",
    })
  elseif call_ok and type(headers) == "table" and not vim.tbl_isempty(headers) then
    ok("Copilot: authorized")
  else
    err("Copilot: not authorized", {
      "Run :Copilot auth to sign in to GitHub Copilot",
      "Then open CopilotChat once to confirm it works",
      call_ok and "(empty credentials returned)" or tostring(headers),
    })
  end

  local configured = cc.config and cc.config.model or "(unset)"
  local mcompleted, mcall_ok, models = run_async(function()
    return client:models()
  end, 12000)
  if not mcompleted then
    warn("Copilot model '" .. configured .. "': could not verify (timed out)")
  elseif not mcall_ok or type(models) ~= "table" or vim.tbl_isempty(models) then
    err("Copilot models: could not fetch the model list", {
      "Usually caused by missing authorization (see above)",
      mcall_ok and "(no models returned)" or tostring(models),
    })
  elseif models[configured] then
    ok("Copilot model: '" .. configured .. "' is available")
  else
    local names = vim.tbl_keys(models)
    table.sort(names)
    local advice = { "Set a valid model in your CopilotChat config (see :CopilotChatModels)", "Available:" }
    for _, name in ipairs(vim.list_slice(names, 1, 15)) do
      table.insert(advice, "  - " .. name)
    end
    err("Copilot model: configured model '" .. configured .. "' not found", advice)
  end
end

--- LazyGit is wired to open commits in this Neovim instance via nvr.
local function check_lazygit()
  start("AutoCommitMessage.nvim [lazygit integration]")

  local cfg = lazygit_config_path()
  if vim.fn.filereadable(cfg) ~= 1 then
    warn("LazyGit config not found at " .. cfg, {
      "Create it so LazyGit opens commits in Neovim via nvr:",
      "os:",
      "  edit: 'nvr --servername $NVIM --remote-wait-silent {{filename}}'",
      "  editInTerminal: false",
    })
    return
  end
  ok("LazyGit config: " .. cfg)

  local content = table.concat(vim.fn.readfile(cfg), "\n")
  if content:match("nvr") then
    ok("LazyGit config references nvr")
  else
    warn("LazyGit config does not reference nvr", {
      "Add an `os.edit` entry that uses nvr; see the plugin README",
    })
  end
end

--- The plugin's own configuration state.
local function check_plugin_config()
  start("AutoCommitMessage.nvim [plugin]")

  local config = require("auto-commit-message.config")
  local opts = config.get()
  if not opts or next(opts) == nil then
    info(
      "Plugin not initialized in this session yet — call "
        .. "require('auto-commit-message').setup() (lazy.nvim `opts = {}` does this on load)."
    )
    return
  end

  ok(string.format("Configured (enabled=%s, staged_only=%s)", tostring(opts.enabled), tostring(opts.staged_only)))
  ok("Diff source: gitdiff:" .. (opts.staged_only and "staged" or "unstaged"))
  if opts.keymap then
    ok("Manual keymap: " .. opts.keymap)
  else
    info("No manual keymap set (opts.keymap = nil); use :AutoCommitMessage")
  end
end

function M.check()
  local has_cc, cc = pcall(require, "CopilotChat")

  check_system()
  check_copilot_chat(has_cc and cc or nil)
  if has_cc then
    check_authorization_and_model(cc)
  end
  check_lazygit()
  check_plugin_config()
end

return M
