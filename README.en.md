[中文](README.md) / English
<p align="left">
    <a href="https://opensource.org/licenses/Apache-2.0" alt="License">
        <img src="https://img.shields.io/badge/License-Apache%202.0-blue.svg" /></a>
<a target="_blank" href="https://join.slack.com/t/neatlogichome/shared_invite/zt-1w037axf8-r_i2y4pPQ1Z8FxOkAbb64w">
<img src="https://img.shields.io/badge/Slack-Neatlogic-orange" /></a>
</p>

---


## About
neatlogic-autoexec-scripts project, a customized script management project for managing non-standard atomic operation plugins, and<a href="../../../autoexec-backend">autoexec-backend</a>The main differences in engineering are:

* <a href="../../../autoexec-backend">autoexec-backend</a> project has built-in atomic operation plugins, which are<a href="../../../neatlogic-autoexec">neatlogic-autoexec</a> automation module foundation solidification plugin, different target users do not need to change or adjust plugin content.


* neatlogic-autoexec-scripts plugins within the project may need to be adjusted during actual delivery due to differences in management and solutions.

* neatlogic-autoexec-scripts provide users with an entrance to scalable management boundaries.

## Applicable scenarios 
The open source scenarios and atomic operations currently provided in this project include:
<ol>
<li>Create, destroy, start and stop Vmware virtual machines</li>

<li>Create a standardized configuration for a new virtual machine</li>

<li>Nginx, Tomcat, Jdk, Weblogic, Websphere middleware software single instance, cluster installation and delivery</li>

<li>Install and deliver MySQL master-slave, master-slave, and 1-master-slave clusters</li>

<li>Oracle standalone, DG, ADG, RAC cluster installation and delivery</li>

<li>PostgreSQL single machine, master-slave installation and delivery</li>
</ol>

⭐️notes
* This project will periodically update new automation scenarios and atomic operations, please continue to pay attention.

## Explanation of key elements
The 5 elements defined by atomic operation plugins
### Execution method

* runner execute
 in <a href="../../../neatlogic-autoexec"> neatlogic-autoexec</a>executed on the machine, abbreviated as local execution. Suitable for installing dependencies, such as creating virtual machines with vmware.
 
* runner->target execute, in<a href="../../../neatlogic-autoexec">neatlogic-autoexec</a>Based on protocol or 
<a href="../../../neatlogic-tagent-client">Neatlogic-tagent-client</a>  connect to remote targets for execution. Suitable for installing dependencies and connecting to remote targets for execution, such as SNMP collection.

* target executeRemote target execution. Suitable for scripts that do not require environmental dependencies, such as application startup and shutdown.

* Sql File execution. Suitable for database DDL, DML, and other operations, such as SQL execution during application deployment.


### Support script parsing development language

currently, it supports custom scenarios and operation extensions for customers, and supports development languages such as:

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

### Library File Definition
* Support custom library files, establish public libraries, and provide references and usage for other custom atomic operation plugins.

### Operating input and output parameters 

Support for custom input parameters, whether parameters are required, parameter validation, default values, and optional control types:

<ul>
<li>Text Box</li>
<li>Single selection dropdown box</li>
<li>Multiple Selection Dropdown Box</li>
<li>Radio Box</li>
<li>Checkbox</li>
<li>Text Field</li>
<li>Password</li>
<li>Date</li>
<li>Date Time</li>
<li>File upload</li>
<li>File Path</li>
<li>JSON object</li>
<!-- Automation specific parameter control -->
<li>Execution phase</li>
<li>Execution node</li>
<li>Execution account</li>
<li>User selector</li>
</ul>

## Atomic operation plugin engineering management

The engineering dependency import and export tools rely on Python 3, supporting custom atomic operation plugins for version tool management, such as Gitlab, SVN, etc., while also supporting one click import/export of engineering code to the corresponding execution environment.

### Environment variable initialization
```
cd autoscripts
source bin/setenv.sh
```

### Environmental Configuration Description

```conf
server.baseurl= http://192.168.0.10:8282 #Neatlogic app host IP and service port
server. username=autoexec # Import Users
server. password=# autoexec user token
password. key=# Password encryption key, which needs to be consistent with the key of nextlogic autoexec
tenant=demo # Tenant
catalogs. default=Database # Import start directory, if empty, import all
```

### Script import and export
```
#Export backup scripts to the current directory
python 3 autoscripts/bin/export.py

#Import script to system
python 3 autoscripts/bin/import. py
```

## Introduction to Plugin Catalog Overview

The following directory introduction is for reference only, and the directory name may be adjusted or changed from time to time.
<ul>
<li>Application: Middleware related scenarios and operation directory</li>

<li>DataBase: Database related scenarios and operation directory</li>

<li>Demo: Provide users with a directory of custom atomic operation reference cases</li>

<li>OS: Operating System Level Related Scenarios and Operation Directory</li>
</ul>
