# Windows 长期维护指南

长期维护分支为 `codex/windows-maintenance`，当前基线为 `0.9.4-windows.14`。本项目依赖 Codex/ChatGPT 客户端内部接口，客户端升级后需要按本文重新验证；未验证的版本不能直接标记兼容。

## 维护边界

- 使用桌面 **Codex Usage Card** 启动，保留用户原有商店和任务栏启动入口。
- 不增加重复开始菜单项，不为加载圆环强制退出或重启正在使用的客户端。
- 图标直接复制目标客户端自带的透明白色 `chatgpt-app-dark.ico`；不重新绘制、改色或添加背景。已有任务栏项只允许修改图标属性。
- 不修改客户端安装包、应用清单或签名，不开放非回环调试端口，不启用自动更新。
- 不提交或打包凭证、聊天内容、额度快照、本机安装清单、日志、临时文件或 Node 二进制。

## 当前兼容基线与来源

- Windows x64；客户端已验证版本：Microsoft Store `OpenAI.Codex 26.1027.3384.0`。
- 已验证实际额度读取、客户端内圆环、桌面启动、后台代理及透明白色图标。实际客户端验证日期为 2026-10-30。
- Node.js `24.14.1`；Windows PowerShell 5.1+；Python 3 用于打包和校验。运行程序不依赖 npm 第三方包。
- Windows x64 ZIP、运行时独立复制和回归测试于 2026-10-31 验证。其他电脑、其他客户端版本及 ARM64 尚未实际验证。
- 上游文档基线提交为 `f1cc976`，来源为 `Lorie7813/codex-usage-card`。
- 运行代码来源为上游 `v0.9.4-beta.1` Release 的可读 `agent.cjs`；原 ZIP SHA-256 为 `e41cbb00fd01b785eb0cac73a946115a35dd2d9a2410c196ec7287ce4b1737f8`。此公开上游仓库主要保存文档，单独更新 Git 文档不等于更新了运行代码。
- 最新 Windows 分发包的文件名、摘要和验证范围记录在 [Windows Release 记录](releases/windows-0.9.4-windows.14.json)。

## 从哪里定位问题

- `agent.cjs`：`resolveCodexBin` 查找客户端 CLI；`AppServerClient` 初始化 app-server 并读取 `account/rateLimits/read`；额度格式化处理账号窗口和通知；`RendererInjector` / `CdpSession` 连接本地调试接口；`installUsageBadge` 放置圆环、处理主题和过期数据。
- `windows/manage.ps1`：安装检测、Explorer 上下文安装、桌面/后台入口、启动参数、状态、卸载和自带 Node 的永久复制。运行目录放在用户 `.codex/addons`，避免 Store AppData 文件重定向。
- `windows/runner.cjs`：命名管道防重复实例、状态文件、停止请求和代理生命周期。
- `windows/doctor.cjs`：读取真实额度的最小诊断；不输出账号 ID、凭证或原始响应。
- `windows/icon.ps1`：读取官方图标，只修改桌面与匹配任务栏项的图标属性。
- `scripts/package_windows.py`：按明确文件清单生成 ZIP、安装/诊断/卸载命令、运行时及许可证、文件摘要。
- `tests/`：额度/账号切换/本地连接限制测试、真实浏览器渲染、已安装 Windows 入口和自带运行时测试。

## 客户端升级后如何排查

1. 记录客户端版本、插件版本、Node 版本、复现方式，以及是否从桌面 **Codex Usage Card** 启动。不要收集聊天内容或凭证。
2. 运行 `node manage.cjs status` 和 `node manage.cjs doctor`，查看已清理个人路径的状态。
3. `waiting-for-codex-debug-port`：先检查新客户端是否接受启动参数，以及是否已有不带端口的旧实例；不要反复重装或强制终止现有会话。
4. app-server 读取失败：检查 CLI 新位置、`initialize` 参数、RPC 方法和额度响应结构。一次真实额度探测只在必要时执行，不扫描会话数据。
5. 已连接但圆环不显示：检查主窗口 URL 判定、导航栏 `nav[data-app-navigation-rail]`、页脚位置和主题。不要把“WebSocket 已连上”当作“圆环已正确显示”。
6. 图标失败：检查目标版本是否仍提供官方资源路径，禁止用自行拼色图案代替后声称官方原图。
7. 安装或桌面启动失败：核对真实物理路径、Explorer 与 Store 进程是否看到同一文件、自带 Node 是否落在永久目录，以及快捷方式中的参数引号。

## 修改与验证

