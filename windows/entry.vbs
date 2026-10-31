Option Explicit
Dim shell, fso, script, action, command
Set shell = CreateObject("WScript.Shell")
Set fso = CreateObject("Scripting.FileSystemObject")
script = fso.BuildPath(fso.GetParentFolderName(WScript.ScriptFullName), "manage.ps1")
action = "launch"
If WScript.Arguments.Count > 0 Then action = WScript.Arguments(0)
If action = "agent" Then action = "start"
If action <> "start" And action <> "launch" Then WScript.Quit 1
command = """" & shell.ExpandEnvironmentStrings("%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe") & """ -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File """ & script & """ -Action " & action & " -FromShortcut"
WScript.Quit shell.Run(command, 0, True)
