#!/bin/zsh

# =============================================================================
# CORE UTILITY FUNCTIONS
# =============================================================================

# Check if required commands are available
function _check_dependencies() {
    local missing_deps=()
    
    command -v rg >/dev/null 2>&1 || missing_deps+=("ripgrep")
    command -v fzf >/dev/null 2>&1 || missing_deps+=("fzf")
    command -v nvim >/dev/null 2>&1 || missing_deps+=("neovim")
    
    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        echo "❌ Missing dependencies: ${missing_deps[*]}"
        return 1
    fi
    return 0
}

# Get search term from user input or arguments
function _get_search_term() {
    local search_term="$*"
    
    if [[ -z "$search_term" ]]; then
        echo "Enter search term: "
        read search_term
        [[ -z "$search_term" ]] && return 1
    fi
    
    echo "$search_term"
}

# Parse command line arguments for search options
function _parse_search_args() {
    local -A options
    options[type]=""
    options[extra_args]=""
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            -t|--type)
                options[type]="--type=$2"
                shift 2
                ;;
            -i|--ignore-case)
                options[extra_args]="${options[extra_args]} --ignore-case"
                shift
                ;;
            -w|--word-regexp)
                options[extra_args]="${options[extra_args]} --word-regexp"
                shift
                ;;
            -h|--help)
                _show_help
                return 1
                ;;
            *)
                break
                ;;
        esac
    done
    
    # Output as associative array format that can be eval'd
    echo "type='${options[type]}' extra_args='${options[extra_args]}'"
}

# Show help message
function _show_help() {
    cat << 'EOF'
Usage: ripfuzz [options] [search_term]

Options:
  -t, --type TYPE     Search only files of TYPE (e.g., js, py, md)
  -i, --ignore-case   Case insensitive search
  -w, --word-regexp   Match whole words only
  -h, --help          Show this help

Keyboard shortcuts:
  Ctrl+R: Reload search
  Ctrl+P: Toggle preview
  Ctrl+T: Change file type filter
  Ctrl+I: Toggle case sensitivity
  Ctrl+W: Toggle word boundary
  Ctrl+G: Show git status of file
  Ctrl+Y: Copy file:line to clipboard
  Alt+Enter: Open in split
EOF
}

# =============================================================================
# CLIPBOARD UTILITIES
# =============================================================================

# Cross-platform clipboard copy function
function _copy_to_clipboard() {
    local content="$1"
    
    if command -v pbcopy >/dev/null 2>&1; then
        echo "$content" | pbcopy
        return 0
    elif command -v xclip >/dev/null 2>&1; then
        echo "$content" | xclip -selection clipboard
        return 0
    elif command -v wl-copy >/dev/null 2>&1; then
        echo "$content" | wl-copy
        return 0
    else
        echo "❌ No clipboard utility found (pbcopy, xclip, or wl-copy)"
        return 1
    fi
}

# Quick copy file:line format
function _quick_copy_file_line() {
    local selection="$1"
    local file_line=$(echo "$selection" | cut -d: -f1,2)
    
    if _copy_to_clipboard "$file_line"; then
        echo "✅ Copied: $file_line"
    else
        echo "❌ Failed to copy to clipboard"
    fi
}

# =============================================================================
# ENHANCED COPY MENU WITH KITTY TERMINAL SUPPORT
# =============================================================================

