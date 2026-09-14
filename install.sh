#!/bin/sh
# my-pi — 把一套 Pi coding agent 配置装到本机
#
# 一键安装（推荐）:
#   sh -c "$(curl -fsSL https://raw.githubusercontent.com/DieRingedesSaturn/my-pi/master/install.sh)"
#
# 也可以（stdin 会被脚本占用，脚本无法再向你提问）:
#   curl -fsSL https://raw.githubusercontent.com/DieRingedesSaturn/my-pi/master/install.sh | sh
#
# 设计说明:
#   这是「装一次就归你」的安装器，不是 git 跟踪。
#   它把模板文件复制进 ~/.pi/agent，覆盖前先备份，完成后你随意改。
#   重复执行 = 用最新模板更新（同样先备份）。
#   你的个人配置（models.json / mcp.json / 记忆 / 会话）不在模板里，永远不被触碰。

set -e

REPO="DieRingedesSaturn/my-pi"
BRANCH="${PI_BRANCH:-master}"
PI_DIR="$HOME/.pi/agent"
CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/my-pi"
LOCAL_OVERRIDE="$HOME/.pi/pi-local.json"
STAMP=$(date +%Y%m%d-%H%M%S)
BACKUP="$HOME/my-pi-backup-$STAMP"

# 模板里要安装的条目（相对路径）。刻意逐条列出而不用通配符，
# 这样永远不会误伤 ~/.pi/agent 下不在清单里的东西。
MANIFEST="
settings.json
pi-speeed.json
extensions/pi-permission-system/config.json
themes/everforest-dark.json
themes/everforest-light.json
patches/prefer-terminal-background-theme.mjs
skills/astronomy-plotting/SKILL.md
skills/astronomy-plotting/agents/openai.yaml
skills/astronomy-plotting/scripts/astronomy_style.py
npm/package.json
npm/.gitignore
.githooks/pre-commit
models.json.example
mcp.json.example
"

echo "=== my-pi 安装 ==="
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

# ── 2. 取模板到缓存目录 ──────────────────────────────────────
# 公开仓库，无需任何凭据。用缓存目录而不是 clone 到 ~/.pi/agent，
# 是为了不建立任何 git 跟踪关系。
SRC_URL="${PI_REPO_URL:-https://github.com/$REPO.git}"
echo "📥 获取模板..."
if [ -d "$CACHE_DIR/.git" ]; then
    git -C "$CACHE_DIR" fetch --depth 1 origin "$BRANCH" >/dev/null 2>&1
    git -C "$CACHE_DIR" checkout -q FETCH_HEAD
    echo "   ✅ 已更新 $CACHE_DIR @ $(git -C "$CACHE_DIR" rev-parse --short HEAD)"
else
    rm -rf "$CACHE_DIR"
    git clone --depth 1 --branch "$BRANCH" --quiet "$SRC_URL" "$CACHE_DIR"
    echo "   ✅ 已克隆到 $CACHE_DIR @ $(git -C "$CACHE_DIR" rev-parse --short HEAD)"
fi

# ── 3. 复制模板（覆盖前备份）─────────────────────────────────
echo "📂 展开配置到 $PI_DIR ..."
mkdir -p "$PI_DIR"
ADDED=0
UPDATED=0
for rel in $MANIFEST; do
    src="$CACHE_DIR/$rel"
    dst="$PI_DIR/$rel"
    if [ ! -f "$src" ]; then
        echo "   ⚠️  模板缺少 $rel，跳过"
        continue
    fi
    if [ -f "$dst" ] && cmp -s "$src" "$dst"; then
        continue
    fi
    if [ -f "$dst" ]; then
        # 只在真的要覆盖时才创建备份目录
        mkdir -p "$BACKUP/$(dirname "$rel")"
        cp "$dst" "$BACKUP/$rel"
        echo "   ⬆️  更新 $rel（原文件已备份）"
        UPDATED=$((UPDATED + 1))
    else
        echo "   ＋  新增 $rel"
        ADDED=$((ADDED + 1))
    fi
    mkdir -p "$(dirname "$dst")"
    cp "$src" "$dst"
done
if [ "$ADDED" = "0" ] && [ "$UPDATED" = "0" ]; then
    echo "   · 所有文件都已是模板版本，无改动"
else
    SUMMARY=""
    [ "$ADDED" = "0" ]   || SUMMARY="新增 $ADDED 个"
    [ "$UPDATED" = "0" ] || SUMMARY="$SUMMARY 更新 $UPDATED 个"
    echo "   📦$SUMMARY"
fi

# ── 4. 生成真实配置（仅在不存在时）───────────────────────────
# 这两个文件必然含个人域名或凭据引用，所以模板里只放 .example。
# 注意：已存在就完全不动 —— 你的配置不会被安装器改写。
echo "📝 检查个人配置..."
for name in models.json mcp.json; do
    if [ -f "$PI_DIR/$name" ]; then
        echo "   · $name 已存在，保持不动"
    elif [ -f "$PI_DIR/$name.example" ]; then
        cp "$PI_DIR/$name.example" "$PI_DIR/$name"
        echo "   ✳️  已从模板生成 $name —— 需按需修改"
    fi
done

# ── 5. 可选：合并本机个人覆盖 ────────────────────────────────
# 多台设备复用个人配置时，把值放 ~/.pi/pi-local.json（不属于模板），
# 安装后自动并入。支持三段: providers / mcpServers / settings
if [ -f "$LOCAL_OVERRIDE" ]; then
    if command -v python3 >/dev/null 2>&1; then
        echo "🔀 合并本机覆盖 $LOCAL_OVERRIDE ..."
        python3 - "$PI_DIR" "$LOCAL_OVERRIDE" <<'PYEOF'
