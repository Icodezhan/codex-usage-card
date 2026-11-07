# Windows 安装与使用

这是基于上游 v0.9.4 Beta 的本地 Windows 适配版 `0.9.4-windows.14`，不是上游发布的 Windows Release，也不是 OpenAI 官方插件。

## 环境与安装

需要 Windows 10/11、Windows PowerShell 5.1+，以及已经登录的 Codex 桌面客户端。Windows x64 安装 ZIP 已包含签名有效的 Node.js 24.14.1 及完整许可证，无需另外安装 Node。完整解压后运行 `Install.cmd`；诊断和卸载分别运行 `Diagnose.cmd`、`Uninstall.cmd`。自带运行时会复制到永久安装目录，安装成功后可以移动解压目录。源码方式安装仍需自行准备 Node.js 24+。

自动识别当前用户的 Microsoft Store `OpenAI.Codex` 安装；其他安装方式可通过 `CODEX_BADGE_APP` 指定客户端 exe 的完整路径。安装包不包含任何当前用户的登录信息、聊天数据、运行日志或安装状态。构建方法：`python scripts/package_windows.py --node <已验证的官方 x64 node.exe>`，Node 的完整 LICENSE 须与 node.exe 位于同一目录。

在项目目录运行：

```powershell
node manage.cjs install
```

安装到当前用户的 `%USERPROFILE%\.codex\addons\codex-usage-card`，只创建桌面的 **Codex Usage Card** 启动入口，并在当前用户的 Startup 文件夹注册隐藏后台代理。不会增加开始菜单入口或改变任务栏的启动目标与参数。无需管理员权限。Node 路径记录在安装清单中；源码方式安装若删除或移动所用 Node，重新执行安装即可。

