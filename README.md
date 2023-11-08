中文 / [English](README.en.md)
<p align="left">
    <a href="https://opensource.org/licenses/Apache-2.0" alt="License">
        <img src="https://img.shields.io/badge/License-Apache%202.0-blue.svg" /></a>
<a target="_blank" href="https://join.slack.com/t/neatlogichome/shared_invite/zt-1w037axf8-r_i2y4pPQ1Z8FxOkAbb64w">
<img src="https://img.shields.io/badge/Slack-Neatlogic-orange" /></a>
</p>

---

## 关于
neatlogic-autoexec-scripts工程，管理 **自定义工具库**(非标准工具库客户化脚本) 管理工程，与[neatlogic-autoexec-backend](../../../neatlogic-autoexec-backend/blob/master/README.MD)工程的主要区别在于：
* [neatlogic-autoexec-backend](../../../neatlogic-autoexec-backend/blob/master/README.MD)工程出厂内置的**工具库**，是[neatlogic-autoexec](../../../neatlogic-autoexec/blob/develop3.0.0/README.md)自动化模块基础固化出厂自带工具，用户无需也无法更改的工具库。

* neatlogic-autoexec-scripts工程内自定义工具，因管理上、技术方案、架构设计上不同，可能在实际交付过程中需要导入到[neatlogic-autoexec](../../../neatlogic-autoexec/blob/develop3.0.0/README.md)模块的自定义工具中修改后使用。

* neatlogic-autoexec-scripts为用户提供可扩展工具库管理边界的入口。

## 适用场景 
目前本工程提供开源场景和原子操作的自定义工具，包括：
<ol>
  <li>Vmware虚拟机的创建、销毁、启停。</li>
  <li>新建虚拟机标准化配置。</li>
  <li>Nginx、Tomcat、Jdk、Weblogic、Websphere中间件软件单实例、集群安装交付。</li>
  <li>MySQL主从、主主、1主多从集群安装交付。</li>
  <li>Oracle 单机、DG、ADG、RAC集群安装交付。</li>
  <li>Postgresql单机、主从安装交付。</li>
</ol>

⭐️说明
* 本工程会不定期更新自动化场景自定义工具，请持续关注。

## 关键要素讲解
原子操作插件定义的5大要素
### 执行方式
* runner执行
 在[neatlogic-runner](../../../neatlogic-runner/blob/develop3.0.0/README.md)所在机器上执行，简称本地执行。适用于需要安装依赖，比如vmware创建虚拟机。
 
* runner->target执行，在[neatlogic-runner](../../../neatlogic-runner/blob/develop3.0.0/README.md)所在机器上基于协议或[neatlogic-tagent-client](../../../neatlogic-tagent-client/blob/master/README.md)连远端目标执行。适用于需要安装依赖同时需要连远端目标执行，比如snmp采集。

* target执行，远端目标执行。适用于不需要环境依赖的脚本下发，比如应用启停。

* Sql文件执行。适用于数据库类DDL、DML等操作，比如应用部署过程中SQL执行。

### 支持脚本解析开发语言
目前支持客户自定义场景和操作扩展，支持开发语言有：
<ul>
  <li>bash</li>
  <li>ksh</li>
  <li>csh</li>
  <li>python</li>
  <li>perl</li>
  <li>ruby</li>
  <li>Powershell</li>
  <li>vbscript</li>
  <li>bat</li>
  <li>cmd</li>
  <li>javascript</li>
  <li>package</li>
</ul>

### 库文件定义
* 支持自定义库文件，建立公共的方库，给其它自定义原子操作插件引用和使用。

### 操作输入参数和输出参数 

支持自定义入参参数、参数是否必填、参数校验、默认值、以及可选控件类型：
<ul>
  <li>文本框</li>
  <li>单选下拉框</li>
  <li>多选下拉框</li>
  <li>单选框</li>
  <li>复选框</li>
  <li>文本域</li>
  <li>密码</li>
  <li>日期</li>
  <li>日期时间</li>
  <li>文件上传</li>
  <li>文件路径</li>
  <li>json对象</li>
  <!-- 自动化特有参数控件 -->
  <li>执行阶段</li>
  <li>执行节点</li>
  <li>执行账号</li>
  <li>用户选择器</li>
</ul>

## 原子操作插件工程管理

工程依赖导入和导出工具依赖python3，支持自定义原子操作插件以版本工具管理，如gitlab、svn等，同时支持工程代码一键导入/出到对应的执行环境。

### 环境变量初始化
```
cd autoscripts
source bin/setenv.sh
```

### 环境配置说明
```conf
server.baseurl = http://192.168.0.10:8282 # neatlogic-app主机IP和服务端口
server.username = autoexec # 导入用户
server.password = # autoexec用户token
password.key =  #密码加密key,需与neatlogic-autoexec-backend的key一直
tenant = demo  # 租户
catalogs.default = Database #导入启始目录，如为空导入所有
```

### 脚本导入导出
```
#导出备份脚本到当前目录
python3 autoscripts/bin/export.py

#导入脚本到系统
python3 autoscripts/bin/import.py
```

## 插件目录概要简介
以下目录简介仅供参考，实际会不定期调整或更改目录名称。
<ul>
  <li>Application:中间件相关场景和操作目录</li>
  <li>DataBase：数据库相关场景和操作目录</li>
  <li>Demo：提供给用户自定义原子操作参考案例目录</li>
  <li>OS：操作系统层面相关场景和操作目录</li>
</ul>
