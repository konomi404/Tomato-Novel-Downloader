#!/usr/bin/env bash
#
# 文件名：installer_silent.sh
# 功能：全静默安装 Tomato-Novel-Downloader，适配 Docker 部署
#   1. 自动通过 GitHub API 获取最新版本
#   2. 使用预设安装路径（默认为 /usr/local/bin）
#   3. 支持环境变量配置（INSTALL_DIR, ACCEL_METHOD）
#   4. Termux 环境下自动处理依赖
#
# 使用方法：
#   chmod +x installer_silent.sh
#   ./installer_silent.sh
#
set -e

#####################################
# 0. 通用辅助函数
#####################################

log_info()  { printf "\033[1;32m[INFO]\033[0m %s\n" "$*"; }
log_warn()  { printf "\033[1;33m[WARN]\033[0m %s\n" "$*"; }
log_error() { printf "\033[1;31m[ERR ]\033[0m %s\n" "$*" >&2; }

command_exists() { command -v "$1" >/dev/null 2>&1; }

# 纯 Bash URL 编码
urlencode() {
    local raw="${1:?}"
    local out="" c
    local i len=${#raw}
    for (( i=0; i<len; i++ )); do
        c="${raw:i:1}"
        case "$c" in
            [a-zA-Z0-9._~/:=-]) out+="$c" ;;
            *) printf -v hex '%%%02X' "'$c"; out+="$hex" ;;
        esac
    done
    printf '%s' "$out"
}

# JSON 字段提取（优先 jq，失败则使用简单 grep+sed 兜底）
json_get_field() {
    local json="$1" field="$2"
    if command_exists jq; then
        printf "%s" "$json" | jq -r --arg f "$field" '.[$f] // .data[$f] // empty' 2>/dev/null || true
        return
    fi
    printf "%s" "$json" \
      | grep -o "\"$field\"[[:space:]]*:[[:space:]]*\"[^\"]*\"" \
      | head -n1 \
      | sed -E 's/.*:"([^"]*)".*/\1/'
}

#####################################
# 1. 配置参数（全静默）
#####################################

# 安装目录（可通过环境变量覆盖）
INSTALL_DIR="${INSTALL_DIR:-/usr/local/bin}"

# 下载方式（direct 或 cenguigui，可通过环境变量覆盖）
ACCEL_METHOD="${ACCEL_METHOD:-direct}"

# 检测 Termux 环境
IS_TERMUX=false
if [ -n "$PREFIX" ] && [[ "$PREFIX" == *"com.termux"* ]]; then
    IS_TERMUX=true
fi

log_info "开始静默安装..."
log_info "安装目录: $INSTALL_DIR"
log_info "下载方式: $ACCEL_METHOD"

# 创建安装目录（静默模式）
if [ ! -d "$INSTALL_DIR" ]; then
    mkdir -p "$INSTALL_DIR"
    log_info "已创建目录: $INSTALL_DIR"
fi

#####################################
# 2. 获取最新 Release tag_name
#####################################

log_info "正在从 GitHub API 获取最新版本信息..."
GITHUB_API_URL="https://api.github.com/repos/zhongbai2333/Tomato-Novel-Downloader/releases/latest"

TAG_NAME=""
if command_exists curl; then
    TAG_NAME=$(curl -s "${GITHUB_API_URL}" | grep -m1 '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
elif command_exists wget; then
    TAG_NAME=$(wget -qO- "${GITHUB_API_URL}" | grep -m1 '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
else
    log_error "系统中未检测到 curl 或 wget"
    exit 1
fi

if [ -z "$TAG_NAME" ]; then
    log_error "无法从 GitHub API 获取 tag_name"
    exit 1
fi

VERSION="${TAG_NAME#v}"
log_info "最新版本: ${TAG_NAME} (VERSION=${VERSION})"

#####################################
# 3. 检测系统与架构
#####################################

PLATFORM="$(uname)"
ARCH="$(uname -m)"
BINARY_NAME=""

case "$PLATFORM" in
    Linux)
        if $IS_TERMUX; then
            BINARY_NAME="TomatoNovelDownloader-Linux_arm64-v${VERSION}"
        else
            if [[ "$ARCH" == "x86_64" || "$ARCH" == "amd64" ]]; then
                BINARY_NAME="TomatoNovelDownloader-Linux_amd64-v${VERSION}"
            elif [[ "$ARCH" == "aarch64" || "$ARCH" == "arm64" ]]; then
                BINARY_NAME="TomatoNovelDownloader-Linux_arm64-v${VERSION}"
            else
                log_error "不支持的 Linux 架构 [${ARCH}]"
                exit 1
            fi
        fi
        ;;
    Darwin)
        if [[ "$ARCH" == "arm64" ]]; then
            BINARY_NAME="TomatoNovelDownloader-macOS_arm64-v${VERSION}"
        elif [[ "$ARCH" == "x86_64" || "$ARCH" == "amd64" ]]; then
            BINARY_NAME="TomatoNovelDownloader-macOS_amd64-v${VERSION}"
        else
            log_error "不支持的 macOS 架构 [${ARCH}]"
            exit 1
        fi
        ;;
    *)
        log_error "不支持的平台 [${PLATFORM}]"
        exit 1
        ;;
esac

#####################################
# 4. 生成下载 URL
#####################################

