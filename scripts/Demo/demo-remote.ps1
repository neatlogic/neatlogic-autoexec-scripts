
# 创建数据目录
function Create_Data_Dir(){
    log("当前执行目录下面创建数据存储目录  data")
    if(Test-Path .\auxiliary){
        log("删除之前数据存储目录")
        Remove-Item -Path .\auxiliary -Recurse
    }
    mkdir -path .\auxiliary\weblog\apache,.\auxiliary\weblog\nginx,.\auxiliary\weblog\tomcat,.\auxiliary\weblog\weblogic
    mkdir -path .\auxiliary\assetsInfo
    mkdir -path .\auxiliary\sysInfo\core
    mkdir -path .\auxiliary\sysInfo\software
    mkdir -path .\auxiliary\sysInfo\userInfo,.\auxiliary\sysInfo\userInfo\member
    mkdir -path .\auxiliary\sysInfo\startItem
    mkdir -path .\auxiliary\sysInfo\crontab,.\auxiliary\sysInfo\crontab\hash
    mkdir -path .\auxiliary\sysInfo\history
    mkdir -path .\auxiliary\sysInfo\dubiousFile,.\auxiliary\sysInfo\dubiousFile\file
    mkdir -path .\auxiliary\processInfo
    mkdir -path .\auxiliary\network
    mkdir -path .\auxiliary\log
}

# 读取web日志数据
function Get_WebLogInfo(){
   log("**********读取web日志数据 开始****************")

   #读取apache日志
   if(![String]::IsNullOrWhiteSpace($APACHE_LOG_DIR)){
        log("读取apache日志数据")
        cp $APACHE_LOG_DIR .\auxiliary\weblog\apache
        if(![String]::IsNullOrWhiteSpace($APACHE_CONFIG_DIR)){
            log("读取apache配置数据")
            cat $APACHE_CONFIG_DIR | findstr 'LogFormat'|findstr 'combined$'|Out-File -FilePath .\auxiliary\weblog\apache\weblogformat.txt -Encoding utf8
        }else{
            log("apache配置目录为空")
        }
   }

   #读取nginx
   if(![String]::IsNullOrWhiteSpace($NGINX_LOG_DIR)){
        log("读取nginx日志数据")
        cp $NGINX_LOG_DIR .\auxiliary\weblog\nginx
   }

   #读取tomcat
   if(![String]::IsNullOrWhiteSpace($TOMCAT_LOG_DIR)){
        log("读取tomcat日志数据")
        cp $TOMCAT_LOG_DIR .\auxiliary\weblog\tomcat
   }

   #读取weblogic
   if(![String]::IsNullOrWhiteSpace($WEBLOGIC_LOG_DIR)){
        log("读取weblogic日志数据")
        cp $WEBLOGIC_LOG_DIR .\auxiliary\weblog\weblogic
   }
   log("**********读取web日志数据 结束****************")
}

