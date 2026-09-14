#!/bin/sh
# my-pi — 给 Pi coding agent 装一套开箱可用的配置
#
# 一键安装（推荐，可交互）:
#   sh -c "$(curl -fsSL https://raw.githubusercontent.com/DieRingedesSaturn/my-pi/master/install.sh)"
#
# 也可以（非交互场景，stdin 会被占用，脚本无法从终端读输入）:
#   curl -fsSL https://raw.githubusercontent.com/DieRingedesSaturn/my-pi/master/install.sh | sh
#
# 重复执行 = 更新。本机未提交的改动会先备份再覆盖。

set -e

REPO="DieRingedesSaturn/my-pi"
BRANCH="${PI_BRANCH:-master}"
PI_DIR="$HOME/.pi/agent"
CONFIG_GIT="$HOME/.my-pi-config"
LOCAL_OVERRIDE="$HOME/.pi/pi-local.json"

echo "=== my-pi 安装 / 更新 ==="
echo ""

# ── 1. 前置检查 ──────────────────────────────────────────────
if ! command -v pi >/dev/null 2>&1; then
    echo "❌ 未找到 pi。请先安装 Pi coding agent：https://pi.dev"
    exit 1
fi
if ! command -v git >/dev/null 2>&1; then
    echo "❌ 未找到 git。请先安装："
    echo "   macOS:  xcode-select --install"
    echo "   Debian: sudo apt install git"
    echo "   Fedora: sudo dnf install git"
    exit 1
fi
echo "✅ pi 与 git 就绪"

# ── 2. 克隆或更新配置仓库 ────────────────────────────────────
# 公开仓库，无需任何凭据。PI_REPO_URL 可覆盖（fork 后自用 / 本地测试）。
REMOTE_URL="${PI_REPO_URL:-https://github.com/$REPO.git}"
if [ -d "$CONFIG_GIT" ]; then
    echo "📥 更新配置仓库..."
    BEFORE=$(git --git-dir="$CONFIG_GIT" rev-parse HEAD)
    if ! git --git-dir="$CONFIG_GIT" fetch origin "$BRANCH:$BRANCH" 2>&1 | sed 's/^/   /'; then
        echo "   ⚠️  快进失败（远端历史可能被重写），强制对齐..."
        git --git-dir="$CONFIG_GIT" fetch origin "+$BRANCH:$BRANCH" 2>&1 | sed 's/^/   /'
    fi
    AFTER=$(git --git-dir="$CONFIG_GIT" rev-parse HEAD)
    if [ "$BEFORE" = "$AFTER" ]; then
        echo "   ✅ 已是最新: $(git --git-dir="$CONFIG_GIT" log --oneline -1)"
    else
        echo "   ⬆️  $BEFORE → $AFTER"
        git --git-dir="$CONFIG_GIT" log --oneline "$BEFORE..$AFTER" | sed 's/^/      /'
    fi
else
    echo "📦 克隆配置仓库..."
    git clone --bare --quiet "$REMOTE_URL" "$CONFIG_GIT"
    git --git-dir="$CONFIG_GIT" rev-parse --verify "$BRANCH" >/dev/null 2>&1 || \
        git --git-dir="$CONFIG_GIT" branch "$BRANCH" "origin/$BRANCH" 2>/dev/null || true
    echo "   ✅ 已克隆到 $CONFIG_GIT"
fi

# ── 3. 展开到 ~/.pi/agent（覆盖前备份本机改动）────────────────
echo "📂 展开配置..."
CHANGED=$(git --git-dir="$CONFIG_GIT" --work-tree="$PI_DIR" status --porcelain 2>/dev/null || true)
if [ -n "$CHANGED" ]; then
    BACKUP="$HOME/my-pi-backup-$(date +%Y%m%d-%H%M%S)"
    mkdir -p "$BACKUP"
    echo "$CHANGED" | while read -r STATUS FILE; do
        if [ -f "$PI_DIR/$FILE" ]; then
            mkdir -p "$BACKUP/$(dirname "$FILE")"
            cp "$PI_DIR/$FILE" "$BACKUP/$FILE"
        fi
    done
    echo "   ⚠️  本机有未提交改动，已备份到: $BACKUP"
    echo "      恢复: cp -R \"$BACKUP\"/. \"$PI_DIR\"/"
fi
mkdir -p "$PI_DIR"
git --git-dir="$CONFIG_GIT" --work-tree="$PI_DIR" checkout -f