import json, os, sys

pi_dir, override_path = sys.argv[1], sys.argv[2]
override = json.load(open(override_path, encoding='utf-8'))


def merge_nested(filename, incoming, key):
    """把 incoming 并入 filename 的 key 段（同名键以 override 为准）。"""
    if not incoming:
        return
    path = os.path.join(pi_dir, filename)
    data = json.load(open(path, encoding='utf-8')) if os.path.exists(path) else {}
    bucket = data.setdefault(key, {})
    bucket.update(incoming)
    with open(path, 'w', encoding='utf-8') as fh:
        json.dump(data, fh, ensure_ascii=False, indent=2)
        fh.write('\n')
    print(f'   • {filename} [{key}]: 并入 {len(incoming)} 项')


def merge_settings(incoming):
    """settings.json 浅合并：override 的键覆盖模板值。"""
    if not incoming:
        return
    path = os.path.join(pi_dir, 'settings.json')
    data = json.load(open(path, encoding='utf-8')) if os.path.exists(path) else {}
    data.update(incoming)
    with open(path, 'w', encoding='utf-8') as fh:
        json.dump(data, fh, ensure_ascii=False, indent=2)
        fh.write('\n')
    print(f'   • settings.json: 覆盖 {len(incoming)} 项（{", ".join(incoming)}）')


merge_nested('models.json', override.get('providers'), 'providers')
merge_nested('mcp.json', override.get('mcpServers'), 'mcpServers')
merge_settings(override.get('settings'))
PYEOF
    else
        echo "   ⚠️  跳过本机覆盖合并：需要 python3"
    fi
fi

# ── 6. MCP token 文件 ────────────────────────────────────────
# 凭据不写进 mcp.json（那个文件可能被同步或分享）。
# 用文件而不是 OS 钥匙串，是为了让无头服务器（VPS）也能用同一份配置 ——
# 适配器的钥匙串后端在无 Secret Service 的机器上会 fail-closed，不退回明文。
SECRET_DIR="$HOME/.pi-secrets"
TOKEN_FILE="$SECRET_DIR/mcp.token"
echo "🔑 检查 MCP token 文件..."
[ -d "$SECRET_DIR" ] || { mkdir -p "$SECRET_DIR" && chmod 700 "$SECRET_DIR"; }
if [ ! -f "$TOKEN_FILE" ]; then
    (umask 077; : > "$TOKEN_FILE")
    chmod 600 "$TOKEN_FILE"
    echo "   ✳️  已创建空文件 $TOKEN_FILE"
    echo "      如果用到需要认证的 MCP server，把 token 填进去："
    echo "        printf '%s' '<token>' > $TOKEN_FILE"
    echo "      然后在 mcp.json 里引用："
    echo '        "bearerToken": "!cat ~/.pi-secrets/mcp.token"'
    echo "      （空文件不会静默失败，适配器会明确报 command returned empty output）"
else
    PERM=$(stat -c '%a' "$TOKEN_FILE" 2>/dev/null || stat -f '%Lp' "$TOKEN_FILE" 2>/dev/null || echo '?')
    if [ "$PERM" != "600" ]; then
        chmod 600 "$TOKEN_FILE"
        echo "   🔧 权限 $PERM → 600（已修正）"
    else
        echo "   ✅ $TOKEN_FILE 存在（权限 600）"
    fi
fi

# ── 7. 安装插件 ──────────────────────────────────────────────
# pi-mcp-adapter 依赖一个挂在 pkg.pr.new 上的预发布包
# （@modelcontextprotocol/client 指向具体 commit 的 build）。npm 12 起默认
# allow-remote=none，禁止"把依赖写成 URL"，不加 flag 必然失败。
# 如不信任该来源，去掉 flag 并从 settings.json / npm/package.json 移除 pi-mcp-adapter。
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

# ── 8. 终端背景色探测补丁 ────────────────────────────────────
# Ghostty 等终端回答 DSR 明暗查询时用的是「系统外观」而非「终端实际背景」，
# 系统浅色 + 终端暗色会导致 Pi 加载浅色主题。补丁让 OSC 11 优先。
# Pi 升级会覆盖 dist，所以每次跑本脚本都重新应用（脚本幂等）。
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

# ── 完成 ─────────────────────────────────────────────────────
echo ""
echo "=== 完成 ==="
echo ""
echo "下一步:"
echo "  1. 在 Pi 里登录模型提供商:  /login"
echo "  2. 按需编辑 $PI_DIR/models.json（自建网关 / 本地模型）"
echo "  3. 按需编辑 $PI_DIR/mcp.json（MCP servers）"
echo ""
echo "更新:"
echo "  重跑本命令即可。模板更新会覆盖对应文件，覆盖前自动备份到"
echo "  ~/my-pi-backup-<时间戳>/；你个人的 models.json、mcp.json 与"
echo "  记忆/会话数据不在模板里，永远不会被改动。"
echo ""
echo "本机个人覆盖（可选）:"
echo "  $LOCAL_OVERRIDE —— 支持 providers / mcpServers / settings 三段，"
echo "  每次安装后自动并入，便于多台设备复用个人域名与默认模型。"
echo ""
[ "$UPDATED" = "0" ] || echo "被覆盖的原文件已备份到: $BACKUP"