# 读取资产信息数据
function Get_AssetsInfo(){
    log("**********获取资产信息 开始****************")
    $os = gcim -Class Win32_OperatingSystem | Select-Object -ExpandProperty Caption
    $osVersion
    if( $os.Contains('2012') ){
       $osVersion = 101206
    }elseif( $os.Contains('2008')){
       $osVersion = 101205
    }elseif( $os.Contains('2016')){
       $osVersion = 101207
    }elseif($os.Contains('2003')){
       $osVersion = 101204
    }elseif($os.Contains('10')){
       $osVersion = 101203
    }elseif($os.Contains('8')){
       $osVersion = 101202
    }elseif($os.Contains('7')){
       $osVersion = 101201
    }
    $cpu = get-wmiobject win32_processor
    $cpuNum = @($cpu).count
    $cpuCore = $cpuNum*$cpu.NumberOfLogicalProcessors
    $cpuMonitor = ps | sort -desc cpu | select -first 10 |Out-String
    [int] $memory = (gcim -Class Win32_ComputerSystem).TotalPhysicalMemory /1mb
    $men = Get-WmiObject -Class win32_OperatingSystem
    [int] $Allmen = $men.TotalVisibleMemorySize /1kb
    [int] $Freemen = $men.FreePhysicalMemory /1kb 
    [int ]$Permem =  ((($men.TotalVisibleMemorySize-$men.FreePhysicalMemory)/$men.TotalVisibleMemorySize)*100)
    $memoryMonitor ="总内存(MB):$Allmen  可用内存(MB):$Freemen 使用率:$Permem %"
    [int] $disk = ((gcim -Class win32_logicaldisk).Size | Measure-Object -Sum).sum /1gb
    [string] $diskMonitor = get-psdrive|Out-String
    [string] $envMonitor = Get-ChildItem env:|Out-String
    $assetsInfo =New-Object object
    Add-Member -InputObject  $assetsInfo -MemberType NoteProperty -Name os_type -Value 101200
    Add-Member -InputObject  $assetsInfo -MemberType NoteProperty -Name os_version -Value $osVersion
    Add-Member -InputObject  $assetsInfo -MemberType NoteProperty -Name cpu -Value $cpuNum
    Add-Member -InputObject  $assetsInfo -MemberType NoteProperty -Name cpu_core -Value $cpuCore
    Add-Member -InputObject  $assetsInfo -MemberType NoteProperty -Name cpu_monitor -Value $cpuMonitor
    Add-Member -InputObject  $assetsInfo -MemberType NoteProperty -Name memory -Value $memory
    Add-Member -InputObject  $assetsInfo -MemberType NoteProperty -Name memory_monitor -Value $memoryMonitor
    Add-Member -InputObject  $assetsInfo -MemberType NoteProperty -Name disk -Value $disk
    Add-Member -InputObject  $assetsInfo -MemberType NoteProperty -Name disk_monitor -Value $diskMonitor
    Add-Member -InputObject  $assetsInfo -MemberType NoteProperty -Name env_monitor -Value $envMonitor
    $assetsInfo |ConvertTo-Json |Out-File -FilePath .\auxiliary\assetsInfo\assetsInfo.txt -Encoding utf8
    log("**********获取资产信息数据 结束****************")
}

# 读取系统信息
function Get_SysInfo(){
    $enable=checkEnable(124101)
    if(![String]::IsNullOrWhiteSpace($enable)){
      Get_SysInfo_Core
    }
    $enable=checkEnable(124102)
    if(![String]::IsNullOrWhiteSpace($enable)){
      Get_SysInfo_Software
    }
    $enable=checkEnable(124103)
    if(![String]::IsNullOrWhiteSpace($enable)){
      Get_SysInfo_UserInfo
    }
    $enable=checkEnable(124106)
    if(![String]::IsNullOrWhiteSpace($enable)){
      Get_SysInfo_StartItem
    }
    $enable=checkEnable(124107)
    if(![String]::IsNullOrWhiteSpace($enable)){
      Get_SysInfo_Crontab
    }
    $enable=checkEnable(124108)
    if(![String]::IsNullOrWhiteSpace($enable)){
      Get_SysInfo_History
    }
    $enable=checkEnable(124109)
    if(![String]::IsNullOrWhiteSpace($enable)){
      Get_Dubious_File
    }
}

# 读取系统信息-内核信息
function Get_SysInfo_Core(){
    log("**********获取系统信息-内核信息 开始****************")
    Get-WmiObject Win32_QuickFixEngineering |Select-Object -Property HotFixID,Description |ConvertTo-Json -Compress|Out-File -FilePath .\auxiliary\sysInfo\core\coreInfo.txt -Encoding utf8
    log("**********获取系统信息-内核信息 结束****************")
}

# 读取系统信息-软件信息
function Get_SysInfo_Software(){
    log("**********获取系统信息-软件信息 开始****************")
    gcim Win32_Product|Select-Object Name,Version,PackageName,InstallDate,InstallSource |ConvertTo-Json -Compress|Out-File -FilePath .\auxiliary\sysInfo\software\software.txt -Encoding utf8
    log("**********获取系统信息-软件信息 结束****************")
}

