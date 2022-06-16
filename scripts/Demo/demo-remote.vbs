Option Explicit

Function usage()
	Wscript.Echo("Usage:cscript demo-remote.vbs /tinput:OptionValue /tjson:JsonString")
	Wscript.Echo("")
	Wscript.Echo("/tinput: Option value")
	Wscript.Echo("/tjson: Json string")
	Wscript.Echo("")
	Wscript.Echo("Example:cscript install.vbs /tinput:TestValue1 /tjson:""{""test"":7878}""")
	WScript.Quit(1)
End Function

'Anonymouse arguments begins at 0
'arg0 = WScript.Arguments(0)
'arg1 = WScript.Arguments(1)

'Named arguments

Dim colArgs
Set colArgs = WScript.Arguments.Named

Dim tinput
If colArgs.Exists("tinput") Then
	tinput = colArgs.Item("tinput")
End If

Dim tjson
If colArgs.Exists("tjson") Then
	tjson = colArgs.Item("tjson")
End If

Dim wshShell
Set wshShell = WScript.CreateObject("WScript.Shell")
Dim tempPath
tempPath = wshShell.ExpandEnvironmentStrings("%TEMP%")

Wscript.Echo("Get option values:")
Wscript.Echo(tinput)
Wscript.Echo(tjson)
Wscript.Echo("Temp directory:" & tempPath)
Dim errCode

'Write output.json file
Set outStream = CreateObject("ADODB.Stream")
outStream.Open
outStream.Type     = 2 'text
outStream.Position = 0
outStream.Charset  = "utf-8"

outStream.WriteText "{\n"
outStream.WriteText """outtext"":""" & tempPath & """\n"
outStream.WriteText "}\n"

outStream.SaveToFile "output.json", 2
outStream.Close
outStream = nothing


'Do some job and return error code
errCode = wshShell.Run("dir c:\", , True)
If errCode <> 0 Then
	Wscript.Echo("ERROR: Do some job failed.")
	WScript.Quit(1)
Else
	 Wscript.Echo("INFO: Do some job success.")
     WScript.Quit(0)
End If