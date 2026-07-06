-- AutoCommitMessage.nvim
-- Automatically generate commit messages using CopilotChat when opening git commits

local M = {}

local config = require("auto-commit-message.config")

-- Track autocmd ID so we can remove it when disabling
local autocmd_id = nil

--- Clean up response from CopilotChat
--- Removes markdown code blocks and trims whitespace
---@param text string Raw response text
---@return string Cleaned text
local function clean_response(text)
  if not text then
    return ""
  end
  -- Remove markdown code blocks if present
  local cleaned = text:gsub("^```[^\n]*\n", ""):gsub("\n```%s*$", "")
  -- Trim leading/trailing whitespace
  cleaned = cleaned:gsub("^%s+", ""):gsub("%s+$", "")
  return cleaned
end

--- Resolve the working-tree root of the git repository for a buffer.
--- Commit buffers live inside the repo's git dir (e.g. `.git/COMMIT_EDITMSG`),
--- so we probe the buffer's directory, then its parent, then Neovim's cwd, and
--- return the first that resolves to a repository.
---@param bufnr number
---@return string|nil root Absolute path of the working tree, or nil if not found
local function git_root(bufnr)
  local name = vim.api.nvim_buf_is_valid(bufnr) and vim.api.nvim_buf_get_name(bufnr) or ""
  local candidates = {}
  if name ~= "" then
    local dir = vim.fn.fnamemodify(name, ":h")
    table.insert(candidates, dir)
    table.insert(candidates, vim.fn.fnamemodify(dir, ":h"))
  end
  table.insert(candidates, vim.fn.getcwd())

  for _, dir in ipairs(candidates) do
    local result = vim.system({ "git", "-C", dir, "rev-parse", "--show-toplevel" }):wait()
    if result.code == 0 then
      local root = vim.trim(result.stdout or "")
      if root ~= "" then
        return root
      end
    end
  end
  return nil
end

--- Return the git diff (staged or unstaged) for a repository, or "" if empty.
---@param root string Working-tree root
---@param staged_only boolean Diff staged changes (true) or unstaged (false)
---@return string diff
local function git_diff(root, staged_only)
  local cmd = { "git", "-C", root, "diff", "--no-color" }
  if staged_only then
    table.insert(cmd, "--staged")
  end
  local result = vim.system(cmd):wait()
  if result.code ~= 0 then
    return ""
  end
  return vim.trim(result.stdout or "")
end

--- Generate commit message using CopilotChat
--- Can be called manually or via autocmd
---@param target_bufnr number|nil Buffer number to insert into (defaults to current)
function M.generate(target_bufnr)
  target_bufnr = target_bufnr or vim.api.nvim_get_current_buf()
  local opts = config.get()

  local ok, chat = pcall(require, "CopilotChat")
  if not ok then
    vim.notify("AutoCommitMessage: CopilotChat.nvim is not installed", vim.log.levels.ERROR)
    return
  end

  -- CopilotChat v3+ no longer exposes a `selection`/`gitdiff` function. The git
  -- diff is now supplied as a "resource" (context provider): `gitdiff:staged`
  -- and `gitdiff:unstaged` inject the diff into the prompt context automatically.
  local resource = opts.staged_only and "gitdiff:staged" or "gitdiff:unstaged"

  -- CopilotChat runs the diff via `git` in its "source" window's cwd, which
  -- defaults to Neovim's cwd -- not necessarily this repo. Resolve the repo from
  -- the commit buffer and pin the source cwd to it, so the diff is always taken
  -- from the right repository.
  local root = git_root(target_bufnr)
  if root then
    -- Pre-flight: bail out with a clear message instead of asking Copilot to
    -- summarize an empty diff (which just replies "no diff detected").
    if git_diff(root, opts.staged_only) == "" then
      local what = opts.staged_only and "staged changes" or "changes"
      vim.notify("AutoCommitMessage: no " .. what .. " to summarize", vim.log.levels.WARN)
      return
    end

    -- Pin the repo cwd on every window showing the commit buffer (one of these
    -- becomes CopilotChat's "source"), plus the current window as a fallback.
    for _, win in ipairs(vim.fn.win_findbuf(target_bufnr)) do
      vim.w[win].cchat_cwd = root
    end
    vim.w[vim.api.nvim_get_current_win()].cchat_cwd = root
  end

  chat.ask(opts.prompt, {
    resources = { resource },
    callback = function(response, source)
      if response and response.content and response.content ~= "" then
        local cleaned = clean_response(response.content)

        if vim.api.nvim_buf_is_valid(target_bufnr) then
          local response_lines = vim.split(cleaned, "\n")
          vim.api.nvim_buf_set_lines(target_bufnr, 0, 0, false, response_lines)

          -- Move cursor to the commit buffer
          local wins = vim.fn.win_findbuf(target_bufnr)
          if #wins > 0 then
            vim.api.nvim_set_current_win(wins[1])
          end

          if opts.notify then
            vim.notify("Commit message generated", vim.log.levels.INFO)
          end
        end
      end

      -- Auto-close CopilotChat window if configured
      if opts.auto_close_chat then
        pcall(function()
          chat.close()
        end)
      end
    end,
  })
end

--- Auto-generate a message for a commit buffer, if appropriate.
--- Guards against generating twice for the same buffer, since both the FileType
--- autocmd and the lazy-load fallback in setup() can fire for the same commit.
---@param bufnr number Commit buffer to consider
local function maybe_auto_generate(bufnr)
  if not config.get().enabled then
    return
  end
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end
  -- Only generate once per commit buffer.
  if vim.b[bufnr].auto_commit_message_done then
    return
  end

  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, 1, false)
  -- Only auto-generate if the first line is empty (don't clobber an existing
  -- message, e.g. when amending a commit).
  if lines[1] and lines[1]:match("^%s*$") then
    vim.b[bufnr].auto_commit_message_done = true
    M.generate(bufnr)
  end
