"""Build an allowlisted Windows ZIP, never copy a user's installed profile."""
from __future__ import annotations

import argparse
import hashlib
import json
import struct
import subprocess
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
VERSION = json.loads((ROOT / "package.json").read_text(encoding="utf-8"))["version"]
PRODUCT = f"CodexUsageCard-Windows-{VERSION}-x64"
FILES = [
    "LICENSE", "agent.cjs", "manage.cjs", "windows/manage.ps1",
    "windows/runner.cjs", "windows/doctor.cjs", "windows/icon.ps1", "windows/entry.vbs",
    "windows/window-icon.ps1", "windows/WindowIconGuard.cs",
]
README = """Codex Usage Card — Windows 安装包
版本：{version}（Windows x64）

这是当前 Windows 适配版的可复制安装包，包含 Node.js {node_version} 运行时。
无需另外安装 Node.js 或执行 npm install。仅支持 Windows 10/11 x64；其他架构未验证。

安装方法
1. 在另一台电脑安装 Codex/ChatGPT Windows 桌面客户端，并使用那台电脑自己的账号登录。
   当前适配主要针对 Microsoft Store 的 OpenAI.Codex 客户端。
2. 将本 ZIP 完整解压到一个普通文件夹，不要直接在压缩包里运行。
3. 双击 Install.cmd，看到 Installation completed 后关闭窗口。无需管理员权限。
4. 保存工作并完全退出 Codex，包括系统托盘中的实例。
5. 双击桌面 Codex Usage Card，等待约 5–15 秒显示额度圆环。

使用说明
- 仍须使用桌面 Codex Usage Card 启动；不支持从任意原始入口启动后自动加载。
- 只添加这个桌面入口及隐藏的后台登录启动项，不添加重复开始菜单入口，不替换任务栏启动方式。
- 图标直接使用目标电脑客户端自带的透明白色官方图标，不重绘、不改色。
- 本版会同步实际运行窗口的大小图标和任务栏图标，不依赖已固定的 .lnk 文件。
  图标助手只作用于通过额度入口打开的客户端，随插件代理或客户端退出而停止。
- windows.8 已撤销 windows.7 的官方应用 ID 绑定，图标助手不修改应用 ID 或重启命令。
  若使用 windows.7 固定后启动不显示额度：取消旧固定项，再右键桌面 Codex Usage Card 重新固定一次。
  安装器不会擅自把原来的官方固定项改成额度入口；Diagnose.cmd 会显示固定项实际走哪条启动路线。
- 运行文件和自带 Node 会复制到 %USERPROFILE%\\.codex\\addons\\codex-usage-card。
  安装成功后可以移动或删除解压目录，不会依赖解压目录中的 Node 路径。
- 不修改客户端安装包或签名。无需复制原电脑的 .codex 目录、auth.json 或任何账号文件。
- 不含当前电脑的登录凭证、聊天记录、运行日志或额度快照。

诊断与卸载
- 双击 Diagnose.cmd：查看插件状态并读取一次额度。分享诊断输出前删去个人路径。
- 双击 Uninstall.cmd：卸载额度插件，不卸载 Codex。
  卸载后完全退出 Codex，再从原入口打开，可以关闭本地调试端口。

连接与兼容性
- 使用本机回环 CDP 端口 39222，该接口可以执行窗口脚本。不要转发或对外开放此端口。
- 这是非官方适配，依赖客户端内部接口，客户端更新后可能需要更新适配。
- 此包已在当前电脑验证打包完整性、运行时和回归测试；尚未在你的另一台电脑上实际安装验证。
- 当前已验证客户端版本：26.1027.3384.0。

项目来源：https://github.com/Lorie7813/codex-usage-card
保留项目 MIT 许可证；Node.js 许可证与第三方许可见 runtime\\LICENSE。
包内文件摘要见 FILES.sha256；ZIP 摘要见随包提供的 .sha256 文件。
"""