# 读取系统信息-用户信息
#function Get_SysInfo_UserInfo(){
#    log("读取系统信息-用户信息")
#    Get-WmiObject -Class Win32_UserAccount | Select-Object SID,Name | ConvertTo-Json |Out-File -FilePath .\auxiliary\sysInfo\userInfo\user.txt -Encoding utf8
#    $groupArray= Get-WmiObject -Class Win32_Group|Select-Object SID,Name
#    $groupArray|ConvertTo-Json |Out-File -FilePath .\auxiliary\sysInfo\userInfo\group.txt -Encoding utf8
#    foreach ($group in $groupArray)
#    {
#        $groupSID = $group.SID.VALUE
#        Get-LocalGroupMember -SID  $groupSID |Select-Object Name,SID|ConvertTo-Json |Out-File -FilePath .\auxiliary\sysInfo\userInfo\$groupSID.txt -Encoding utf8
#    }
#}

# 读取系统信息-用户信息
function Get_SysInfo_UserInfo(){
    log("**********获取系统信息-用户信息 开始****************")
    Get-WmiObject -Class Win32_UserAccount | Select-Object SID,Name | ConvertTo-Json |Out-File -FilePath .\auxiliary\sysInfo\userInfo\user.txt -Encoding utf8
    $groupArray= Get-WmiObject -Class Win32_Group|Select-Object SID,Name
    $groupArray|ConvertTo-Json |Out-File -FilePath .\auxiliary\sysInfo\userInfo\group.txt -Encoding utf8
    $groupUser = Get-WmiObject -Query " select * from Win32_GroupUser"
    foreach ($group in $groupArray)
    {
        $groupName = $group.Name
        getMember($groupName)

    }
    log("**********获取系统信息-用户信息 结束****************")
}

function getMember($group){
    $member = ""
    foreach ($t in $groupUser ){
    if ($t.GroupComponent -match $group){
        $longstr = $t.PartComponent
        $namepos = $longstr.IndexOf("Name=") + 6
        $name = $longstr.Substring($namepos, $longstr.Length - $namepos -1)
        $name|Out-File -FilePath .\auxiliary\sysInfo\userInfo\member\$group.txt -Append -Encoding utf8
        }
    }
}

# 读取系统信息-启动项
function Get_SysInfo_StartItem(){
    log("**********获取系统信息-启动项 开始****************")
    Get-Service |Select-Object Status,ServiceName|ConvertTo-Json|Out-File -FilePath .\auxiliary\sysInfo\startItem\startItem.txt -Encoding utf8
    log("**********获取系统信息-启动项 结束****************")
}

# 读取系统信息-定时任务 TODO
function Get_SysInfo_Crontab(){
    log("**********获取系统信息-定时任务 开始****************")
    $allTask = schtasks /query /v /fo list
    $allTask|Out-File -FilePath .\auxiliary\sysInfo\crontab\allTask.txt -Encoding utf8
    $taskFileList =  $allTask|findstr '要运行的任务:'
    foreach ($taskFile in $taskFileList)
    {
        $value = $taskFile.Remove(0,7) -replace '\s{2,}', ''
        if(Test-Path $value){
            $hash = (Get-FileHash -Algorithm MD5 $value).Hash
            $value|Out-File -FilePath .\auxiliary\sysInfo\crontab\hash\$hash -Encoding utf8
        }
    }
    log("**********获取系统信息-定时任务 结束****************")
}

# 读取系统信息-历史命令
function Get_SysInfo_History(){
    log("**********获取系统信息-历史命令 开始****************")
    history|Select-Object Id,CommandLine|ConvertTo-Json|Out-File -FilePath .\auxiliary\sysInfo\history\history.txt -Encoding utf8
    log("**********获取系统信息-历史命令 结束****************")
}