end

--- Create the autocmd for auto-generating commit messages
local function create_autocmd()
  if autocmd_id then
    vim.api.nvim_del_autocmd(autocmd_id)
  end

  autocmd_id = vim.api.nvim_create_autocmd("FileType", {
    pattern = "gitcommit",
    callback = function(args)
      local bufnr = args.buf
      vim.defer_fn(function()
        maybe_auto_generate(bufnr)
      end, config.get().defer_delay)
    end,
    group = vim.api.nvim_create_augroup("AutoCommitMessage", { clear = true }),
  })
end

--- Create user commands
local function create_commands()
  vim.api.nvim_create_user_command("AutoCommitMessage", function()
    M.generate()
  end, { desc = "Generate commit message with CopilotChat" })

  vim.api.nvim_create_user_command("AutoCommitMessageEnable", function()
    M.enable()
  end, { desc = "Enable auto commit message generation" })

  vim.api.nvim_create_user_command("AutoCommitMessageDisable", function()
    M.disable()
  end, { desc = "Disable auto commit message generation" })
end

--- Create keymap if configured
local function create_keymap()
  local opts = config.get()
  if opts.keymap then
    vim.keymap.set("n", opts.keymap, M.generate, {
      desc = "Generate commit message with CopilotChat",
      silent = true,
    })
  end
end

--- Enable auto-generation
function M.enable()
  local opts = config.get()
  opts.enabled = true
  vim.notify("AutoCommitMessage enabled", vim.log.levels.INFO)
end

--- Disable auto-generation
function M.disable()
  local opts = config.get()
  opts.enabled = false
  vim.notify("AutoCommitMessage disabled", vim.log.levels.INFO)
end

--- Check if auto-generation is enabled
---@return boolean
function M.is_enabled()
  return config.get().enabled
end

--- Setup the plugin
---@param opts table|nil User configuration options
function M.setup(opts)
  config.setup(opts)
  create_autocmd()
  create_commands()
  create_keymap()

  -- If we're already in a gitcommit buffer (lazy-loaded via `ft = "gitcommit"`),
  -- the FileType autocmd above was registered too late to fire for it, so trigger
  -- generation directly. maybe_auto_generate() guards against a double-generation
  -- if the autocmd does also fire.
  vim.defer_fn(function()
    if vim.bo.filetype == "gitcommit" then
      maybe_auto_generate(vim.api.nvim_get_current_buf())
    end
  end, config.get().defer_delay)
end

return M