# ── 4. 从 .example 生成真实配置（仅在不存在时）────────────────
#     models.json / mcp.json 不入库（必然含个人域名或密钥引用），
#     所以首次安装时要从模板生成一份，之后由你自己维护。
echo "📝 生成配置文件..."
gen_from_example() {
    real="$PI_DIR/$1"
    tmpl="$PI_DIR/$1.example"
    if [ -f "$real" ]; then
        echo "   • $1 已存在，保持不动"
    elif [ -f "$tmpl" ]; then
        cp "$tmpl" "$real"
        echo "   ✳️  已从模板生成 $1 —— 需按需修改（域名、模型 ID 等）"
    fi
}
gen_from_example models.json
gen_from_example mcp.json

# ── 5. 可选：合并本机个人覆盖 ────────────────────────────────
#     把个人域名/地址放在 ~/.pi/pi-local.json（不跟踪），
#     便于自己多台设备复用时不必手改生成出来的文件。
if [ -f "$LOCAL_OVERRIDE" ]; then
    if command -v python3 >/dev/null 2>&1; then
        echo "🔀 合并本机覆盖 $LOCAL_OVERRIDE..."
        python3 - "$PI_DIR" "$LOCAL_OVERRIDE" <<'PYEOF'
import json, os, sys

pi_dir, override_path = sys.argv[1], sys.argv[2]
override = json.load(open(override_path, encoding='utf-8'))


def merge(path, incoming, key):
    """把 incoming 里的条目并入 path；同名键以 override 为准。"""
    if not incoming:
        return
    if os.path.exists(path):
        data = json.load(open(path, encoding='utf-8'))
    else:
        data = {}
    bucket = data.setdefault(key, {})
    for name, value in incoming.items():
        bucket[name] = value
    with open(path, 'w', encoding='utf-8') as fh:
        json.dump(data, fh, ensure_ascii=False, indent=2)
        fh.write('\n')
    print(f'   • {os.path.basename(path)}: 并入 {len(incoming)} 项')


merge(os.path.join(pi_dir, 'models.json'),
      override.get('providers'), 'providers')
merge(os.path.join(pi_dir, 'mcp.json'),
      override.get('mcpServers'), 'mcpServers')
PYEOF
    else
        echo "   ⚠️  跳过本机覆盖合并：需要 python3"
    fi
fi

# ── 6. 密钥扫描钩子 ──────────────────────────────────────────
#     目录名刻意用 .githooks/ 而非 hooks/ —— Pi 会把 hooks/ 当成
#     遗留扩展目录并告警。
echo "🛡️  安装密钥扫描钩子..."
if [ -x "$PI_DIR/.githooks/pre-commit" ]; then
    git --git-dir="$CONFIG_GIT" config core.hooksPath "$PI_DIR/.githooks"
    echo "   ✅ pre-commit 会拦截明文密钥"
else
    echo "   ⚠️  未找到 .githooks/pre-commit，跳过"
fi

# ── 7. MCP token 文件 ────────────────────────────────────────
#     MCP 凭据放这里，而不是写进 mcp.json —— 后者可能被同步/分享。
#     用文件而不是 OS 钥匙串，是为了让无头服务器（VPS）也能用：
#     适配器的钥匙串后端在无 Secret Service 的机器上是 fail-closed 的。
SECRET_DIR="$HOME/.pi-secrets"
TOKEN_FILE="$SECRET_DIR/mcp.token"
echo "🔑 检查 MCP token 文件..."
[ -d "$SECRET_DIR" ] || { mkdir -p "$SECRET_DIR" && chmod 700 "$SECRET_DIR"; }
if [ ! -f "$TOKEN_FILE" ]; then
    (umask 077; : > "$TOKEN_FILE")
    chmod 600 "$TOKEN_FILE"
    echo "   ✳️  已创建空文件 $TOKEN_FILE"
    echo "      如果用需要认证的 MCP server，把 token 填进去："
    echo "        printf '%s' '<token>' > $TOKEN_FILE"
    echo "      并在 mcp.json 里引用它："
    echo '        "bearerToken": "!cat ~/.pi-secrets/mcp.token"'
    echo "      空文件不会静默失败 —— 适配器会明确报 command returned empty output"
