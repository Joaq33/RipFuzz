# **RipFuzz**  🌪️
[![Zsh Version](https://img.shields.io/badge/Zsh-5.8+-blue.svg)](https://www.zsh.org/)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
![Version: 0.0.1](https://img.shields.io/badge/Version-1.0.0-green.svg)

A lightning-fast, interactive file search and navigation tool powered by **ripgrep**, **fzf**, and **Neovim**. Search your codebase with real-time previews, multi-select capabilities, and intelligent copy options - all within your terminal.

## ✨ Features

- 🔍 Real-time search with ripgrep and fzf
- 🖼️ File previews with syntax highlighting
- 📋 Advanced copy menu with 8 formats
- 🧩 Multi-select and batch operations
- 🎨 Terminal-friendly UI with keyboard navigation
- 📦 Zero dependencies besides rg/fzf/nvim
- 🐧 Works on Linux/macOS/WSL

## ⚡ Installation

1. **Install prerequisites**:
   ```bash
   # macOS
   brew install ripgrep fzf neovim

   # Ubuntu/Debian
   sudo apt install ripgrep fzf neovim

   # Arch Linux
   sudo pacman -S ripgrep fzf neovim
   ```
2. Download the script:
```bash
curl -o ~/.ripfuzz.zsh https://raw.githubusercontent.com/Joaq33/ripfuzz/main/ripfuzz.zsh
```

3. Source in your .zshrc:
```bash
echo "source ~/.ripfuzz.zsh" >> ~/.zshrc
```

4. Reload your shell:
```bash
source ~/.zshrc
```

## 🕹️ Usage
Basic search:
```bash
ripfuzz
```

Search with options: (not functional yet)
```bash
ripfuzz --type=js -i "search term"
```
## Keyboard shortcuts in search mode:
| Key          | Action                          |
|--------------|---------------------------------|
| `Enter`      | Open selected file in Neovim    |
| `Ctrl+K`     | Show copy menu                  |
| `Alt+C`      | Alternative copy menu           |
| `Ctrl+Y`     | Quick copy file:line            |
| `Tab`        | Multi-select files              |
| `Ctrl+P`     | Toggle preview                  |
| `Ctrl+R`     | Reload search                   |

Copy menu options:
📋 File:line format
📁 Full file paths
📄 Filenames only
📝 Line content only
💻 Terminal commands
🔗 Relative paths
🌐 Markdown links
🧪 JSON format

## 🧩 .zshrc Integration
Add this to your .zshrc for quick access:

```bash
# ripfuzz integration
source ~/.ripfuzz.zsh

# Create handy aliases
alias search='ripfuzz'
(not implemented yet)alias codegrep='ripfuzz -w'
```
## 🚨 Troubleshooting
If you get "Missing dependencies" error:
```bash
# Verify installations
command -v rg && command -v fzf && command -v nvim

# If using kitty terminal
export TERM=xterm-256color
```
## 📜 License
MIT License - see LICENSE for details

"A powerful search workflow is the difference between coding and enjoying coding."

Inspired by modern developer experience principles