function _show_copy_menu() {
    local selections="$1"
    local num_results=$(echo "$selections" | wc -l)
    
    # Create temporary file for selections
    local temp_file=$(mktemp)
    echo "$selections" > "$temp_file"
    
    # Enter alternate screen
    print -n "\e[?1049h\e[H" > /dev/tty
    
    # Define copy options with emojis
    local copy_options=(
        "1: 📋 File:line format (file.js:42)"
        "2: 📁 Full file paths"
        "3: 📄 Filenames only"
        "4: 📝 Line content only"
        "5: 💻 Terminal commands (nvim +42 file.js)"
        "6: 🔗 Relative paths"
        "7: 🌐 Markdown links ([file.js:42](path))"
        "8: 🧪 JSON format"
    )
    
    # Display fancy menu
    while true; do
        # Clear using ANSI escape sequences
        print -n "\e[H\e[2J\e[3J" > /dev/tty
        
        # Print menu to terminal
        {
            echo "📋 COPY MENU - ${num_results} selected"
            echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
            echo "Current selection preview:"
            
            # Show all selected items, not just the first
            echo "$selections" | head -10 | while IFS=: read -r file line_num content; do
                printf "%-35s %4s  %s\n" "${file##${PWD}/}" "$line_num" "${content:0:50}"
            done
            
            [[ $num_results -gt 10 ]] && echo "... and $((num_results - 10)) more"
            echo ""
            echo "┌────────────┬──────────────────────────────────────────────┐"
            for option in "${copy_options[@]}"; do
                printf "│ %-10s │ %-44s │\n" "${option%%:*}" "${option#*:}"
            done
            echo "└────────────┴──────────────────────────────────────────────┘"
            echo ""
            echo "ⓘ  Press 1-8 to copy, P for preview, V to view, or Q to quit"
            echo ""
        } > /dev/tty
        
        # Read from terminal
        read -k1 -s choice < /dev/tty
        
        case "$choice" in
            [1-8])
                local option_num=${choice}
                local result=""
                
                case $option_num in
                    1) result=$(echo "$selections" | cut -d: -f1,2) ;;
                    2) result=$(echo "$selections" | cut -d: -f1) ;;
                    3) result=$(echo "$selections" | cut -d: -f1 | while read file; do basename "$file"; done) ;;
                    4) result=$(echo "$selections" | cut -d: -f3-) ;;
                    5) result=$(echo "$selections" | while IFS=: read -r file line_num content; do
                          echo "nvim +$line_num \"$file\""
                       done) ;;
                    6) result=$(echo "$selections" | cut -d: -f1 | while read file; do
                          realpath --relative-to=. "$file" 2>/dev/null || echo "$file"
                       done) ;;
                    7) result=$(echo "$selections" | while IFS=: read -r file line_num content; do
                          base=$(basename "$file")
                          rel=$(realpath --relative-to=. "$file" 2>/dev/null || echo "$file")
                          echo "[$base:$line_num]($rel#L$line_num)"
                       done) ;;
                    8) result=$(echo "$selections" | while IFS=: read -r file line_num content; do
                          content_escaped=${content//\"/\\\"}
                          echo "{\"file\":\"$file\",\"line\":$line_num,\"content\":\"$content_escaped\"}"
                       done) ;;
                esac
                
                if _copy_to_clipboard "$result"; then
                    print -n "\e[H\e[2J\e[3J" > /dev/tty
                    {
                        echo "✅ Copied to clipboard! Preview:"
                        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
                        echo "$result" | head -10
                        [[ $(echo "$result" | wc -l) -gt 10 ]] && echo "... and $(( $(echo "$result" | wc -l) - 10 )) more"
                        echo ""
                        echo "Press any key to return to search..."
                    } > /dev/tty
                    read -k1 -s < /dev/tty
                fi
                break
                ;;
            p|P)
                # Show preview selector
                print -n "\e[H\e[2J\e[3J" > /dev/tty
                {
                    echo "🔍 PREVIEW OPTIONS - ${num_results} selected"
                    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
                    
                    local i=1
                    for option in "${copy_options[@]}"; do
                        printf "%d) %s\n" $i "${option#*:}"
                        ((i++))
                    done
                    echo ""
                    echo -n "Select preview option (1-8): "
                } > /dev/tty
                read -k1 -s preview_choice < /dev/tty
                
                if [[ "$preview_choice" =~ [1-8] ]]; then
                    print -n "\e[H\e[2J\e[3J" > /dev/tty
                    {
                        echo "👀 PREVIEW: ${copy_options[$preview_choice]#*:}"
                        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
                        
                        case $preview_choice in
                            1) echo "$selections" | cut -d: -f1,2 | head -20 ;;
                            2) echo "$selections" | cut -d: -f1 | head -20 ;;
                            3) echo "$selections" | cut -d: -f1 | while read file; do basename "$file"; done | head -20 ;;
                            4) echo "$selections" | cut -d: -f3- | head -20 ;;
                            5) echo "$selections" | while IFS=: read -r file line_num content; do
                                 echo "nvim +$line_num \"$file\""
                               done | head -20 ;;
                            6) echo "$selections" | cut -d: -f1 | while read file; do
                                 realpath --relative-to=. "$file" 2>/dev/null || echo "$file"
                               done | head -20 ;;
                            7) echo "$selections" | while IFS=: read -r file line_num content; do
                                 base=$(basename "$file")
                                 rel=$(realpath --relative-to=. "$file" 2>/dev/null || echo "$file")
                                 echo "[$base:$line_num]($rel#L$line_num)"
                               done | head -20 ;;
                            8) 
                                # Special handling for JSON preview
                                echo "$selections" | while IFS=: read -r file line_num content; do
                                    content_escaped=${content//\"/\\\"}
                                    echo "{\"file\":\"$file\",\"line\":$line_num,\"content\":\"$content_escaped\"}"
                                done | head -5 | jq . 2>/dev/null || {
                                    echo "Raw JSON preview:"
                                    echo "$selections" | while IFS=: read -r file line_num content; do
                                        content_escaped=${content//\"/\\\"}
                                        echo "{\"file\":\"$file\",\"line\":$line_num,\"content\":\"$content_escaped\"}"
                                    done | head -5
                                }
                                ;;
                        esac
                        echo ""
                        echo "Press any key to return to menu..."
                    } > /dev/tty
                    read -k1 -s < /dev/tty
                fi
                ;;
            v|V)
                # View full content
                print -n "\e[H\e[2J\e[3J" > /dev/tty
                {
                    echo "📄 VIEWING SELECTION CONTENT"
                    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
                    echo "$selections" | head -50
                    [[ $num_results -gt 50 ]] && echo "... and $((num_results - 50)) more"
                    echo ""
                    echo "Press any key to continue..."
                } > /dev/tty
                read -k1 -s < /dev/tty
                ;;
            q|Q)
                break
                ;;
        esac
    done
    
    # Exit alternate screen
    print -n "\e[?1049l" > /dev/tty
    rm -f "$temp_file"
}

