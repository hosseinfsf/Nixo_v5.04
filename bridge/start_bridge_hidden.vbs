Set shell = CreateObject("WScript.Shell")
Set fso = CreateObject("Scripting.FileSystemObject")

base = fso.GetParentFolderName(WScript.ScriptFullName)
python = base & "\.venv\Scripts\python.exe"
script = base & "\signal_bridge.py"

If Not fso.FileExists(python) Or Not fso.FileExists(script) Then WScript.Quit 1

shell.CurrentDirectory = base

Do While True
	exitCode = shell.Run(Chr(34) & python & Chr(34) & " " & Chr(34) & script & Chr(34), 0, True)
	WScript.Sleep 30000
Loop