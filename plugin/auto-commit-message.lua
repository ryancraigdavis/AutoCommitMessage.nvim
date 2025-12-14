-- AutoCommitMessage.nvim plugin loader
-- This file is automatically loaded by Neovim

-- Prevent loading twice
if vim.g.loaded_auto_commit_message then
  return
end
vim.g.loaded_auto_commit_message = true

-- Require Neovim 0.9+
if vim.fn.has("nvim-0.9") ~= 1 then
  vim.notify("AutoCommitMessage.nvim requires Neovim 0.9+", vim.log.levels.ERROR)
  return
end
