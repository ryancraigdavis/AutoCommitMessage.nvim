# AutoCommitMessage.nvim

Automatically generate commit messages using GitHub Copilot when opening git commits in Neovim.

When you press `C` (uppercase) in LazyGit to create a commit, this plugin automatically generates a commit message based on your staged changes using CopilotChat.

## Features

- Automatic commit message generation when opening `gitcommit` buffers
- Uses CopilotChat to analyze staged changes and generate meaningful commit messages
- Follows commitizen convention by default
- Configurable prompts for different commit message styles
- Manual trigger command for regenerating messages
- Health check integration (`:checkhealth auto-commit-message`)

## Requirements

- **Neovim** 0.9+
- **[CopilotChat.nvim](https://github.com/CopilotC-Nvim/CopilotChat.nvim)** - Chat interface for GitHub Copilot
- **[copilot.lua](https://github.com/zbirenbaum/copilot.lua)** - GitHub Copilot integration
- **[neovim-remote](https://github.com/mhinz/neovim-remote)** (`nvr`) - For LazyGit integration
- **Treesitter parsers** - `markdown` and `markdown_inline`

### Installing Dependencies

**neovim-remote:**
```bash
pip install neovim-remote
```

**Treesitter parsers** (in Neovim):
```vim
:TSInstall markdown markdown_inline
```

## Installation

### [lazy.nvim](https://github.com/folke/lazy.nvim)

```lua
{
  "ryancraigdavis/AutoCommitMessage.nvim",
  dependencies = {
    "CopilotC-Nvim/CopilotChat.nvim",
  },
  ft = "gitcommit",
  opts = {},
}
```

### [packer.nvim](https://github.com/wbthomason/packer.nvim)

```lua
use {
  "ryancraigdavis/AutoCommitMessage.nvim",
  requires = {
    "CopilotC-Nvim/CopilotChat.nvim",
  },
  config = function()
    require("auto-commit-message").setup()
  end,
}
```

## Configuration

```lua
require("auto-commit-message").setup({
  -- Enable/disable auto-generation on gitcommit filetype
  enabled = true,

  -- Prompt sent to CopilotChat for generating commit messages
  prompt = 'Write commit message for the change with commitizen convention. '
    .. 'Write clear, informative commit messages that explain the "what" and "why" '
    .. 'behind changes, not just the "how". '
    .. 'Return ONLY the commit message, no explanation or markdown formatting.',

  -- Only use staged changes (true) or all changes (false)
  staged_only = true,

  -- Delay in ms before triggering generation (allows buffer to fully load)
  defer_delay = 100,

  -- Show notification when commit message is inserted
  notify = true,

  -- Auto-close CopilotChat window after generation
  auto_close_chat = true,

  -- Keymap for manual trigger (nil = disabled)
  -- Example: "<leader>gcm"
  keymap = nil,
})
```

### Custom Prompts

You can customize the prompt for different commit message styles:

**Conventional Commits:**
```lua
prompt = "Write a commit message following Conventional Commits specification. "
  .. "Format: <type>(<scope>): <description>. "
  .. "Types: feat, fix, docs, style, refactor, test, chore. "
  .. "Return ONLY the commit message.",
```

**Gitmoji:**
```lua
prompt = "Write a commit message using gitmoji convention. "
  .. "Start with an appropriate emoji. "
  .. "Return ONLY the commit message.",
```

## LazyGit Configuration

For this plugin to work with LazyGit, you need to configure LazyGit to open files in the parent Neovim instance using `nvr`.

**~/.config/lazygit/config.yml:**
```yaml
os:
  edit: 'nvr --servername $NVIM --remote-wait-silent {{filename}}'
  editAtLine: 'nvr --servername $NVIM --remote-wait-silent +{{line}} {{filename}}'
  editAtLineAndWait: 'nvr --servername $NVIM --remote-wait-silent +{{line}} {{filename}}'
  editInTerminal: false
```

Replace `nvr` with the full path if it's not in your PATH (e.g., `/home/user/.local/bin/nvr`).

### lazygit.nvim Configuration

If you're using [lazygit.nvim](https://github.com/kdheepak/lazygit.nvim):

```lua
{
  "kdheepak/lazygit.nvim",
  lazy = true,
  cmd = { "LazyGit" },
  keys = {
    { "<leader>gs", "<cmd>LazyGit<cr>", desc = "LazyGit" },
  },
  config = function()
    vim.g.lazygit_floating_window_scaling_factor = 0.9
    vim.g.lazygit_use_neovim_remote = 1
  end,
}
```

## Usage

1. Open Neovim in a git repository
2. Open LazyGit (e.g., `<leader>gs`)
3. Stage your changes (select files, press `space`)
4. Press **`C`** (uppercase, Shift+C) to commit with editor
5. Wait for CopilotChat to generate the commit message
6. Edit the message if needed
7. Save and quit (`:wq`) to complete the commit

**Note:** Lowercase `c` in LazyGit opens a simple inline input and won't trigger the editor or this plugin.

## Commands

| Command | Description |
|---------|-------------|
| `:AutoCommitMessage` | Manually generate a commit message |
| `:AutoCommitMessageEnable` | Enable auto-generation |
| `:AutoCommitMessageDisable` | Disable auto-generation |

## Health Check

Run `:checkhealth auto-commit-message` to verify your setup. It checks for:

- neovim-remote (nvr) installation
- CopilotChat.nvim presence
- copilot.lua presence
- Treesitter markdown parsers
- LazyGit configuration

## How It Works

```
User presses <leader>gs
        │
        ▼
LazyGit opens in floating terminal
        │
        ▼
User stages files and presses 'C' (uppercase)
        │
        ▼
LazyGit invokes: nvr --servername $NVIM --remote-wait-silent COMMIT_EDITMSG
        │
        ▼
COMMIT_EDITMSG opens in parent Neovim (new buffer)
        │
        ▼
Neovim detects filetype = "gitcommit"
        │
        ▼
Plugin autocmd fires, checks if first line is empty
        │
        ▼
CopilotChat.ask() called with staged diff
        │
        ▼
Copilot generates commit message
        │
        ▼
Callback inserts message into COMMIT_EDITMSG buffer
        │
        ▼
User edits if needed, then :wq
        │
        ▼
nvr returns control to LazyGit
        │
        ▼
LazyGit completes the commit
```

## Troubleshooting

### Commit buffer doesn't open in Neovim

- Verify `nvr` is installed: `which nvr`
- Check LazyGit config uses correct nvr path
- Ensure `$NVIM` is set (run `echo $NVIM` in Neovim's `:terminal`)

### CopilotChat errors about markdown parser

Install treesitter parsers:
```vim
:TSInstall markdown markdown_inline
```

### Message not generated

- Check `:messages` for errors
- Verify CopilotChat is working: `:CopilotChatCommitStaged`
- Run `:checkhealth auto-commit-message`

### LazyGit uses wrong editor

- Run `lazygit --print-config-dir` to verify config location
- Check config syntax in `config.yml`
- Make sure you're pressing uppercase `C`, not lowercase `c`

## License

MIT License - see [LICENSE](LICENSE) for details.

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.