ORIGINAL_URL="https://github.com/zhongbai2333/Tomato-Novel-Downloader/releases/download/${TAG_NAME}/${BINARY_NAME}"
DOWNLOAD_URL="$ORIGINAL_URL"

resolve_cenguigui_url() {
    local orig="$1"
    local enc
    enc="$(urlencode "$orig")"
    local api="https://api.cenguigui.cn/api/github/?type=json&url=${enc}"
    
    local json=""
    if command_exists curl; then
        json=$(curl -s --connect-timeout 10 "$api" || true)
    else
        json=$(wget -qO- "$api" || true)
    fi
    
    if [ -z "$json" ]; then
        log_warn "笒鬼鬼 API 无响应"
        return 1
    fi
    
    local code
    code=$(json_get_field "$json" "code")
    if [ "$code" != "200" ]; then
        log_warn "笒鬼鬼 API 返回异常 code=${code:-空}"
        return 1
    fi
    
    local downUrl
    downUrl=$(json_get_field "$json" "downUrl")
    downUrl="${downUrl//\\//}"
    if [ -z "$downUrl" ]; then
        log_warn "未获取到 downUrl 字段"
        return 1
    fi
    printf "%s" "$downUrl"
}

case "$ACCEL_METHOD" in
    direct)
        log_info "使用直连下载"
        ;;
    cenguigui)
        if RESOLVED_URL=$(resolve_cenguigui_url "$ORIGINAL_URL"); then
            DOWNLOAD_URL="$RESOLVED_URL"
            log_info "笒鬼鬼 API 解析成功"
        else
            log_warn "笒鬼鬼 API 解析失败，回退直连"
            DOWNLOAD_URL="$ORIGINAL_URL"
        fi
        ;;
    *)
        log_warn "无效的下载方式，使用直连"
        DOWNLOAD_URL="$ORIGINAL_URL"
        ;;
esac

#####################################
# 5. 下载二进制
#####################################

TARGET_BINARY_PATH="${INSTALL_DIR}/${BINARY_NAME}"
if [ -f "$TARGET_BINARY_PATH" ]; then
    log_info "移除已存在的文件: ${TARGET_BINARY_PATH}"
    rm -f "$TARGET_BINARY_PATH"
fi

log_info "开始下载: ${BINARY_NAME}"

if command_exists wget; then
    wget -4 -q --show-progress -O "${TARGET_BINARY_PATH}" "${DOWNLOAD_URL}" || {
        log_error "wget 下载失败"
        exit 1
    }
elif command_exists curl; then
    curl -4 -L -o "${TARGET_BINARY_PATH}" "${DOWNLOAD_URL}" || {
        log_error "curl 下载失败"
        exit 1
    }
else
    log_error "未检测到 wget 或 curl"
    exit 1
fi

if [ ! -f "$TARGET_BINARY_PATH" ] || [ ! -s "$TARGET_BINARY_PATH" ]; then
    log_error "下载的文件不存在或为空"
    exit 1
fi

chmod +x "$TARGET_BINARY_PATH"
log_info "下载完成: ${TARGET_BINARY_PATH}"

#####################################
# 6. 平台后续操作
#####################################

if $IS_TERMUX; then
    log_info "检测到 Termux 环境，安装 glibc-repo 与 glibc-runner..."
    pkg update -y >/dev/null 2>&1
    pkg install -y glibc-repo glibc-runner >/dev/null 2>&1
    
    RUN_SH_PATH="${INSTALL_DIR}/run.sh"
    cat > "$RUN_SH_PATH" <<EOF
#!/usr/bin/env bash
SCRIPT_DIR="\$(cd "\$(dirname "\${BASH_SOURCE[0]}")" && pwd)"
exec glibc-runner "\${SCRIPT_DIR}/${BINARY_NAME}"
EOF
    chmod +x "$RUN_SH_PATH"
    log_info "已生成: ${RUN_SH_PATH}"
    
    # 创建软链接到 PATH
    ln -sf "$RUN_SH_PATH" "/data/data/com.termux/files/usr/bin/tomato-novel" 2>/dev/null || true
    log_info "创建软链接: /data/data/com.termux/files/usr/bin/tomato-novel"
else
    # 创建软链接到系统 PATH（Linux/macOS）
    BINARY_BASENAME="tomato-novel-downloader"
    SYMLINK_PATH="/usr/local/bin/${BINARY_BASENAME}"
    
    # 尝试创建软链接（需要sudo权限）
    if ln -sf "$TARGET_BINARY_PATH" "$SYMLINK_PATH" 2>/dev/null; then
        log_info "创建软链接: ${SYMLINK_PATH} -> ${TARGET_BINARY_PATH}"
    else
        # 如果无权限，则在当前目录创建
        LOCAL_SYMLINK="${INSTALL_DIR}/${BINARY_BASENAME}"
        ln -sf "$BINARY_NAME" "$LOCAL_SYMLINK"
        log_info "创建本地软链接: ${LOCAL_SYMLINK} -> ${BINARY_NAME}"
    fi
fi

log_info "安装完成"
echo "二进制文件: ${TARGET_BINARY_PATH}"
echo "运行命令:"
if $IS_TERMUX; then
    echo "  tomato-novel 或 ${RUN_SH_PATH}"
else
    echo "  tomato-novel-downloader 或 ${TARGET_BINARY_PATH}"
fi

exit 0