# =============================================================================
# SEARCH FUNCTIONALITY
# =============================================================================

# Build ripgrep command with options
function _build_rg_command() {
    local search_term="$1" type_filter="$2" extra_args="$3"
    
    # Handle empty search term
    if [[ -z "$search_term" ]]; then
        echo "true"  # fzf requires some command, true does nothing
        return
    fi
    
    local cmd="rg --column --line-number --no-heading --color=always --smart-case"
    
    [[ -n "$type_filter" ]] && cmd="$cmd $type_filter"
    [[ -n "$extra_args" ]] && cmd="$cmd $extra_args"
    
    # Properly escape the search term
    cmd="$cmd $(printf '%q' "$search_term")"
    
    echo "$cmd"
}

# Generate preview command for fzf
function _build_preview_command() {
    cat << 'EOF'
FILE=$(echo {} | cut -d: -f1); 
LINE=$(echo {} | cut -d: -f2); 
if command -v bat >/dev/null 2>&1; then 
    bat --color=always --style=numbers --highlight-line=$LINE "$FILE" 2>/dev/null; 
else 
    rg --context 8 --color=always --line-number --smart-case {q} "$FILE" 2>/dev/null || cat "$FILE"; 
fi
EOF
}

# =============================================================================
# FILE OPENING FUNCTIONALITY
# =============================================================================

# Open selected file(s) in nvim
function _open_files() {
    local choice="$1"
    [[ -z "$choice" ]] && { echo "❌ No file selected"; return 1; }
    
    local line_count=$(echo "$choice" | wc -l)
    
    if [[ $line_count -gt 1 ]]; then
        _open_multiple_files "$choice"
    else
        _open_single_file "$choice"
    fi
}

