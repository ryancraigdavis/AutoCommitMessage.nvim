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

  local select_ok, select = pcall(require, "CopilotChat.select")
  if not select_ok then
    vim.notify("AutoCommitMessage: Could not load CopilotChat.select", vim.log.levels.ERROR)
    return
  end

  chat.ask(opts.prompt, {
    selection = function(source)
      return select.gitdiff(source, opts.staged_only)
    end,
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

--- Create the autocmd for auto-generating commit messages
local function create_autocmd()
  local opts = config.get()

  if autocmd_id then
    vim.api.nvim_del_autocmd(autocmd_id)
  end

  autocmd_id = vim.api.nvim_create_autocmd("FileType", {
    pattern = "gitcommit",
    callback = function()
      if not config.get().enabled then
        return
      end

      vim.defer_fn(function()
        local commit_bufnr = vim.api.nvim_get_current_buf()
        local lines = vim.api.nvim_buf_get_lines(commit_bufnr, 0, 1, false)

        -- Only auto-generate if the commit message is empty
        if lines[1] and lines[1]:match("^%s*$") then
          M.generate(commit_bufnr)
        end
      end, opts.defer_delay)
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
end

return M