# 读取系统信息-可疑文件
function Get_Dubious_File(){
    log("**********获取系统信息-可疑文件 开始****************")
    $exeFile = wmic process where "NOT ExecutablePath Like '%windows%'" Get ExecutablePath | sort -Unique
    $list = New-Object -TypeName System.Collections.ArrayList
    foreach ($file in $exeFile){
        if( ![String]::IsNullOrWhiteSpace($file) -and (Test-Path $file) ){
            $time  = (Get-ChildItem -Path $file).LastAccessTime.ToString("yyyy-MM-dd HH:mm:ss")
            $fileHash = (Get-FileHash -Algorithm MD5 $file).Hash
            $dubiousFile =New-Object object
            Add-Member -InputObject  $dubiousFile -MemberType NoteProperty -Name name -Value $file.Trim()
            Add-Member -InputObject  $dubiousFile -MemberType NoteProperty -Name time -Value $time
            Add-Member -InputObject  $dubiousFile -MemberType NoteProperty -Name fileHash -Value $fileHash
            $list.Add($dubiousFile)
            mkdir -path .\auxiliary\sysInfo\dubiousFile\file\$fileHash
            Copy-Item -Path $file -Destination .\auxiliary\sysInfo\dubiousFile\file\$fileHash
        }
    }
    $list |ConvertTo-Json |Out-File -FilePath .\auxiliary\sysInfo\dubiousFile\data.txt -Encoding utf8
    log("**********获取系统信息-可疑文件 结束****************")
}

# 读取进程信息
function Get_ProcessInfo(){
     log("**********读取进程信息 开始****************")
     Get-Process | Select-Object Id,Modules,@{N='StartTime';E={$_.StartTime.ToString("yyyy-MM-dd HH:mm:ss")}},@{N='TotalProcessorTime';E={$_.TotalProcessorTime.ToString()}},VM,WS,Path |ConvertTo-Json|Out-File -FilePath .\auxiliary\processInfo\processList.txt -Encoding utf8
     tasklist /V /FO table|Out-File -FilePath  .\auxiliary\processInfo\tasklist.txt -Encoding utf8
     log("**********读取进程信息 结束****************")

}

# 读取网络信息
function Get_NetstatInfo(){
     log("**********读取网络信息 开始****************")
     netstat -naoq |Out-File -FilePath .\auxiliary\network\network.txt -Encoding utf8
     netstat -nao |Out-File -FilePath .\auxiliary\network\network1.txt -Encoding utf8
     log("**********读取网络信息 结束****************")
}

