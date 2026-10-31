Option Explicit
Dim shell, fso, root, script, action, command, result
Set shell = CreateObject("WScript.Shell")
Set fso = CreateObject("Scripting.FileSystemObject")
root = fso.GetParentFolderName(WScript.ScriptFullName)
script = fso.BuildPath(root, "manage.ps1")
action = "launch"
If WScript.Arguments.Count > 0 Then action = WScript.Arguments(0)
If action = "agent" Then action = "start"
If action <> "start" And action <> "launch" Then WScript.Quit 1
command = "powershell.exe -NoProfile -ExecutionPolicy Bypass -File """ & script & """ -Action " & action
result = shell.Run(command, 0, True)
If result <> 0 And action = "launch" Then
    MsgBox "Codex Usage Card could not launch. If Codex is open, fully quit it (including the tray icon), then try this shortcut again. For details, run: node manage.cjs status", 48, "Codex Usage Card"
End If
WScript.Quit result