def launcher(action: str) -> bytes:
    text = f'''@echo off
setlocal
cd /d "%~dp0"
if not exist "%~dp0runtime\\node.exe" (
  echo ERROR: Bundled Node.js is missing. Fully extract the ZIP first.
  pause
  exit /b 1
)
"%~dp0runtime\\node.exe" "%~dp0manage.cjs" {action}
set "RESULT=%ERRORLEVEL%"
if not "%RESULT%"=="0" (
  echo.
  echo Operation failed. Read the message above.
) else (
  echo.
  echo {dict(install='Installation completed. Use the desktop Codex Usage Card shortcut.', uninstall='Uninstall completed.', doctor='Diagnosis completed.')[action]}
)
pause
exit /b %RESULT%
'''
    return text.replace("\n", "\r\n").encode("ascii")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--node", type=Path, required=True)
    args = parser.parse_args()
    node = args.node.resolve(strict=True)
    node_license = node.parent / "LICENSE"
    if not node_license.is_file():
        raise SystemExit("The complete Node.js LICENSE is required beside node.exe.")
    raw = node.read_bytes()
    pe = struct.unpack_from("<I", raw, 0x3C)[0]
    if raw[:2] != b"MZ" or raw[pe:pe + 4] != b"PE\0\0" or struct.unpack_from("<H", raw, pe + 4)[0] != 0x8664:
        raise SystemExit("Only the Windows x64 Node executable can be packaged.")
    node_version = subprocess.check_output([str(node), "--version"], text=True).strip()
    if int(node_version.removeprefix("v").split(".")[0]) < 24:
        raise SystemExit("Node.js 24+ is required.")
    payload = {name: (ROOT / name).read_bytes() for name in FILES}
    payload.update({
        "runtime/node.exe": raw,
        "runtime/LICENSE": node_license.read_bytes(),
        "Install.cmd": launcher("install"),
        "Uninstall.cmd": launcher("uninstall"),
        "Diagnose.cmd": launcher("doctor"),
        "README-安装说明.txt": README.format(version=VERSION, node_version=node_version).encode("utf-8"),
        "release.json": (json.dumps({
            "product": "Codex Usage Card", "version": VERSION,
            "platform": "windows", "architecture": "x64", "node": node_version,
            "upstream": "https://github.com/Lorie7813/codex-usage-card",
            "upstream_release": "v0.9.4-beta.1",
            "entry_mode": "desktop-launcher", "includes_user_data": False,
        }, ensure_ascii=False, indent=2) + "\n").encode("utf-8"),
    })
    payload["FILES.sha256"] = "".join(
        f"{hashlib.sha256(content).hexdigest()}  {name}\n"
        for name, content in sorted(payload.items())
    ).encode("utf-8")
    destination = ROOT / "dist"
    destination.mkdir(exist_ok=True)
    archive = destination / (PRODUCT + ".zip")
    with zipfile.ZipFile(archive, "w", zipfile.ZIP_DEFLATED, compresslevel=9) as output:
        for name, content in sorted(payload.items()):
            output.writestr(f"{PRODUCT}/{name}", content)
    with zipfile.ZipFile(archive) as check:
        if check.testzip() is not None:
            raise SystemExit("ZIP integrity check failed.")
        actual = {entry.removeprefix(PRODUCT + "/") for entry in check.namelist()}
        if actual != set(payload):
            raise SystemExit("Unexpected archive entries.")
        for name, expected in payload.items():
            if check.read(PRODUCT + "/" + name) != expected:
                raise SystemExit("Archive byte mismatch: " + name)
    digest = hashlib.sha256(archive.read_bytes()).hexdigest()
    (destination / (PRODUCT + ".zip.sha256")).write_text(
        digest + "  " + archive.name + "\n", encoding="utf-8", newline="\n")
    (destination / "README-安装说明.txt").write_bytes(payload["README-安装说明.txt"])
    print(json.dumps({"archive": str(archive), "bytes": archive.stat().st_size,
                      "files": len(payload), "sha256": digest,
                      "node": node_version}, ensure_ascii=False))


if __name__ == "__main__":
    main()
