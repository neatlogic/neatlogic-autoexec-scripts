#!/usr/bin/python3
# -*- coding: utf-8 -*-

import initenv
import base64
import json
import os
import os.path
import ijson
import urllib.request
import argparse

import Utils


def exportJsonInfo(params):
    hasError = 0
    # 需要数据源的表单类型
    needDataSourceTypeList = ['select', 'multiselect', 'radio', 'checkbox']
    serverUser = params.get('user')
    serverPass = params.get('password')
    tenant = params.get('tenant')
    pathStr = params.get('destDir')
    url = params.get('baseUrl') + '/public/api/binary/autoexec/script/export'
    # 获取json数据
    authStr = serverUser + ":" + serverPass
    Authorization = "Basic " + base64.b64encode(authStr.encode('utf8')).decode()
    headers = {
        'tenant': tenant,
        'Authorization': Authorization,
        'Content-Type': 'application/json; charset=utf-8'
    }
    request = urllib.request.Request(url, headers=headers)
    try:
        f = urllib.request.urlopen(request)
    except Exception as ex:
        hasError = 1
        print("ERROR: Request URL:{} failed, {}".format(url, str(ex)))
        return hasError

    objects = ijson.items(f, 'item')
    while True:
        try:
            data = objects.__next__()
            jsonInfo = {}
            opName = data.get('name')
            catalogPath = data.get('catalogPath')
            #jsonInfo['opName'] = opName
            jsonInfo['opType'] = data.get('execMode')
            jsonInfo['typeName'] = data.get('typeName')
            jsonInfo['riskName'] = data.get('riskName')
            jsonInfo['interpreter'] = data.get('parser')
            jsonInfo['description'] = data.get('description')
            # todo defaultProfile
            option = []
            output = []
            paramList = data.get('paramList')
            for param in paramList:
                dataParam = {}
                if param.get('mode') == 'input':
                    dataParam['opt'] = param.get('key')
                    dataParam['name'] = param.get('name')
                    dataParam['help'] = param.get('description')
                    dataParam['type'] = param.get('type')
                    if param.get('type') in needDataSourceTypeList:
                        config = param.get('config')
                        if config != None:
                            # 去掉多余的字段
                            config.pop('type', None)
                            config.pop('defaultValue', None)
                            config.pop('isRequired', None)
                            dataSource = config.pop('dataSource', None)
                            if dataSource != None:
                                config['dataType'] = dataSource
                            dataParam['dataSource'] = config
                    dataParam['defaultValue'] = param.get('defaultValue')
                    if param.get('isRequired') == 1:
                        dataParam['required'] = 'true'
                    else:
                        dataParam['required'] = 'false'
                    # 校验正则表达式
                    dataParam['validate'] = ''
                    # todo 全局参数
                    option.append(dataParam)

                if param.get('mode') == 'output':
                    dataParam['opt'] = param.get('key')
                    dataParam['name'] = param.get('name')
                    dataParam['help'] = param.get('description')
                    dataParam['type'] = param.get('type')
                    dataParam['defaultValue'] = param.get('defaultValue')
                    if param.get('isRequired') == 1:
                        dataParam['required'] = 'true'
                    else:
                        dataParam['required'] = 'false'
                    output.append(dataParam)

            argumentParam = data.get('argument')
            # 自由参数
            if argumentParam != None:
                argument = {}
                argument['name'] = argumentParam.get('name')
                argument['type'] = argumentParam.get('type')
                argument['defaultValue'] = argumentParam.get('defaultValue')
                argument['help'] = argumentParam.get('description')
                argument['count'] = argumentParam.get('argumentCount')
                argument['validate'] = ''
                if argumentParam.get('isRequired') == 1:
                    argument['required'] = 'true'
                else:
                    argument['required'] = 'false'
                jsonInfo['argument'] = argument

            jsonInfo['option'] = option
            jsonInfo['output'] = output
            # 写入
            if opName != None:
                opJsonName = opName + '.json'
                jsonPath = ''
                if catalogPath != None and catalogPath != '':
                    catalogFullDir = os.path.join(pathStr, catalogPath)
                    #jsonPath = pathStr + '/' + catalogPath + '/' + opName + '.json'
                    jsonPath = os.path.join(catalogFullDir, opJsonName)
                    if not os.path.exists(catalogFullDir):
                        os.makedirs(catalogFullDir)
                else:
                    #jsonPath = pathStr + '/' + opName + '.json'
                    jsonPath = os.path.join(pathStr, opJsonName)
                    if not os.path.exists(pathStr):
                        os.makedirs(pathStr)
                try:
                    with open(jsonPath, 'w', encoding='utf-8') as m:
                        m.write(json.dumps(jsonInfo, indent=4, ensure_ascii=False))
                except Exception as reason:
                    hasError = hasError + 1
                    print("ERROR: Script:%s export failed, %s" % (opName, str(reason)))

                lineList = data.get('lineList')
                if opName != None:
                    scriptFilePath = None
                    if catalogPath != None and catalogPath != '':
                        #scriptFilePath = pathStr + '/' + catalogPath + '/' + opName
                        scriptFilePath = os.path.join(pathStr, catalogPath, opName)
                    else:
                        #scriptFilePath = pathStr + '/' + opName
                        scriptFilePath = os.path.join(pathStr, opName)

                    try:
                        with open(scriptFilePath, 'w', encoding='utf8') as scriptFile:
                            print("INFO: Try to export {}".format(opName))
                            for line in lineList:
                                if line.__contains__('content'):
                                    content = line.get('content')
                                    scriptFile.write(content)
                                scriptFile.write('\n')
                            print("INFO: {} exported to {}.\n".format(opName, scriptFilePath))
                    except Exception as reason:
                        hasError = hasError + 1
                        print("ERROR: Script:%s export failed, %s" % (opName, str(reason)))
        except StopIteration as e:
            break


def parseArgs():
    parser = argparse.ArgumentParser(description='you should add those paramete')
    parser.add_argument("--baseurl", default='', help="Automation web console address")
    parser.add_argument("--tenant", default='', help="Tenant")
    parser.add_argument("--user", default='', help="username")
    parser.add_argument("--password", default='', help="passWord")
    parser.add_argument("--dir", default='', help="Script's directory")
    args = parser.parse_args()

    params = Utils.parseCmdArgs(args)

    return params


if __name__ == '__main__':
    params = parseArgs()
    status = exportJsonInfo(params)
    exit(status)
