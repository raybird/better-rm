#!/bin/bash
#
# better-rm 安裝腳本
# Installation script for better-rm
#
# 用法 (Usage):
#   bash -c "$(curl -fsSL https://raw.githubusercontent.com/raybird/better-rm/main/install.sh)"
#   或 (or)
#   bash install.sh [repository_path]
#

set -euo pipefail

# 顏色定義
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 顯示訊息函式
info_msg() {
    echo -e "${BLUE}資訊 (Info): $1${NC}"
}

success_msg() {
    echo -e "${GREEN}✓ $1${NC}"
}

warn_msg() {
    echo -e "${YELLOW}⚠ $1${NC}"
}

error_msg() {
    echo -e "${RED}✗ $1${NC}" >&2
}

# 取得腳本所在目錄（安全方式）
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-}")" && pwd)"
REPO_PATH="${1:-}"

# 驗證關鍵環境變數
if [ -z "$HOME" ]; then
    echo "錯誤: HOME 環境變數未設定" >&2
    exit 1
fi

# 安裝目錄
INSTALL_DIR="$HOME/.local/bin"
SCRIPT_NAME="better-rm"

# 檢測 shell 類型
detect_shell() {
    if [ -n "$ZSH_VERSION" ]; then
        echo "zsh"
    elif [ -n "$BASH_VERSION" ]; then
        echo "bash"
    else
        echo "unknown"
    fi
}

# 取得 shell 設定檔路徑
get_shell_config() {
    local shell_type=$(detect_shell)
    case "$shell_type" in
        zsh)
            echo "$HOME/.zshrc"
            ;;
        bash)
            if [ -f "$HOME/.bash_profile" ]; then
                echo "$HOME/.bash_profile"
            else
                echo "$HOME/.bashrc"
            fi
            ;;
        *)
            echo "$HOME/.bashrc"
            ;;
    esac
}

# 檢查 PATH 是否包含安裝目錄
is_in_path() {
    # 使用固定字串避免注入問題
    echo "$PATH" | grep -qF "$INSTALL_DIR" || return 1
    return 0
}

# 更新 PATH 環境變數
update_path() {
    local config_file=$(get_shell_config)
    local path_export='export PATH="$HOME/.local/bin:$PATH"'
    
    if [ -f "$config_file" ]; then
        # 使用固定字串搜尋，避免注入問題
        if grep -qF "$INSTALL_DIR" "$config_file" 2>/dev/null; then
            info_msg "PATH 已包含 $INSTALL_DIR"
            return 0
        fi
    fi
    
    info_msg "正在更新 $config_file..."
    echo "" >> "$config_file"
    echo "# better-rm PATH" >> "$config_file"
    echo "$path_export" >> "$config_file"
    success_msg "已更新 $config_file"
    warn_msg "請執行 'source $config_file' 或重新開啟終端機以套用變更"
}

# 檢查是否已設定 rm 別名
is_alias_set() {
    local config_file=$(get_shell_config)
    if [ -f "$config_file" ]; then
        # 檢查是否已有 better-rm 相關的別名設定
        if grep -qE "^[[:space:]]*alias[[:space:]]+rm=['\"]better-rm['\"]" "$config_file" 2>/dev/null; then
            return 0
        fi
    fi
    return 1
}

# 設定 rm 別名
setup_alias() {
    local config_file=$(get_shell_config)
    local alias_line="alias rm='better-rm'"
    
    if is_alias_set; then
        info_msg "rm 別名已設定"
        return 0
    fi
    
    info_msg "正在設定 rm 別名..."
    echo "" >> "$config_file"
    echo "# better-rm: 使用 better-rm 替代系統 rm 命令" >> "$config_file"
    echo "# 如需使用系統原生的 rm，請使用 /bin/rm 或 \\rm" >> "$config_file"
    echo "$alias_line" >> "$config_file"
    success_msg "已設定 rm 別名"
    warn_msg "請執行 'source $config_file' 或重新開啟終端機以套用變更"
    return 0
}

# 驗證倉庫路徑格式（防止路徑注入）
validate_repo_path() {
    local repo_path="$1"
    # 只允許字母、數字、連字號、底線和斜線
    # 格式應該是：username/repo-name
    if [[ ! "$repo_path" =~ ^[a-zA-Z0-9_.-]+/[a-zA-Z0-9_.-]+$ ]]; then
        return 1
    fi
    return 0
}

# 驗證下載的腳本是否為有效的 bash 腳本
validate_downloaded_script() {
    local script_file="$1"
    
    # 檢查檔案是否存在且不為空
    if [ ! -f "$script_file" ] || [ ! -s "$script_file" ]; then
        return 1
    fi
    
    # 檢查是否以 shebang 開頭
    if ! head -n 1 "$script_file" | grep -q "^#!/bin/bash"; then
        return 1
    fi
    
    return 0
}

