中文 / [English](README.en.md)
<p align="left">
    <a href="https://opensource.org/licenses/Apache-2.0" alt="License">
        <img src="https://img.shields.io/badge/License-Apache%202.0-blue.svg" /></a>
<a target="_blank" href="https://join.slack.com/t/neatlogichome/shared_invite/zt-1w037axf8-r_i2y4pPQ1Z8FxOkAbb64w">
<img src="https://img.shields.io/badge/Slack-Neatlogic-orange" /></a>
</p>

---

## 关于

此项目用于管理所有客户化脚本，不定时更新

## 使用

### python3 在Linux上的安装后，更改python3位默认的python执行程序

执行autoscripts目录下的bin/setup.sh切换python3位默认python

```shell
cd autoscripts
./setup.sh
```

### 安装python3第三方库

```
cd autoscripts/media
./ins-modules.sh

###或者手工pip3安装
pip3 install requests filelock ijson
```

### 升级python3第三方库

```
cd autoscripts/media
./upgrade-modules.sh
```

### 重新安装单个模块例子

```
cd autoscripts/media
./ins-modules.sh requests ijson
./upgrade-modules.sh requests ijson
```

### 环境变量初始化

```
cd autoscripts
source bin/setenv.sh
```

### 脚本导入导出

```
#导出脚本到scripts目录下
python3 bin/export.py

#导入脚本到系统
python3 bin/import.py
```

### Windows脚本

Windows脚本不同解析器对参数格式的要求不一致
cmd.exe设置编码（UTF-8）：mode con cp select=1250
cmd.exe设置编码（GBK）：mode con cp select=936

### Windows不同类型脚本的参数格式

Windows不同类型脚本的参数格式和处理方法不一样

#### 注意：VBScript无法处理参数值中带双引号的参数，不支持复杂参数

#### 注意：bat脚本无法处理有名称的参数，对于存在空格的参数会把前后的双引号带上

bat脚本：

```
@echo off
echo Param1 = %1
echo Param2 = %2
echo Param3 = %3
```

测试：

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

测试：

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
    write-host("Argument  $i is $($args[$i])")
} 
```

测试：

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

测试：

```
>ShowParams.exe "c:\test a\" "c:\test b\"
param 0 = ShowParams.exe
param 1 = c:\test a" c:\test
param 2 = b"
```