# 读取系统日志 (需要管理权限)
function Get_SysLogInfo(){
    log("**********读取系统日志 开始****************")
    #Get-EventLog Security |Select-Object MachineName,Data,Index,Category,CategoryNumber,EventID,EntryType,Message,Source,ReplacementStrings,InstanceId,UserName,Site,Container,@{N='TimeGenerated';E={$_.TimeGenerated.ToString("yyyy-MM-dd HH:mm:ss")}},@{N='TimeWritten';E={$_.TimeWritten.ToString("yyyy-MM-dd HH:mm:ss")}} |ConvertTo-Json|Out-File -FilePath .\auxiliary\log\security -Encoding utf8
    #Get-EventLog Application |Select-Object MachineName,Data,Index,Category,CategoryNumber,EventID,EntryType,Message,Source,ReplacementStrings,InstanceId,UserName,Site,Container,@{N='TimeGenerated';E={$_.TimeGenerated.ToString("yyyy-MM-dd HH:mm:ss")}},@{N='TimeWritten';E={$_.TimeWritten.ToString("yyyy-MM-dd HH:mm:ss")}}  |ConvertTo-Json|Out-File -FilePath .\auxiliary\log\application -Encoding utf8
    #Get-EventLog System |Select-Object MachineName,Data,Index,Category,CategoryNumber,EventID,EntryType,Message,Source,ReplacementStrings,InstanceId,UserName,Site,Container,@{N='TimeGenerated';E={$_.TimeGenerated.ToString("yyyy-MM-dd HH:mm:ss")}},@{N='TimeWritten';E={$_.TimeWritten.ToString("yyyy-MM-dd HH:mm:ss")}} |ConvertTo-Json|Out-File -FilePath .\auxiliary\log\system -Encoding utf8
    $SecurityList = New-Object -TypeName System.Collections.ArrayList
    $StartDate=(Get-Date).AddDays(-$check_day)
    Get-WinEvent -FilterHashtable @{LogName='Security';StartTime=$StartDate;EndTime=Get-Date}|ForEach-Object{
                $SelectorStrings = [string[]]@(
                'Event/System/EventID',
                'Event/System/Level',
                'Event/EventData/Data[@Name="TargetUserName"]',
                'Event/EventData/Data[@Name="SubjectUserName"]',
                'Event/EventData/Data[@Name="SubjectUserSid"]',
                'Event/EventData/Data[@Name="TargetDomainName"]',
                'Event/EventData/Data[@Name="SubjectDomainName"]',
                'Event/EventData/Data[@Name="IpAddress"]',
                'Event/EventData/Data[@Name="IpPort"]',
                'Event/EventData/Data[@Name="ProcessName"]'
                )
                $PropertySelector = [System.Diagnostics.Eventing.Reader.EventLogPropertySelector]::new($SelectorStrings)
                $EventID,$Level,$TargetUserName,$SubjectUserName,$SubjectUserId,$TargetDomain,$SubjectDomain,$IPAddress,$IpPort,$ProcessName = $_.GetPropertyValues($PropertySelector)
                if ($SubjectUserId) {
                    $SubjectUserId= $SubjectUserId.ToString()
                }
               $obj = [PSCustomObject]@{
                Opcode                = $_.Opcode
                ProviderName          = $_.ProviderName
                TaskDisplayName       = $_.TaskDisplayName
                KeywordsDisplayNames  = $_.KeywordsDisplayNames
                Message               = $_.Message.toString()
                TimeCreated           = $_.TimeCreated.ToString("yyyy-MM-dd HH:mm:ss")
                EventID               = $EventID
                Level                 = $Level
                TargetUserName        = $TargetUserName
                SubjectUserName       = $SubjectUserName
                SubjectUserId         = $SubjectUserId
                TargetDomain          = $TargetDomain
                SubjectDomain         = $SubjectDomain
                IPAddress             = $IPAddress
                IpPort                = $IpPort
                ProcessName           = $ProcessName
                }
                $SecurityList.Add($obj)
            }
    $SecurityList|ConvertTo-Json|Out-File -FilePath  .\auxiliary\log\security -Encoding utf8


    $ApplicationList = New-Object -TypeName System.Collections.ArrayList
    Get-WinEvent -FilterHashtable @{LogName='Application';StartTime=$StartDate;EndTime=Get-Date}|ForEach-Object{
                $SelectorStrings = [string[]]@(
                'Event/System/EventID',
                'Event/System/Level'
                )
                $PropertySelector = [System.Diagnostics.Eventing.Reader.EventLogPropertySelector]::new($SelectorStrings)
                $EventID,$Level=$_.GetPropertyValues($PropertySelector)
                if ($_.TimeCreated) {
                    $TimeCreatedStr=$_.TimeCreated.ToString("yyyy-MM-dd HH:mm:ss")
                }else{
                    $TimeCreatedStr=$_.TimeCreated
                }
                if ($_.Message) {
                    $MessageContent=$_.Message.toString()
                }else{
                    $MessageContent=$_.Message
                }
               $obj = [PSCustomObject]@{
                Opcode                = $_.Opcode
                ProviderName          = $_.ProviderName
                TaskDisplayName       = $_.TaskDisplayName
                KeywordsDisplayNames  = $_.KeywordsDisplayNames
                Message               = $MessageContent
                TimeCreated           = $TimeCreatedStr
                EventID               = $EventID
                Level                 = $Level
                }
                $ApplicationList.Add($obj)
            }
    $ApplicationList|ConvertTo-Json|Out-File -FilePath  .\auxiliary\log\application -Encoding utf8


    $SystemList = New-Object -TypeName System.Collections.ArrayList
    Get-WinEvent -FilterHashtable @{LogName='System';StartTime=$StartDate;EndTime=Get-Date}|ForEach-Object{
                $SelectorStrings = [string[]]@(
                'Event/System/EventID',
                'Event/System/Level'
                )
                $PropertySelector = [System.Diagnostics.Eventing.Reader.EventLogPropertySelector]::new($SelectorStrings)
                $EventID,$Level = $_.GetPropertyValues($PropertySelector)
                if ($_.TimeCreated) {
                    $TimeCreatedStr= $_.TimeCreated.ToString("yyyy-MM-dd HH:mm:ss")
                }else{
                    $TimeCreatedStr=$_.TimeCreated
                }
                if ($_.Message) {
                    $MessageContent= $_.Message.toString()
                }else{
                    $MessageContent=$_.Message
                }
                $obj = [PSCustomObject]@{
                Opcode                = $_.Opcode
                ProviderName          = $_.ProviderName
                TaskDisplayName       = $_.TaskDisplayName
                KeywordsDisplayNames  = $_.KeywordsDisplayNames
                Message               = $MessageContent
                TimeCreated           = $TimeCreatedStr
                EventID               = $EventID
                Level                 = $Level
                }
                $SystemList.Add($obj)
            }
    $SystemList|ConvertTo-Json|Out-File -FilePath  .\auxiliary\log\system -Encoding utf8


    log("**********读取系统日志 结束****************")
}