# 下載腳本（從 GitHub）
download_script() {
    local repo_path="$1"
    
    # 驗證倉庫路徑格式
    if ! validate_repo_path "$repo_path"; then
        error_msg "無效的倉庫路徑格式: $repo_path"
        error_msg "格式應為: username/repository-name"
        return 1
    fi
    
    local url="https://raw.githubusercontent.com/${repo_path}/main/better-rm"
    local temp_file="${INSTALL_DIR}/${SCRIPT_NAME}.tmp"
    
    info_msg "正在從 GitHub 下載 better-rm..."
    info_msg "來源: $url"
    
    # 先下載到臨時檔案
    if command -v curl >/dev/null 2>&1; then
        if ! curl -fsSL "$url" -o "$temp_file"; then
            error_msg "下載失敗，請檢查網路連線或 URL"
            rm -f "$temp_file" 2>/dev/null || true
            return 1
        fi
    elif command -v wget >/dev/null 2>&1; then
        if ! wget -q "$url" -O "$temp_file"; then
            error_msg "下載失敗，請檢查網路連線或 URL"
            rm -f "$temp_file" 2>/dev/null || true
            return 1
        fi
    else
        error_msg "需要 curl 或 wget 才能下載腳本"
        return 1
    fi
    
    # 驗證下載的檔案
    if ! validate_downloaded_script "$temp_file"; then
        error_msg "下載的檔案無效或損壞"
        rm -f "$temp_file" 2>/dev/null || true
        return 1
    fi
    
    # 驗證通過後，移動到目標位置
    if mv "$temp_file" "$INSTALL_DIR/$SCRIPT_NAME"; then
        success_msg "已下載並驗證 better-rm"
        return 0
    else
        error_msg "無法移動下載的檔案"
        rm -f "$temp_file" 2>/dev/null || true
        return 1
    fi
}

# 複製本地腳本
copy_local_script() {
    local source_file="$SCRIPT_DIR/$SCRIPT_NAME"
    
    if [ ! -f "$source_file" ]; then
        error_msg "找不到 $source_file"
        return 1
    fi
    
    # 驗證來源檔案
    if ! validate_downloaded_script "$source_file"; then
        error_msg "來源檔案無效或損壞"
        return 1
    fi
    
    info_msg "正在複製本地腳本..."
    if cp "$source_file" "$INSTALL_DIR/$SCRIPT_NAME"; then
        success_msg "已複製 better-rm"
        return 0
    else
        error_msg "複製失敗"
        return 1
    fi
}

# 主安裝流程
main() {
    echo "=========================================="
    echo "  better-rm 安裝程式"
    echo "  better-rm Installation Script"
    echo "=========================================="
    echo ""
    
    # 建立安裝目錄
    info_msg "正在建立安裝目錄: $INSTALL_DIR"
    mkdir -p "$INSTALL_DIR" || {
        error_msg "無法建立目錄: $INSTALL_DIR"
        exit 1
    }
    success_msg "已建立安裝目錄"
    
    # 下載或複製腳本
    if [ -n "$REPO_PATH" ]; then
        # 從 GitHub 下載
        if ! download_script "$REPO_PATH"; then
            exit 1
        fi
    else
        # 檢查是否在專案目錄中
        if [ -f "$SCRIPT_DIR/$SCRIPT_NAME" ]; then
            copy_local_script
        else
            # 嘗試從預設的 GitHub 路徑下載
            info_msg "未指定倉庫路徑，嘗試從預設位置下載..."
            if ! download_script "raybird/better-rm"; then
                error_msg "請在專案目錄中執行此腳本，或提供 GitHub 倉庫路徑"
                echo ""
                echo "用法範例 (Usage examples):"
                echo "  本地安裝: bash install.sh"
                echo "  從 GitHub: bash -c \"\$(curl -fsSL https://raw.githubusercontent.com/raybird/better-rm/main/install.sh)\""
                exit 1
            fi
        fi
    fi
    
    # 設定執行權限
    info_msg "正在設定執行權限..."
    chmod +x "$INSTALL_DIR/$SCRIPT_NAME" || {
        error_msg "無法設定執行權限"
        exit 1
    }
    success_msg "已設定執行權限"
    
    # 更新 PATH
    if ! is_in_path; then
        update_path
    else
        info_msg "PATH 已包含 $INSTALL_DIR"
    fi
    
    # 詢問是否要設定 rm 別名
    echo ""
    if is_alias_set; then
        info_msg "rm 別名已設定，無需重複設定"
    else
        echo -n "是否要設定 rm 別名以替代系統 rm 命令？(y/N): "
        read -r response
        if [[ "$response" =~ ^[yY] ]]; then
            setup_alias
        else
            info_msg "跳過別名設定，您可以稍後手動設定"
        fi
    fi
    
    # 驗證安裝
    echo ""
    info_msg "正在驗證安裝..."
    if [ -x "$INSTALL_DIR/$SCRIPT_NAME" ]; then
        success_msg "安裝成功！"
        echo ""
        echo "=========================================="
        echo "  安裝完成 (Installation Complete)"
        echo "=========================================="
        echo ""
        
        # 顯示版本資訊（使用絕對路徑，避免 PATH 注入）
        if [ -x "$INSTALL_DIR/$SCRIPT_NAME" ]; then
            "$INSTALL_DIR/$SCRIPT_NAME" --version 2>/dev/null || true
        fi
        
        echo ""
        info_msg "下一步 (Next steps):"
        echo ""
        local config_file=$(get_shell_config)
        
        if is_alias_set; then
            echo "1. 重新載入 shell 設定檔以套用變更 (Reload shell config):"
            echo "   source $config_file"
            echo ""
            echo "2. 驗證安裝 (Verify installation):"
            echo "   rm --version  # 應該顯示 better-rm 版本"
            echo ""
            warn_msg "注意：如需使用系統原生的 rm，請使用 /bin/rm 或 \\rm"
        else
            echo "1. 重新載入 shell 設定檔 (Reload shell config):"
            echo "   source $config_file"
            echo ""
            echo "2. 設定別名以替代 rm 命令 (Set alias to replace rm):"
            echo "   在 $config_file 中加入："
            echo "   alias rm='better-rm'"
            echo ""
            echo "3. 驗證安裝 (Verify installation):"
            echo "   better-rm --version"
            echo ""
            warn_msg "注意：設定別名後，仍可使用 /bin/rm 或 \\rm 呼叫系統原生的 rm 命令"
        fi
        echo ""
    else
        error_msg "安裝驗證失敗"
        exit 1
    fi
}

# 執行主程式
main "$@"

