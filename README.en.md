[中文](README.md) / English
<p align="left">
    <a href="https://opensource.org/licenses/Apache-2.0" alt="License">
        <img src="https://img.shields.io/badge/License-Apache%202.0-blue.svg" /></a>
<a target="_blank" href="https://join.slack.com/t/neatlogichome/shared_invite/zt-1w037axf8-r_i2y4pPQ1Z8FxOkAbb64w">
<img src="https://img.shields.io/badge/Slack-Neatlogic-orange" /></a>
</p>

---

## About

This project is used to manage all customized scripts, updating irregularly.

## Usage

### After installing python3 on Linux, change python3 to be the default python execution program

Execute the bin/setup.sh in the autoscripts directory to switch python3 to be the default python

```shell
cd autoscripts
./setup.sh
```

### Install python3 third-party libraries

```
cd autoscripts/media
./ins-modules.sh

###or manually install via pip3
pip3 install requests filelock ijson
```

### Upgrade python3 third-party libraries

```
cd autoscripts/media
./upgrade-modules.sh
```

### Reinstall individual module examples

```
cd autoscripts/media
./ins-modules.sh requests ijson
./upgrade-modules.sh requests ijson
```

### Environment variable initialization

```
cd autoscripts
source bin/setenv.sh
```

### Script import and export

```
#export scripts to the scripts directory
python3 bin/export.py

#import scripts to the system
python3 bin/import.py
```

### Windows scripts

Different parsers for Windows scripts have different requirements for parameter formats
Set encoding (UTF-8) for cmd.exe: mode con cp select=1250
Set encoding (GBK) for cmd.exe: mode con cp select=936

### Parameter format of different types of Windows scripts

The parameter format and handling methods of different types of Windows scripts are different

#### Note: VBScript cannot handle parameters with double quotes in the parameter values, and does not support complex parameters

#### Note: bat scripts cannot handle named parameters, and for parameters with spaces, the double quotes before and after will be carried

bat script:

```
@echo off
echo Param1 = %1
echo Param2 = %2
echo Param3 = %3
```

Test:

```
>ShowParams.bat "c:\test a\" "c:\test b\"
param 1 = "c:\test a\"
param 2 = "c:\test b\"
```

vbscript:

```vbscript
If Wscript.Arguments.Count = 0 Then
        Wscript.echo "No parameters found"
Else
    i=0
        Do until i = Wscript.Arguments.Count
        Parms = Parms & "Param " & i & " = " & Wscript.Arguments(i) & " " & vbcr
        i = i+1
        loop
        Wscript.echo parms
End If
```

Test:

```
>ShowParams.vbs "c:\test a\" "c:\test b\"
param 0 = c:\test a\
param 1 = c:\test b\
```

powershell:

```powershell
#Get arguments by array $args, $args[0], $args[1]
write-host("There are a total of $($args.count) arguments")
for ( $i = 0; $i -lt $args.count; $i++ ) 
{
    write-host("Argument  $i is $($args

[$i])")
} 
```

Test:

```
>powershell -f ShowParams.ps1 "c:\test a\" "c:\test b\"
param 0 = c:\test a" c:\test
param 1 = b"
```

VC

```c
#include "stdafx.h"
int main(int argc, char* argv[])
{
  for (int i = 0; i < argc; ++i)
  {
    printf("param %d = ",i);
    puts(argv[i]);
    printf("\n");
  }
  return 0;
}
```

Test:

```
>ShowParams.exe "c:\test a\" "c:\test b\"
param 0 = ShowParams.exe
param 1 = c:\test a" c:\test
param 2 = b"
```