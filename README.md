# my-pi

给 [Pi coding agent](https://pi.dev) 用的一套配置：核心设置、权限模型、主题、期刊级绘图技能，加上一个一键安装脚本。

**装一次就归你。** 这是安装器而不是配置仓库 —— 它把模板文件复制进 `~/.pi/agent`，
之后你随便改。你个人的 `models.json`、`mcp.json`、记忆与会话数据从不在模板里，永远不会被覆盖。

不含任何个人域名、内网地址与密钥；所有敏感值都以模板形式提供，由你在本机填写。

## 一键安装

```sh
sh -c "$(curl -fsSL https://raw.githubusercontent.com/DieRingedesSaturn/my-pi/master/install.sh)"
```

重复执行同一条命令即为**更新**：会用最新模板覆盖对应文件，覆盖前自动备份到
`~/my-pi-backup-<时间戳>/`。

> 也支持 `curl -fsSL <url> | sh`，但那样 stdin 会被脚本占用，脚本无法再向你提问。
> 需要交互时用上面的 `sh -c "$(...)"` 形式。

安装脚本做的事：

1. 检查 `pi` 与 `git`
2. 把模板取到缓存目录 `~/.cache/my-pi`（**不** clone 进 `~/.pi/agent`，不建立 git 跟踪关系）
3. 按显式清单复制模板文件到 `~/.pi/agent`，覆盖前先备份并逐个报告
4. 若 `models.json` / `mcp.json` 不存在，从 `.example` 生成（已存在则绝不改动）
5. 若存在 `~/.pi/pi-local.json`，把其中的个人配置并进去
6. 准备好 `~/.pi-secrets/mcp.token`（600 权限）
7. `npm install` 安装插件
8. 应用终端背景色探测补丁

**不安装** `README.md`、`install.sh`、`.gitignore`、`.githooks/` —— 那些是本仓库自身的文件。

## 装了什么

| 文件 | 作用 |
|------|------|
| `settings.json` | 核心设置：主题、思考等级、compaction 预算、插件清单 |
| `extensions/pi-permission-system/config.json` | 权限模型：分层放行 + 显式保护敏感路径 |
| `themes/everforest-{dark,light}.json` | Everforest 低饱和主题（明/暗） |
| `patches/prefer-terminal-background-theme.mjs` | 修 Ghostty 等终端的明暗误判 |
| `skills/astronomy-plotting/` | 期刊级天文绘图技能（AAS/IOP 规范 + 合规审计脚本） |
| `npm/package.json` | 插件依赖清单 |
| `pi-speeed.json` | tok/s 显示插件配置 |
| `models.json.example` | 模型提供商模板 |
| `mcp.json.example` | MCP server 模板 |

### 插件

```
pi-mcp-adapter                        MCP 支持（省 token 的懒加载）
@gotgenes/pi-permission-system        权限审批
pi-subagents                          子代理编排
@juicesharp/rpiv-todo                 任务清单
@juicesharp/rpiv-ask-user-question    结构化提问
@ayulab/pi-rewind                     会话回退
pi-speeed                             生成速度显示
pi-markdown-preview                   Markdown 预览
better-custom                         自定义工具
```

## 密钥怎么放

**永远不要把密钥写进配置文件。** 三条路径：

| 类型 | 位置 | 说明 |
|------|------|------|
| 模型提供商密钥 | `~/.pi/agent/auth.json` | 用 Pi 里的 `/login` 写入，权限 600 |
| MCP token | `~/.pi-secrets/mcp.token` | 600 权限，配置里用 `"bearerToken": "!cat ~/.pi-secrets/mcp.token"` 引用 |
| 环境变量类 | shell 环境 | 配置里写 `${VAR}`，值放不进版本库 |

### 为什么 MCP token 用文件而不是系统钥匙串

Pi 的 MCP 适配器支持 `bearerTokenStore: true` 从 OS 钥匙串读 token，桌面上没问题，
但**无头服务器上没有 Secret Service**（gnome-keyring / KWallet），适配器在那种环境下是
**fail-closed 的，不会退回明文**，直接报：

```
Bearer token secure credential store unavailable.
Configure or unlock the OS credential store and retry.
```

而三种 token 来源（`bearerToken` 命令 / `bearerTokenEnv` / 钥匙串）是**互斥**的 ——
前两个一旦出现，钥匙串分支就不会走。所以同一份配置想同时跑在桌面和 VPS 上，
`!cat <文件>` 是唯一干净的选择：

- 配置文件里只有命令路径，没有密钥，可以安全入库/分享
- 文件缺失、为空或权限不对时会**明确报错**，不会静默 401
- 不依赖钥匙串、D-Bus 或 shell 环境变量

```json
"mcpServers": {
  "your-server": {
    "type": "sse",
    "url": "https://mcp.example.com/your-server",
    "auth": "bearer",
    "bearerToken": "!cat ~/.pi-secrets/mcp.token"
  }
}
```

## 个人配置的多设备复用（可选）

把个人值集中在 `~/.pi/pi-local.json`，安装脚本每次都会并入。支持三段：

```json
{
  "settings": {
    "defaultProvider": "my-gateway",
    "defaultModel": "your-model-id"
  },
  "providers": {
    "my-gateway": {
      "baseUrl": "https://api.example.com/v1",
      "api": "openai-completions",
      "models": [{ "id": "your-model-id" }]
    }
  },
  "mcpServers": {
    "my-server": {
      "type": "sse",
      "url": "https://mcp.example.com/your-server",
      "auth": "bearer",
      "bearerToken": "!cat ~/.pi-secrets/mcp.token"
    }
  }
}
```

- `providers` → 并入 `models.json`
- `mcpServers` → 并入 `mcp.json`
- `settings` → 浅覆盖 `settings.json` 的同名键（比如把默认模型设成你自建网关上的模型）

这样你可以在多台设备间复用自己的配置，而本仓库保持通用。

## 自己版本化配置（可选）

安装器不建立任何 git 跟踪关系。如果你想给自己的配置做版本控制：

```sh
cd ~/.pi/agent
git init
cp ~/.cache/my-pi/.gitignore .        # 模板自带的忽略规则，避免提交进个人配置
cp -r ~/.cache/my-pi/.githooks .      # 可选的提交前密钥扫描钩子
git config core.hooksPath .githooks
```

`.gitignore` 已排除 `models.json`、`mcp.json`、`auth.json`、`.pi-secrets/`、
记忆与会话目录等 —— 这些是泄露风险最高的东西。

## 更新与维护

```sh
# 拉取最新模板并应用（覆盖前自动备份）
sh -c "$(curl -fsSL https://raw.githubusercontent.com/DieRingedesSaturn/my-pi/master/install.sh)"
```

Pi 升级后建议重跑一次：主题探测补丁会被 Pi 的升级覆盖，脚本会重新打上。

## 已知问题

### 插件安装需要 `--allow-remote=all`

`pi-mcp-adapter` 依赖一个挂在 `pkg.pr.new` 上的预发布包（`@modelcontextprotocol/client`，
指向某个具体 commit 的 build）。npm 12 起默认 `allow-remote=none`，禁止
“把依赖直接写成一个 URL” 的包，不加 flag 会直接失败：

```
npm error Fetching packages of type "remote" have been disabled
npm error Refusing to fetch "@modelcontextprotocol/client@https://pkg.pr.new/..."
```

安装脚本已代为加上 `--allow-remote=all`。手动重跑时记得带上：

```sh
cd ~/.pi/agent/npm && npm install --allow-remote=all
```

如果你不接受从该 URL 拉包，把 `pi-mcp-adapter` 从 `settings.json` 的 `packages` 和
`npm/package.json` 的依赖里一并去掉即可 —— 它是 MCP 支持，不影响 Pi 本体。

## 环境要求

- Pi coding agent：https://pi.dev
- git
- node / npm（装插件）
- shell：POSIX `sh` 即可；交互式安装建议用 `sh -c "$(curl ...)"`

---

配置取自一个实际长期使用的环境，按需取舍即可 —— 不喜欢某个插件，删掉
`settings.json` 的 `packages` 条目和 `npm/package.json` 的依赖即可。
