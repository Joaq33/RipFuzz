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
Usage: rgvim [options] [search_term]

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

function _show_copy_menu() {
    local selections="$1"
    local num_results=$(echo "$selections" | wc -l)
    
    # Create temporary file for selections
    local temp_file=$(mktemp)
    echo "$selections" > "$temp_file"
    
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
        # Use built-in zsh clear instead of external clear
        builtin print -n "\e[H\e[2J\e[3J"
        
        echo "📋 COPY MENU - ${num_results} selected"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo "Current selection preview:"
        echo "$selections" | head -5 | awk -F: '{printf "%-35s %4s  %s\n", substr($1, length($1)-34 < 1 ? 1 : length($1)-34), $2":"$3, $4}' 
        [[ $num_results -gt 5 ]] && echo "... and $((num_results - 5)) more"
        echo ""
        echo "┌────────────┬──────────────────────────────────────────────┐"
        for option in "${copy_options[@]}"; do
            printf "│ %-10s │ %-44s │\n" "${option%%:*}" "${option#*:}"
        done
        echo "└────────────┴──────────────────────────────────────────────┘"
        echo ""
        echo "ⓘ  Press 1-8 to copy, P for preview, V to view, or Q to quit"
        echo ""
        read -k1 -s choice
        
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
                    # Clear using zsh built-in
                    builtin print -n "\e[H\e[2J\e[3J"
                    echo "✅ Copied to clipboard! Preview:"
                    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
                    echo "$result" | head -10
                    [[ $(echo "$result" | wc -l) -gt 10 ]] && echo "... and $(( $(echo "$result" | wc -l) - 10 )) more"
                    echo ""
                    echo "Press any key to continue..."
                    read -k1 -s
                fi
                break
                ;;
            p|P)
                # Show preview selector
                builtin print -n "\e[H\e[2J\e[3J"
                echo "🔍 PREVIEW OPTIONS - ${num_results} selected"
                echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
                
                local i=1
                for option in "${copy_options[@]}"; do
                    printf "%d) %s\n" $i "${option#*:}"
                    ((i++))
                done
                echo ""
                echo -n "Select preview option (1-8): "
                read -k1 -s preview_choice
                
                if [[ "$preview_choice" =~ [1-8] ]]; then
                    builtin print -n "\e[H\e[2J\e[3J"
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
                        8) echo "$selections" | while IFS=: read -r file line_num content; do
                             content_escaped=${content//\"/\\\"}
                             echo "{\"file\":\"$file\",\"line\":$line_num,\"content\":\"$content_escaped\"}"
                           done | head -5 ;;
                    esac
                    echo ""
                    echo "Press any key to continue..."
                    read -k1 -s
                fi
                ;;
            v|V)
                # View full content
                builtin print -n "\e[H\e[2J\e[3J"
                echo "📄 VIEWING SELECTION CONTENT"
                echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
                echo "$selections" | head -50
                [[ $num_results -gt 50 ]] && echo "... and $((num_results - 50)) more"
                echo ""
                echo "Press any key to continue..."
                read -k1 -s
                ;;
            q|Q)
                echo "❌ Copy cancelled"
                break
                ;;
        esac
    done
    
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

# =============================================================================
# MAIN FUNCTIONS
# =============================================================================

# Simple interactive search and open
function rgvim() {
    _check_dependencies || return 1
    
    local search_term
    search_term=$(_get_search_term "$@") || return 1
    
    local choice
    choice=$(rg -il "$search_term" | fzf \
        --exit-0 \
        --select-1 \
        --ansi \
        --preview "rg '$search_term' --context 3 --color=always {}" \
        --preview-window=right:50%:wrap \
        --header="Search: $search_term" \
        --bind "ctrl-r:reload(rg -il '$search_term')" \
        --bind "ctrl-p:toggle-preview")
    
    if [[ -n "$choice" ]]; then
        local vim_search="${search_term:l}"
        nvim "+/$vim_search" "$choice"
    fi
}

# Enhanced version with live search and advanced features
function rgvim_enhanced() {
    _check_dependencies || return 1
    
    local type_filter="" extra_args=""
    eval $(_parse_search_args "$@") || return 0
    
    # Create the base command template
    local rg_base="rg --column --line-number --no-heading --color=always --smart-case"
    [[ -n "$type_filter" ]] && rg_base="$rg_base $type_filter"
    [[ -n "$extra_args" ]] && rg_base="$rg_base $extra_args"
    
    # Temporary file for selections
    local copyfile=$(mktemp)
    
    local choice
    choice=$(fzf \
        --disabled \
        --ansi \
        --multi \
        --bind "change:reload(if [[ -n {q} ]]; then $rg_base {q}; else true; fi)" \
        --bind "ctrl-r:reload(if [[ -n {q} ]]; then $rg_base {q}; else true; fi)" \
        --bind "ctrl-p:toggle-preview" \
        --bind "ctrl-u:preview-up" \
        --bind "ctrl-d:preview-down" \
        --bind "ctrl-y:execute-silent(echo {} | cut -d: -f1,2 | if command -v pbcopy >/dev/null 2>&1; then pbcopy; elif command -v xclip >/dev/null 2>&1; then xclip -selection clipboard; elif command -v wl-copy >/dev/null 2>&1; then wl-copy; fi)" \
        --bind "ctrl-m:execute(echo {+} > $copyfile)+abort" \
        --bind "alt-c:execute(echo {+} > $copyfile)+abort" \
        --bind "ctrl-o:execute(echo {+} | cut -d: -f1 | xargs ls -la)" \
        --bind "ctrl-g:execute(echo {} | cut -d: -f1 | xargs git log --oneline -5)" \
        --bind "alt-enter:execute(echo {+} | cut -d: -f1 | xargs nvim -o)" \
        --delimiter : \
        --preview "FILE=\$(echo {} | cut -d: -f1); LINE=\$(echo {} | cut -d: -f2); if command -v bat >/dev/null 2>&1; then bat --color=always --style=numbers --highlight-line=\$LINE \"\$FILE\" 2>/dev/null; else if [[ -n {q} ]]; then rg --context 8 --color=always --line-number --smart-case {q} \"\$FILE\" 2>/dev/null; else cat \"\$FILE\" 2>/dev/null; fi; fi" \
        --preview-window=right:60%:wrap:+{2}-5 \
        --header="🔍 Search | Tab:select | Enter:open | Ctrl+Y:quick-copy | Ctrl+M:copy-menu | Alt+C:copy-menu | Ctrl+P:preview" \
        --prompt="Search > " \
        --info=inline \
        --border=rounded \
        --height=90%)
    
    # Check if we need to show copy menu
    if [[ -s $copyfile ]]; then
        _show_copy_menu "$(cat $copyfile)"
        rm -f $copyfile
        return
    fi
    
    _open_files "$choice"
    rm -f $copyfile
}
