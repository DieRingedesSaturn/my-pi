#!/usr/bin/env node
/**
 * prefer-terminal-background-theme.mjs — pi-config 补丁
 *
 * 目的
 *   让 pi 的自动主题检测以「终端实际背景色」(OSC 11) 为准，而不是终端自称的
 *   明暗（DSR: CSI ? 996 n → CSI ? 997 ; 1|2 n）。
 *
 * 为什么
 *   Ghostty 对 CSI ? 996 n 的回答取自 macOS 系统外观
 *   (NSApplication.effectiveAppearance)，而不是终端渲染出来的背景色。
 *   于是「系统浅色 + 终端暗色」时 pi 会加载浅色主题，暗色终端下的工具框
 *   就变成米黄 / 淡绿 / 淡粉（上游 issue #7770，closed as not planned）。
 *
 * 参考
 *   openai/codex `codex-rs/tui/src/terminal_probe.rs`：只用 OSC 10/11 探测
 *   真实默认前景 / 背景色，从不使用 DSR 明暗回报。
 *
 * 补丁内容
 *   detectTerminalThemeForAuto 的优先级改为：
 *     OSC 11 背景色 → DSR 明暗回报 → "dark"
 *   （原实现是 DSR 优先，OSC 11 只在 DSR 无响应时才用）
 *
 * 幂等
 *   已打过补丁 → 跳过；目标代码结构变化（通常意味着 pi 升级）→ 显式失败
 *   并以非零状态退出，不会静默失效。
 *
 * 用法
 *   node prefer-terminal-background-theme.mjs
 *   pi-setup.sh 会自动调用；pi 升级后重新跑一次 setup 即可。
 */
import { spawnSync } from "node:child_process";
import fs from "node:fs";
import path from "node:path";

const MARKER = "/* pi-config:prefer-terminal-background */";

// pi 0.85.x 打包产物中的原始实现（dist/bundle/chunks/chunk-*.js，压缩过但未混淆）
const ORIGINAL =
    "async function detectTerminalThemeForAuto({ui,timeoutMs,env:env2}){let colorSchemePromise;try{colorSchemePromise=ui.queryTerminalColorScheme?.({timeoutMs})}catch{}let backgroundThemePromise=detectTerminalBackgroundTheme({ui,timeoutMs,env:env2});try{let colorScheme=await colorSchemePromise;if(colorScheme)return colorScheme}catch{}return(await backgroundThemePromise).theme}";

// 补丁后：先取 OSC 11 背景色结果，拿不到时才回落到 DSR 明暗回报
const PATCHED =
    "async function detectTerminalThemeForAuto({ui,timeoutMs,env:env2}){" +
    MARKER +
    "let colorSchemePromise;try{colorSchemePromise=ui.queryTerminalColorScheme?.({timeoutMs})}catch{}let backgroundThemePromise=detectTerminalBackgroundTheme({ui,timeoutMs,env:env2});let backgroundTheme;try{backgroundTheme=(await backgroundThemePromise).theme}catch{}if(backgroundTheme)return backgroundTheme;try{let colorScheme=await colorSchemePromise;if(colorScheme)return colorScheme}catch{}return\"dark\"}";

function log(msg) {
    process.stdout.write(`${msg}\n`);
}

function fail(msg) {
    process.stderr.write(`❌ ${msg}\n`);
    process.exit(1);
}

function findPackageDir() {
    const candidates = [];
    if (process.env.PI_PACKAGE_DIR) candidates.push(process.env.PI_PACKAGE_DIR);

    const which = spawnSync("which", ["pi"], { encoding: "utf8" });
    if (which.status === 0 && which.stdout.trim()) {
        try {
            const real = fs.realpathSync(which.stdout.trim());
            // <pkg>/dist/bundle/cli.js → <pkg>
            candidates.push(path.resolve(path.dirname(real), "../.."));
        } catch {
            /* 忽略：继续尝试其它候选路径 */
        }
    }

    const npmRoot = spawnSync("npm", ["root", "-g"], { encoding: "utf8" });
    if (npmRoot.status === 0 && npmRoot.stdout.trim()) {
        candidates.push(path.join(npmRoot.stdout.trim(), "@earendil-works", "pi-coding-agent"));
    }

    if (process.env.HOME) {
        candidates.push(path.join(process.env.HOME, ".npm/lib/node_modules/@earendil-works/pi-coding-agent"));
    }

    for (const dir of candidates) {
        if (dir && fs.existsSync(path.join(dir, "dist", "bundle", "chunks"))) return dir;
    }
    return undefined;
}

function readPiVersion(pkgDir) {
    try {
        return JSON.parse(fs.readFileSync(path.join(pkgDir, "package.json"), "utf8")).version;
    } catch {
        return "unknown";
    }
}

function main() {
    const pkgDir = findPackageDir();
    if (!pkgDir) fail("找不到 pi 安装目录（可设置 PI_PACKAGE_DIR 后重试）");

    const chunksDir = path.join(pkgDir, "dist", "bundle", "chunks");
    const version = readPiVersion(pkgDir);
    log(`pi ${version} @ ${pkgDir}`);

    const files = fs
        .readdirSync(chunksDir)
        .filter((name) => name.endsWith(".js"))
        .map((name) => path.join(chunksDir, name))
        .filter((file) => fs.readFileSync(file, "utf8").includes("detectTerminalThemeForAuto"));

    if (files.length === 0) {
        fail(
            "在 bundle 里找不到 detectTerminalThemeForAuto。\n" +
                "   可能 pi 已重构主题检测（或上游已修复该问题）。\n" +
                "   请检查后再决定是否还保留 pi-setup.sh 中的补丁步骤。",
        );
    }

    let patched = 0;
    let already = 0;

    for (const file of files) {
        const source = fs.readFileSync(file, "utf8");
        if (source.includes(MARKER)) {
            already += 1;
            continue;
        }

        const hits = source.split(ORIGINAL).length - 1;
        if (hits !== 1) {
            fail(
                `目标代码结构与预期不符（${path.basename(file)} 中匹配到 ${hits} 处）。\n` +
                    "   pi 可能升级改动了实现，请更新 patches/prefer-terminal-background-theme.mjs。",
            );
        }

        const tmp = path.join(path.dirname(file), `.${path.basename(file)}.pi-config-tmp.mjs`);
        fs.writeFileSync(tmp, source.replace(ORIGINAL, PATCHED));
        const check = spawnSync(process.execPath, ["--check", tmp], { encoding: "utf8" });
        if (check.status !== 0) {
            fs.rmSync(tmp, { force: true });
            fail(`补丁后语法校验失败：\n${check.stderr || check.stdout}`);
        }
        fs.renameSync(tmp, file);

        const verify = fs.readFileSync(file, "utf8");
        if (!verify.includes(MARKER) || verify.includes(ORIGINAL)) {
            fail(`补丁写入后校验失败：${file}`);
        }
        patched += 1;
    }

    if (patched > 0) {
        log(`✅ 已应用补丁（${patched} 个文件）：OSC 11 真实背景色优先，DSR 仅作后备`);
    }
    if (already > 0) {
        log(`✅ 已是最新（${already} 个文件已是补丁版本），无需操作`);
    }
}

main();