function log($logContent){
    echo $logContent
    $logContent | Out-File -Append .\import.log -Encoding utf8
}


function main(){
    log("  ##::: ##::'######::::'######:::'#######:::'######::")
    log("  ###:: ##:'##... ##::'##... ##:'##.... ##:'##... ##:")
    log("  ####: ##: ##:::..::: ##:::..:: ##:::: ##: ##:::..::")
    log("  ## ## ##: ##::'####:. ######:: ##:::: ##: ##:::::::")
    log("  ##. ####: ##::: ##:::..... ##: ##:::: ##: ##:::::::")
    log("  ##:. ###: ##::: ##::'##::: ##: ##:::: ##: ##::: ##:")
    log("  ##::. ##:. ######:::. ######::. #######::. ######::")
    log(" ..::::..:::......:::::......::::.......::::......:::")
    log("                                                     ")
    log("             Windows调查取证工具 V1.0                ")
    log("              北斗网络安全运营平台                   ")
    log("            北京国舜科技股份有限公司                 ")
    log(" 取证机器 Powershell脚本的执行权限需要为以下权限     ")
    log("           RemoteSigned 或者 Unrestricted            ")

    #apache配置
    $APACHE_LOG_DIR=""
    $APACHE_CONFIG_DIR=""
    #nginx配置
    $NGINX_LOG_DIR=""
    #tomcat配置
    $TOMCAT_LOG_DIR=""
    #weblogic配置
    $WEBLOGIC_LOG_DIR=""
    log("**********采集数据开始***********")
    Create_Data_Dir
    $enable=checkEnable(123706)
    if(![String]::IsNullOrWhiteSpace($enable)){
      Get_WebLogInfo
    }
    $enable=checkEnable(123702)
    if(![String]::IsNullOrWhiteSpace($enable)){
      Get_AssetsInfo
    }
    Get_SysInfo
    $enable=checkEnable(123708)
    if(![String]::IsNullOrWhiteSpace($enable)){
      Get_ProcessInfo
    }
    $enable=checkEnable(123709)
    if(![String]::IsNullOrWhiteSpace($enable)){
      Get_NetstatInfo
    }
    $enable=checkEnable(123710)
    if(![String]::IsNullOrWhiteSpace($enable)){
      Get_SysLogInfo
    }
    log("**********采集数据结束***********")
    log("**********采集数据压缩打包开始（powershell5.0以及以后版本可以自动打包）***********")
    Compress-Archive -Path .\auxiliary -DestinationPath .\auxiliary.zip -Force
    echo "end" | Out-File -Append .\finish.log -Encoding utf8
    log("**********采集数据压缩打包结束（如果当前目录下面无auxiliary.zip文件,请手动将auxiliary文件夹打包为auxiliary.zip）***********")
    exit 0
}

function checkEnable($taskCode){
    foreach ($code in $task_list){
        if($code.ToString().Equals("0")){
          return 0
        }elseif($code.ToString().Equals($taskCode.ToString())){
            return 0
        }
   }
   return ""
}


$check_day=$args[0]
$task_list=$args[1]
if(!$task_list.GetType().IsArray){
   $task_list=$task_list.ToString().Split(",")
}
main