从维护分支创建一个处理具体问题的分支，例如 `codex/windows-fix-navigation-rail`。保持一个兼容性问题对应一组可审阅修改。

普通代码回归：

```powershell
npm test
npm run test:browser
git diff --check
```

`npm test` 中 Windows CLI 发现测试需要这台电脑已安装客户端；浏览器测试需要 Chrome 或 Edge。没有客户端的通用 CI 不能代替实际兼容性验证。

涉及安装和后台生命周期时，在专用测试用户或已准备好的测试机器上运行：

```powershell
npm run test:windows
```

这个检查会停止并重新启动插件代理，但不会重启客户端。它还会核对开始菜单重复项、任务栏启动目标，以及 `GetFinalPathNameByHandle` 返回的真实路径。不要在无关用户环境中运行一次性的旧入口清理脚本。

涉及打包时，解压新 ZIP 后运行：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File tests/bundled-runtime.ps1 -PackageRoot "解压后的包目录" -TestRoot "独立的测试目录"
```

最后在目标版本客户端中人工确认：圆环实际可见、额度与账号一致、重置提示可读、主题正确、异常时不保留旧百分比、已有会话不被关闭。将日期和客户端版本写入兼容记录。

## 发版与交付

1. 同步更新 `package.json`、`agent.cjs` 的 `AGENT_VERSION`、`windows/manage.ps1` 的安装版本，以及 README、Windows 文档与 Changelog。
2. 检查选用的 x64 Node 签名有效、版本至少为 24、同目录有完整 `LICENSE`。更换 Node 时记录新版本并重新验证。
3. 执行 `python scripts/package_windows.py --node "已验证的 node.exe 路径"`。
4. 核对 ZIP CRC、`FILES.sha256`、ZIP 外部摘要与文件清单；确认没有用户数据、本机路径或旧运行状态。运行解压包的 Node 和上述测试。
5. 新增 `docs/releases/windows-<插件版本>.json`，记录客户端验证范围、日期、运行时和 ZIP 摘要。一个已交付版本的安装包发生变化时，应更新插件版本，而不是悄悄替换相同版本。
6. 提交源码、测试、文档和 Release 元数据。`dist/` 和下载包保持忽略；需要对外分发时将 ZIP 与校验文件放到 Release 附件或独立分发位置。

上游新 Release 的运行文件应从其已核验的归档中取得，再与本分支的 Windows 改动比较。不要直接覆盖已验证的适配，也不要把文档仓库的无冲突合并视为功能验证。

当前本机选择使用启动后图标同步：启动时可能短暂显示客户端灰色图标，随后应用官方透明白色 logo。窗口和桌面额度入口使用 CodexUsageCard.Windows 分组，窗口重启命令复用既有桌面额度启动命令。不会修改官方程序或签名，不新增开始菜单入口；原始固定项仅在明确属于额度入口时关联额度分组。完整退出重开已由用户观察到灰色随后白色；此行为于 2026-10-31 获用户接受。

windows.12 将桌面、后台启动及额度任务栏重启入口统一为 wscript.exe 隐藏入口，并为图标助手启用 CreateNoWindow，避免命令行窗口闪现。图标同步方式和额度功能保持不变。

windows.13 / UI 54 增加原生侧边栏控件避让：额度卡仍在文档流中，空间不足或与原生按钮重叠时暂时隐藏，空间恢复后显示。新增真实浏览器回归覆盖更新按钮动态出现、独立按钮、绝对定位、样式/hidden 变化、短导航栏、单/双圆环切换和滚动裁剪。2026-11-04 核对本机客户端 26.1029.7803.0 导航结构；未触发真实客户端更新流程。现有分发 ZIP 的历史记录仍为 windows.12，本次先更新本机源码安装。

windows.14 / UI 55 增加本地重置时分/月日标签。来源：NANAiiiii/codex-usage-card Windows 分支提交 `60cfd75eacc07bf2bdeeafb761570dbfea4f8495`，MIT 许可；保留项目原版权及许可证。回归覆盖上海/洛杉矶跨日、UTC 午夜、纽约夏令时切换、无效及过期数据清理与恢复，以及新增标签后的原生按钮避让。历史分发 ZIP 仍为 windows.12，本次更新本机源码安装。

2026-11-04 已生成 windows.14 x64 分发 ZIP，包含签名有效的 Node.js 24.14.1 和完整许可证。ZIP CRC、17 项文件摘要、源码一致性、解压后执行以及中文/空格路径下的运行时永久复制测试通过。安装包入口为 Install.cmd，仍使用桌面 Codex Usage Card 启动；其他电脑的实际安装尚待验证。