早期 Windows 适配在 Codex 商店版进程内写入 AppData 时，实际被重定向到应用的 `LocalCache` 隔离目录；应用内测试能看到文件，桌面启动却找不到。当前版本将运行文件放在 AppData 以外，并经 Explorer 在真实桌面进程环境中完成安装。回归测试使用 `GetFinalPathNameByHandle` 检查运行文件及快捷方式的实际物理路径，避免把应用内可见误当作系统可见。这符合 [Microsoft 的 MSIX 文件虚拟化说明](https://learn.microsoft.com/en-us/windows/msix/desktop/flexible-virtualization)。不修改应用清单、签名或系统安全配置。

安装器使用 `-ExecutionPolicy Bypass` 仅运行本次 PowerShell 子进程，不修改系统或用户的持久执行策略。快捷方式由无控制台的 Windows Script Host 调用入口脚本，以隐藏方式创建 PowerShell，避免 PowerShell 运行到隐藏参数前闪出窗口。图标助手使用 CreateNoWindow 创建。安装时校验保存后的快捷方式目标和脚本路径，旧版 WSH 入口会自动迁移。启动失败时弹出具体错误，并在安装目录写入 `launcher-error.log`。

桌面和已有任务栏图标统一使用客户端自带的透明背景白色 `chatgpt-app-dark.ico`，按原始字节复制，不重绘、不改色、不添加背景。任务栏仅修改图标属性，保留原始启动目标和参数。卸载时图标路径恢复到客户端自己的资源文件。

## 首次启用及后续启动

1. 保存当前工作，并从 Codex 托盘菜单完全退出应用。仅关闭窗口可能仍保留后台主进程。
2. 打开桌面的 **Codex Usage Card** 快捷方式；也可在项目目录运行 `node manage.cjs launch`。
3. 等待约 5–15 秒，圆环会在可见导航栏底部出现。悬停或键盘聚焦显示重置时间。

该入口会解析最新安装的客户端位置，使用 `--remote-debugging-address=127.0.0.1 --remote-debugging-port=39222` 启动原始 exe。Windows 版不会自动终止、重启已有会话；若当前实例没有该端口，启动器会要求先完全退出。

## 原始启动入口

当前实现依赖启动时开启的本地 CDP 接口。后台代理只能连接已有接口，不能让一个没有该接口的运行实例自动显示圆环。因此本版仍须使用桌面 **Codex Usage Card** 启动，不声称支持“任意入口自动加载”。不修改原始商店入口、应用包或签名，也不会为了显示圆环而自动关闭已有会话。

此前的任务栏替换方案已撤回。新增的普通 **Codex** 桌面/开始菜单项和重复的 **ChatGPT** 文件快捷方式已清理，原始注册的 ChatGPT 商店应用保留。任务栏恢复直接启动原始程序，无调试参数。退役启动器文件保存在安装目录下 `entrypoint-backups`，不再被任何活动入口调用。

用户登录 Windows 时，后台代理会自动启动。它每 5 秒检查可连接的 Codex 主窗口，连接后约每 60 秒刷新额度；没有客户端窗口时不保持额外 app-server。代理通过系统命名管道防止重复运行。配额数据过期后会显示不可用，避免保留旧的正常百分比。

## 诊断、停止和卸载

```powershell
node manage.cjs status
node manage.cjs doctor
node manage.cjs stop
node manage.cjs uninstall
```

`status` 显示代理、登录启动项、本地端口和连接状态。`waiting-for-codex-debug-port` 表示代理已就绪，客户端需要从上述快捷方式重新启动。`doctor` 另外使用现有登录环境读取一次真实额度，仅输出百分比，不输出凭证、账号 ID 或原始响应。诊断输出仍包含本地路径，分享前请删去个人信息。

`stop` 停止额度代理，不关闭 Codex。重新打开快捷方式或重新安装可启动代理。`uninstall` 校验安装归属和绝对路径后，仅删除本插件目录及归属明确的快捷方式。卸载后完全退出 Codex，再使用原始入口启动，可关闭调试端口。

代理日志位于安装目录的 `agent.log` / `agent-error.log`。启动器另外记录 `launcher.log`：是否进入启动器、代理是否就绪、请求启动的进程 ID、实际主窗口与调试连接是否可用。启动器会等待约 20 秒验证本地接口；失败会弹出具体错误并写日志，不再仅凭 Start-Process 返回就报告启动成功。客户端或侧栏内部结构变更后，可能需要更新适配。后台状态显示连接不代表圆环一定可见；隐藏导航栏时不会强行插入其他区域。

## 本地调试端口

CDP 调试端口可以执行客户端窗口中的 JavaScript，权限高于单纯的额度查询。它不具备本地身份认证，切勿转发或对外开放 `39222`。启动器指定回环地址，诊断会检查实际监听地址；代理只接受配置端口上的回环 WebSocket，拒绝其他主机、端口、凭证及 HTTP 重定向。

不读取聊天数据库或扫描项目，不把额度发送到额外服务器，不修改 Codex 应用包或签名，不启用自动更新。原始 Codex CLI 在读取额度时仍可能向 OpenAI 发出自身的已认证请求。

## 来源与验证范围

`agent.cjs` 来自 `Lorie7813/codex-usage-card` 的 `v0.9.4-beta.1` Release，资产名 `CodexUsageCard-macOS-0.9.4.zip`。下载字节与仓库独立公布的 SHA-256 `e41cbb00fd01b785eb0cac73a946115a35dd2d9a2410c196ec7287ce4b1737f8` 一致；保留原始 MIT 许可证。新增 Windows 管理代码不执行原包里的 macOS 安装器、原生 bridge 或 updater。

本机验证环境：Codex Windows Store 版本 `26.1027.3384.0`、Node `24.14.1`。已验证真实额度读取、实际客户端显示、Chromium 中的圆环放置/双额度/过期/销毁、代理生命周期及安装卸载。分发 ZIP 已验证完整性、运行时签名、复制到独立永久目录及回归测试；其他电脑和其他客户端版本尚未实际验证。

开发检查：

```powershell
npm test
npm run test:browser
npm run test:windows
```

运行时只依赖 Node 自带模块和 Windows 组件，无需 `npm install`。浏览器测试使用本机 Chrome 或 Edge；`EDGE_BIN` 可覆盖浏览器路径。原始 macOS 发行和校验流程保持在上游文档与 Release 中。

后续客户端更新后的维护流程见 [Windows 维护指南](windows-maintenance.md)。

当前本机选择使用启动后图标同步：启动时可能短暂显示客户端灰色图标，随后应用官方透明白色 logo。窗口和桌面额度入口使用 CodexUsageCard.Windows 分组，窗口重启命令复用既有桌面额度启动命令。不会修改官方程序或签名，不新增开始菜单入口；原始固定项仅在明确属于额度入口时关联额度分组。完整退出重开已由用户观察到灰色随后白色；此行为于 2026-10-31 获用户接受。

## 侧边栏更新按钮避让（windows.13）

额度卡保留在原生底部区域之前，更新、用量、个人资料按钮继续使用客户端自己的布局。没有更新按钮时不额外预留空白；只根据实际存在的控件测量空间。检测到卡片与原生按钮重叠、底部区域超出可见范围，或导航列表不足一行时，额度卡暂时隐藏；空间恢复后自动显示。支持按钮动态出现、样式/显隐变化和窗口缩放，不改动原生按钮或更新行为。

2026-11-04 在本机 `OpenAI.Codex 26.1029.7803.0` 核对导航栏结构，并以真实 Chromium 模拟更新按钮和小窗口进行回归。当前客户端没有显示待更新按钮，因此没有执行实际更新安装流程。

## 重置时间标签（windows.14）

在五小时额度下显示本地 24 小时时分（例如 `18:30`），在周额度下显示补零的月日（例如 `11-10`）。读取真实重置时间戳，按电脑本地时区换算，不固定为北京时间；悬停详情继续显示完整月日和时分。缺失、无效、读取失败或过期数据的标签显示 `—`，恢复有效数据后自动刷新。

参考 [NANAiiiii/codex-usage-card Windows 0.1.4](https://github.com/NANAiiiii/codex-usage-card/tree/60cfd75eacc07bf2bdeeafb761570dbfea4f8495/windows) 的 MIT 实现与淡底标签样式。双圆环卡片增高以容纳标签，继续沿用原生更新按钮避让，不为尚未出现的更新按钮预留空白。
