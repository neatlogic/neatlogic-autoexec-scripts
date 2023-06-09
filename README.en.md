[中文](README.md) / English
<p align="left">
    <a href="https://opensource.org/licenses/Apache-2.0" alt="License">
        <img src="https://img.shields.io/badge/License-Apache%202.0-blue.svg" /></a>
<a target="_blank" href="https://join.slack.com/t/neatlogichome/shared_invite/zt-1w037axf8-r_i2y4pPQ1Z8FxOkAbb64w">
<img src="https://img.shields.io/badge/Slack-Neatlogic-orange" /></a>
</p>

---


## about
neatlogic-autoexec-scripts project, manages **custom tool library** (customized scripts for non-standard atomic operation plug-ins) management project, and [neatlogic-autoexec-backend](../../../neatlogic-autoexec-backend/blob/master/README.MD) The main differences of the project are:
* [neatlogic-autoexec-backend](../../../neatlogic-autoexec-backend/blob/master/README.MD) project built-in **tool library**, is [neatlogic-autoexec](../../../neatlogic-autoexec/blob/develop3.0.0/README.md) The automation module base solidifies the factory-built tools, which are not needed and cannot be changed and adjusted by the target users.

* The custom tools in the neatlogic-autoexec-scripts project may need to be imported into [neatlogic-autoexec](../../../neatlogic-autoexec/blob/develop3.0.0/README.md) module's custom tool after modification.

* neatlogic-autoexec-scripts provides users with an entry point for extensible management boundaries.

## Applicable scene 
Currently, this project provides custom tools for open source scenarios and atomic operations, including:
<ol>
   <li>Create, destroy, start and stop Vmware virtual machines. </li>
   <li>Create a new virtual machine standardized configuration. </li>
   <li>Nginx, Tomcat, Jdk, Weblogic, Websphere middleware software single instance, cluster installation and delivery. </li>
   <li>MySQL master-slave, master-master, 1-master-multi-slave cluster installation and delivery. </li>
   <li>Oracle stand-alone, DG, ADG, RAC cluster installation and delivery. </li>
   <li>Postgresql stand-alone, master-slave installation and delivery. </li>
</ol>

⭐️Description
* This project will update the automation scene customization tool from time to time, please continue to pay attention.

## Explanation of key elements
The 5 elements defined by the atomic operation plugin
### Implementation modalities
* runner execution
  Execute on the machine where [neatlogic-runner](../../../neatlogic-runner/blob/develop3.0.0/README.md) is located, referred to as local execution. Applicable to the need to install dependencies, such as vmware to create virtual machines.
 
* Runner->target execution, based on protocol or [neatlogic-tagent-client] on the machine where [neatlogic-runner](../../../neatlogic-runner/blob/develop3.0.0/README.md) is located [neatlogic-tagent-client](../../../neatlogic-tagent-client/blob/master/README.md) Even remote target execution. It is suitable for the installation of dependencies and the execution of remote targets, such as snmp collection.

* target execution, remote target execution. It is suitable for delivering scripts that do not depend on the environment, such as starting and stopping applications.

* Sql file execution. Applicable to operations such as database DDL and DML, such as SQL execution during application deployment.

### Support script parsing development language
Currently, it supports customer-defined scenarios and operation extensions, and the supported development languages are:
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

### Library file definition
* Support custom library files, create public square libraries, and reference and use other custom atomic operation plug-ins.

### Operation input parameters and output parameters

Supports custom input parameters, whether parameters are required, parameter validation, default values, and optional control types:
<ul>
   <li>Text box</li>
   <li>Single selection drop-down box</li>
   <li>Multiple selection drop-down box</li>
   <li>Radio box</li>
   <li>Check box</li>
   <li>Text field</li>
   <li>Password</li>
   <li>Date</li>
   <li>Date time</li>
   <li>File upload</li>
   <li>File path</li>
   <li>json object</li>
   <!-- Automation-specific parameter controls -->
   <li>Execution phase</li>
   <li>Execution Node</li>
   <li>Execution account</li>
   <li>User selector</li>
</ul>

## Atomic operation plug-in project management

Project dependency import and export tools rely on python3, support custom atomic operation plug-ins and version tool management, such as gitlab, svn, etc., and support one-click import/export of project code to the corresponding execution environment.

### Environment variable initialization
```
cd autoscripts
source bin/setenv.sh
```

### Environment configuration instructions
```conf
server.baseurl = http://192.168.0.10:8282 # neatlogic-app host IP and service port
server.username = autoexec # import users
server.password = # autoexec user token
password.key = #Password encryption key, which needs to be consistent with the key of neatlogic-autoexec-backend
tenant = demo # tenant
catalogs.default = Database #Import the starting directory, if it is empty, import all
```

### Script import and export
```
#Export the backup script to the current directory
python3 autoscripts/bin/export.py

#Import the script to the system
python3 autoscripts/bin/import.py
```

## Introduction to plugin directory
The following directory introduction is for reference only, and the directory name will be adjusted or changed from time to time.
<ul>
   <li>Application: middleware related scenarios and operation directory</li>
   <li>DataBase: database related scenarios and operation directory</li>
   <li>Demo: Provide user-defined atomic operation reference case directory</li>
   <li>OS: operating system level related scenarios and operation directory</li>
</ul>