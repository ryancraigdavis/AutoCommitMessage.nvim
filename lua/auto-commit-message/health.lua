-- Health check for AutoCommitMessage.nvim
-- Run with :checkhealth auto-commit-message

local M = {}

function M.check()
  vim.health.start("AutoCommitMessage.nvim")

  -- Check for neovim-remote (nvr)
  if vim.fn.executable("nvr") == 1 then
    vim.health.ok("neovim-remote (nvr) is installed")
  else
    vim.health.error("neovim-remote (nvr) not found", {
      "Install with: pip install neovim-remote",
      "This is required for LazyGit integration",
    })
  end

  -- Check for CopilotChat.nvim
  local has_copilot_chat = pcall(require, "CopilotChat")
  if has_copilot_chat then
    vim.health.ok("CopilotChat.nvim is installed")
  else
    vim.health.error("CopilotChat.nvim not found", {
      "Install CopilotC-Nvim/CopilotChat.nvim",
      "This plugin requires CopilotChat.nvim to generate commit messages",
    })
  end

  -- Check for copilot.lua
  local has_copilot = pcall(require, "copilot")
  if has_copilot then
    vim.health.ok("copilot.lua is installed")
  else
    vim.health.warn("copilot.lua not found", {
      "Install zbirenbaum/copilot.lua",
      "CopilotChat.nvim requires copilot.lua",
    })
  end

  -- Check for treesitter markdown parser
  local has_ts_markdown = pcall(vim.treesitter.language.inspect, "markdown")
  if has_ts_markdown then
    vim.health.ok("Treesitter markdown parser is installed")
  else
    vim.health.warn("Treesitter markdown parser not found", {
      "Install with: :TSInstall markdown markdown_inline",
      "CopilotChat.nvim requires markdown parser for its chat window",
    })
  end

  -- Check for treesitter markdown_inline parser
  local has_ts_markdown_inline = pcall(vim.treesitter.language.inspect, "markdown_inline")
  if has_ts_markdown_inline then
    vim.health.ok("Treesitter markdown_inline parser is installed")
  else
    vim.health.warn("Treesitter markdown_inline parser not found", {
      "Install with: :TSInstall markdown_inline",
    })
  end

  -- Check LazyGit config exists
  local lazygit_config = vim.fn.expand("~/.config/lazygit/config.yml")
  if vim.fn.filereadable(lazygit_config) == 1 then
    vim.health.ok("LazyGit config file exists at " .. lazygit_config)

    -- Check if config contains nvr
    local config_content = vim.fn.readfile(lazygit_config)
    local has_nvr = false
    for _, line in ipairs(config_content) do
      if line:match("nvr") then
        has_nvr = true
        break
      end
    end
    if has_nvr then
      vim.health.ok("LazyGit config appears to use nvr")
    else
      vim.health.warn("LazyGit config may not be configured to use nvr", {
        "Add to ~/.config/lazygit/config.yml:",
        "os:",
        "  edit: 'nvr --servername $NVIM --remote-wait-silent {{filename}}'",
        "  editAtLine: 'nvr --servername $NVIM --remote-wait-silent +{{line}} {{filename}}'",
        "  editAtLineAndWait: 'nvr --servername $NVIM --remote-wait-silent +{{line}} {{filename}}'",
        "  editInTerminal: false",
      })
    end
  else
    vim.health.warn("LazyGit config not found at " .. lazygit_config, {
      "Create ~/.config/lazygit/config.yml with nvr configuration",
      "See plugin README for details",
    })
  end

  -- Check if plugin is set up
  local config = require("auto-commit-message.config")
  if config.get().enabled ~= nil then
    vim.health.ok("Plugin is configured (enabled: " .. tostring(config.get().enabled) .. ")")
  else
    vim.health.warn("Plugin may not be set up", {
      "Call require('auto-commit-message').setup() in your config",
    })
  end
end

return M
