#!/usr/bin/python3
# -*- coding: utf-8 -*-
import initenv
import json
import os
import traceback
import os.path
import re
import requests
import argparse

import Utils


def importJsonInfo(params):
    hasError = 0
    serverUser = params.get('user')
    serverPass = params.get('password')
    tenant = params.get('tenant')
    url = params.get('baseUrl') + '/public/api/stream/autoexec/script/import/fromjson'
    dataDir = params.get('destDir')
    headers = {
        'tenant': tenant,
    }

    if dataDir != None and dataDir != '':
        # 新脚本
        newScriptList = set()
        # 更新了基本信息或生成了新版本的脚本
        updatedScriptList = set()
        for root, dirs, files in os.walk(dataDir, topdown=False):
            for opName in files:
                if not opName.endswith('.json'):
                    try:
                        scriptPath = os.path.join(root, opName)
                        catalogName = os.path.basename(root)
                        jsonList = []
                        jsonInfo = {}
                        # 获取脚本描述.json文件
                        if not os.path.exists(scriptPath + '.json'):
                            continue

                        with open(scriptPath + '.json', 'r', encoding='utf-8') as scriptJsonFile:
                            print("INFO: Try to import {}".format(scriptPath))
                            try:
                                data = json.load(scriptJsonFile)
                            except Exception as ex:
                                print("ERROR: Load json file %s failed, there is possible format error: %s" % (scriptPath + ".json", str(ex)))
                            paramList = []
                            # 输入参数
                            optionList = data.get('option')
                            for option in optionList:
                                param = {}
                                param['key'] = option.get('opt')
                                param['name'] = option.get('name')
                                param['defaultValue'] = option.get('defaultValue')
                                param['description'] = option.get('help')
                                if option.get('required') == 'true':
                                    param['isRequired'] = 1
                                else:
                                    param['isRequired'] = 0
                                param['type'] = option.get('type')
                                dataSource = option.get('dataSource')
                                if dataSource != None:
                                    dataType = dataSource.pop('dataType', None)
                                    if dataType != None and dataType != '':
                                        dataSource['dataSource'] = dataType
                                    else:
                                        dataSource['dataSource'] = 'static'
                                    param['config'] = dataSource
                                param['mode'] = 'input'
                                # todo 全局参数
                                paramList.append(param)

                            # 输出参数
                            outputList = data.get('output')
                            for output in outputList:
                                param = {}
                                param['key'] = output.get('opt')
                                param['name'] = output.get('name')
                                param['description'] = output.get('help')
                                if output.get('required') == 'true':
                                    param['isRequired'] = 1
                                else:
                                    param['isRequired'] = 0
                                param['type'] = output.get('type')
                                param['defaultValue'] = output.get('defaultValue')
                                param['mode'] = 'output'
                                paramList.append(param)

                            # 自由参数
                            argumentParam = data.get('argument')
                            if argumentParam != None:
                                argument = {}
                                argument['name'] = argumentParam.get('name')
                                argument['type'] = argumentParam.get('type')
                                argument['defaultValue'] = argumentParam.get('defaultValue')
                                argument['argumentCount'] = argumentParam.get('count')
                                argument['description'] = argumentParam.get('help')
                                if argumentParam.get('required') == 'true':
                                    argument['isRequired'] = 1
                                else:
                                    argument['isRequired'] = 0
                                jsonInfo['argument'] = argument

                            jsonInfo['paramList'] = paramList
                            jsonInfo['parser'] = data.get('interpreter')

                            jsonInfo['name'] = opName
                            # 目录
                            jsonInfo['catalogName'] = catalogName
                            jsonInfo['execMode'] = data.get('opType')
                            jsonInfo['riskName'] = data.get('riskName')
                            jsonInfo['typeName'] = data.get('typeName')
                            jsonInfo['defaultProfileName'] = data.get('defaultProfile')
                            jsonInfo['description'] = data.get('description')

                        lineList = []
                        try:
                            with open(scriptPath, 'r', encoding='utf-8') as scriptFile:
                                for line in scriptFile:
                                    line = re.sub('\\r?\\n$', '', line)
                                    lineList.append({'content': line})
                                jsonInfo['lineList'] = lineList
                            jsonList.append(jsonInfo)
                        except Exception as ex:
                            print("ERROR: Open script file %s failed, error: %s" % (scriptPath, str(ex)))
                        try:
                            res = requests.post(url, headers=headers, data=json.dumps(jsonList), auth=(serverUser, serverPass))
                            content = res.json()
                            result = content.get('Return')
                            faultArray = result.get('faultArray')
                            # 新脚本
                            newScriptArray = result.get('newScriptArray')
                            # 更新了基本信息或生成了新版本的脚本
                            updatedScriptArray = result.get('updatedScriptArray')
                            for item in faultArray:
                                print("ERROR：{}".format(item['item']))
                                faultMessages = item['faultMessages']
                                for message in faultMessages:
                                    print(message)
                            if faultArray == None or len(faultArray) == 0:
                                if newScriptArray != None and len(newScriptArray) > 0:
                                     newScriptList.add(newScriptArray[0])
                                if updatedScriptArray != None and len(updatedScriptArray) > 0:
                                    updatedScriptList.add(updatedScriptArray[0])
                            print("INFO: {} imported.\n".format(scriptPath))
                        except Exception as ex:
                            hasError = hasError + 1
                            print("ERROR: Request URL:%s failed, %s" % (url, str(ex)))
                            return hasError
                    except Exception as reason:
                        hasError = hasError + 1
                        print("ERROR: Import %s failed, Unknown error %s" % (scriptPath, str(reason)))
                        print(traceback.format_exc())
        if len(newScriptList) > 0:
            print("INFO: New scripts: {}".format(','.join(newScriptList)))
        if len(updatedScriptList) > 0:
            print("INFO: Update base information or generate new version scripts: {}".format(','.join(updatedScriptList)))

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
    status = importJsonInfo(params)
    exit(status)