else
    PERM=$(stat -c '%a' "$TOKEN_FILE" 2>/dev/null || stat -f '%Lp' "$TOKEN_FILE" 2>/dev/null || echo '?')
    if [ "$PERM" != "600" ]; then
        chmod 600 "$TOKEN_FILE"
        echo "   🔧 权限 $PERM → 600（已修正）"
    else
        echo "   ✅ $TOKEN_FILE 存在（权限 600）"
    fi
fi

# ── 8. 安装插件 ──────────────────────────────────────────────
# pi-mcp-adapter 依赖一个挂在 pkg.pr.new 上的预发布包
# （@modelcontextprotocol/client，指向某个具体 commit 的 build）。
# npm 12 起默认 allow-remote=none，禁止这类"依赖直接写成 URL"的包，不加 flag 会直接失败。
# 代价是 npm 会从那个 URL 拉包；若不信任该来源，去掉 flag 并从 settings.json 与
# npm/package.json 中一并移除 pi-mcp-adapter。
echo "📦 安装插件（npm）..."
if [ -f "$PI_DIR/npm/package.json" ]; then
    NPM_LOG=$(mktemp "${TMPDIR:-/tmp}/my-pi-npm.XXXXXX")
    if ( cd "$PI_DIR/npm" && npm install --omit=dev --allow-remote=all ) >"$NPM_LOG" 2>&1; then
        tail -3 "$NPM_LOG" | sed 's/^/   /'
        echo "   ✅ 插件已安装"
    else
        echo "   ⚠️  npm install 失败："
        tail -12 "$NPM_LOG" | sed 's/^/      /'
        echo "      可稍后手动重跑：cd $PI_DIR/npm && npm install --allow-remote=all"
    fi
    rm -f "$NPM_LOG"
else
    echo "   ⚠️  未找到 npm/package.json，跳过"
fi

# ── 9. 终端背景色探测补丁 ────────────────────────────────────
#     Ghostty 等终端回答 DSR 明暗查询时用的是「系统外观」而非「终端实际背景」，
#     系统浅色 + 终端暗色会导致 Pi 加载浅色主题。补丁让 OSC 11 优先。
#     Pi 升级会覆盖 dist，所以每次跑本脚本都重新应用（脚本幂等）。
echo "🎨 应用主题探测补丁..."
PATCH_SCRIPT="$PI_DIR/patches/prefer-terminal-background-theme.mjs"
if [ -f "$PATCH_SCRIPT" ]; then
    if ! node "$PATCH_SCRIPT"; then
        echo "   ❌ 补丁未应用：Pi 可能升级改动了主题探测代码"
        exit 1
    fi
else
    echo "   ⚠️  未找到 $PATCH_SCRIPT，跳过"
fi

# ── 10. shell 别名 ───────────────────────────────────────────
ALIAS_LINE="alias pi-cfg='git --git-dir=\$HOME/.my-pi-config --work-tree=\$HOME/.pi/agent'"
add_alias() {
    rc="$1"
    if [ -f "$rc" ] && ! grep -q "pi-cfg'git --git-dir" "$rc" 2>/dev/null && \
       ! grep -q "my-pi-config" "$rc" 2>/dev/null; then
        {
            echo ""
            echo "# my-pi 配置管理"
            echo "$ALIAS_LINE"
        } >> "$rc"
        echo "   ✅ 已添加 pi-cfg 别名到 $rc"
    fi
}
add_alias "$HOME/.zshrc"
add_alias "$HOME/.bashrc"

# ── 完成 ─────────────────────────────────────────────────────
echo ""
echo "=== 完成 ==="
echo ""
echo "下一步:"
echo "  1. 在 Pi 里登录模型提供商:  /login"
echo "  2. 按需编辑 $PI_DIR/models.json（自建网关/本地模型）"
echo "  3. 按需编辑 $PI_DIR/mcp.json（MCP servers）"
echo ""
echo "日常维护:"
echo "  pi-cfg status              查看本机相对仓库的改动"
echo "  pi-cfg add <文件> / commit / push"
echo "  sh install.sh              重新拉取并应用最新配置（等于更新）"
echo ""
echo "文件约定:"
echo "  models.json / mcp.json   →  不入库，只跟踪对应的 .example 模板"
echo "  密钥                     →  ~/.pi-secrets/mcp.token（600）与 ~/.pi/agent/auth.json"
echo "  本机个人覆盖（可选）     →  ~/.pi/pi-local.json，安装时并入上面两个文件"