# Open multiple files in nvim
function _open_multiple_files() {
    local choice="$1"
    echo "📁 Opening multiple files..."
    
    local nvim_args=()
    local files_with_lines=()
    
    while IFS=: read -r file line_num content; do
        if [[ -n "$file" && -f "$file" ]]; then
            echo "  → $file:$line_num"
            files_with_lines+=("$file")
        fi
    done <<< "$choice"
    
    if [[ ${#files_with_lines[@]} -gt 0 ]]; then
        # Get first file's line number for initial cursor position
        local first_line=$(echo "$choice" | head -1 | cut -d: -f2)
        
        # Open all files, starting with the first one at the correct line
        nvim "+$first_line" "${files_with_lines[@]}"
    fi
}

# Open single file in nvim
function _open_single_file() {
    local choice="$1"
    local file line_num content
    IFS=: read -r file line_num content <<< "$choice"
    
    if [[ -n "$file" && -f "$file" ]]; then
        echo "📄 Opening: $file at line $line_num"
        
        # Check git status if file is in git repo
        if git ls-files --error-unmatch "$file" &>/dev/null; then
            local git_status=$(git status --porcelain "$file" 2>/dev/null)
            [[ -n "$git_status" ]] && echo "📝 Git status: $git_status"
        fi
        
        if [[ -n "$line_num" && "$line_num" =~ ^[0-9]+$ ]]; then
            nvim "+$line_num" "+normal! zz" "$file"
        else
            nvim "$file"
        fi
    else
        echo "❌ File not found: $file"
        return 1
    fi
}

# # =============================================================================
# # MAIN FUNCTION
# # =============================================================================
function ripfuzz() {
    _check_dependencies || return 1
    
    local type_filter="" extra_args=""
    eval $(_parse_search_args "$@") || return 0
    
    # Create the base command template
    local rg_base="rg --column --line-number --no-heading --color=always --smart-case"
    [[ -n "$type_filter" ]] && rg_base="$rg_base $type_filter"
    [[ -n "$extra_args" ]] && rg_base="$rg_base $extra_args"
    
    # Temporary file for selections
    local copyfile=$(mktemp)
    
    # Variable to track if we should show copy menu
    local show_copy_menu=0
    
    local choice
    choice=$(fzf \
        --disabled \
        --ansi \
        --multi \
        --bind "enter:accept" \
        --bind "change:reload(if [[ -n {q} ]]; then $rg_base {q}; else true; fi)" \
        --bind "ctrl-r:reload(if [[ -n {q} ]]; then $rg_base {q}; else true; fi)" \
        --bind "ctrl-p:toggle-preview" \
        --bind "ctrl-u:preview-up" \
        --bind "ctrl-d:preview-down" \
        --bind "ctrl-y:execute-silent(echo {} | cut -d: -f1,2 | if command -v pbcopy >/dev/null 2>&1; then pbcopy; elif command -v xclip >/dev/null 2>&1; then xclip -selection clipboard; elif command -v wl-copy >/dev/null 2>&1; then wl-copy; fi)" \
        --bind "ctrl-k:execute(printf '%s\n' {+} > $copyfile; echo 1 > ${copyfile}.flag)+abort" \
        --bind "alt-c:execute(printf '%s\n' {+} > $copyfile; echo 1 > ${copyfile}.flag)+abort" \
        --delimiter : \
        --preview "FILE=\$(echo {} | cut -d: -f1); LINE=\$(echo {} | cut -d: -f2); if command -v bat >/dev/null 2>&1; then bat --color=always --style=numbers --highlight-line=\$LINE \"\$FILE\" 2>/dev/null; else if [[ -n {q} ]]; then rg --context 8 --color=always --line-number --smart-case {q} \"\$FILE\" 2>/dev/null; else cat \"\$FILE\" 2>/dev/null; fi; fi" \
        --preview-window=right:60%:wrap:+{2}-5 \
        --header="🔍 Search | Tab:select | Enter:open | Ctrl+Y:quick-copy | Ctrl+K:copy-menu | Alt+C:copy-menu | Ctrl+P:preview" \
        --prompt="Search > " \
        --info=inline \
        --border=rounded \
        --height=90%)
    
    # Check if we need to show copy menu
    if [[ -f "${copyfile}.flag" ]]; then
        show_copy_menu=1
        rm -f "${copyfile}.flag"
    fi
    
    if [[ $show_copy_menu -eq 1 ]]; then
        if [[ -s $copyfile ]]; then
            local selections=$(cat "$copyfile")
            _show_copy_menu "$selections"
        else
            echo "❌ No selections to copy"
        fi
        rm -f $copyfile
        return
    fi
    
    # If user selected files normally (without copy menu)
    if [[ -n "$choice" ]]; then
        _open_files "$choice"
    else
        echo "❌ No file selected"
    fi
    
    rm -f $copyfile
}
