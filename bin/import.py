#!/usr/bin/python3
# -*- coding: utf-8 -*-
from genericpath import isdir, isfile
import initenv
import json
import os
import base64
import hmac
from hashlib import sha256
import traceback
import os.path
import re
import requests
import argparse

import Utils


def signRequest(username, password, headers, apiUri, postBody=None):
    signContent = username + '#' + apiUri + '#'
    if postBody is not None and postBody != '':
        signContent = signContent + base64.b64encode(postBody.encode('utf-8')).decode('utf-8')

    digest = 'Hmac ' + hmac.new(password.encode('utf-8'), signContent.encode('utf-8'), digestmod=sha256).hexdigest()
    headers['AuthType'] = 'hmac'
    headers['x-access-key'] = username
    headers['Authorization'] = digest


def importOneFile(opName, dataDir=None, scriptPath=None, params={}):
    hasError = 0

    serverUser = params.get('user')
    serverPass = params.get('password')
    url = params.get('url')
    uri = params.get('uri')
    headers = params.get('headers')

    try:
        # 获取当前脚本所在目录的相对路径作为工具目录
        catalogName = os.path.dirname(os.path.relpath(scriptPath, dataDir))
        catalogName = catalogName.replace('\\', '/')
        jsonList = []
        jsonInfo = {}
        # 获取脚本描述.json文件
        if not os.path.exists(scriptPath + '.json'):
            return 0

        with open(scriptPath + '.json', 'r', encoding='utf-8') as scriptJsonFile:
            print("INFO: Try to import {}".format(scriptPath))
            try:
                data = json.load(scriptJsonFile)
            except Exception as ex:
                hasError = 1
                print("ERROR: Load json file %s failed, there is possible format error: %s" % (scriptPath + ".json", str(ex)))
                return hasError

            enabled = data.get('enabled', 1)
            if enabled == 0:
                print("WARN: Script %s not enabled, skip." % (scriptPath))
                return 0
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
            hasError = 1
            print("ERROR: Open script file %s failed, error: %s" % (scriptPath, str(ex)))
            return hasError
        try:
            postBody = json.dumps(jsonList, ensure_ascii=False)
            signRequest(serverUser, serverPass, headers, uri, postBody)
            res = requests.post(url, headers=headers, data=postBody.encode('utf-8'))
            content = res.json()
            if content.get('Status') != 'OK':
                raise Exception("Http request faield, %s" % json.dumps(content, ensure_ascii=False))
            result = content.get('Return')
            faultArray = result.get('faultArray')
            newScriptArray = result.get('newScriptArray')
            updatedScriptArray = result.get('updatedScriptArray')
            if faultArray != None and len(faultArray) > 0:
                hasError = 1
                print("ERROR: Import {} failed:".format(scriptPath))
                item = faultArray[0]
                faultMessages = item['faultMessages']
                for message in faultMessages:
                    print("\t", message)
                return hasError
            else:
                resultMessage = None
                if newScriptArray != None and len(newScriptArray) > 0:
                    resultMessage = 'INFO: {} added.\n'
                elif updatedScriptArray != None and len(updatedScriptArray) > 0:
                    resultMessage = 'INFO: {} updated.\n'
                else:
                    resultMessage = 'INFO: {} not changed.\n'
                print(resultMessage.format(scriptPath))
                return 0
        except Exception as ex:
            hasError = 1
            print("ERROR: Request URL:%s failed, %s" % (url, str(ex)))
            return hasError
    except Exception as reason:
        hasError = 1
        print("ERROR: Import %s failed, Unknown error %s" % (scriptPath, str(reason)))
        print(traceback.format_exc())
        return hasError


def importJsonInfo(params):
    hasError = 0
    uri = '/neatlogic/api/stream/autoexec/script/import/fromjson'
    params['uri'] = uri
    url = params.get('baseUrl') + uri
    params['url'] = url

    tenant = params.get('tenant')
    headers = {
        'Tenant': tenant,
        'Content-Type': 'application/json; charset=utf-8'
    }
    params['headers'] = headers

    dataDir = params.get('destDir')

    subDirList = params.get('catalogList')
    if subDirList is None or len(subDirList) == 0:
        if dataDir != None and dataDir != '':
            subDirList = [dataDir]
    else:
        for idx in range(0, len(subDirList)):
            subDirList[idx] = os.path.join(dataDir, subDirList[idx])

    for subDir in subDirList:
        print('INFO: Try to import scripts in directory ' + subDir + '...')
        if os.path.isfile(subDir):
            opName = os.path.basename(subDir)
            if not opName.endswith('.json'):
                scriptPath = subDir
                hasError = hasError + importOneFile(opName, dataDir=dataDir, scriptPath=scriptPath, params=params)
        else:
            for root, dirs, files in os.walk(subDir, topdown=False):
                for opName in files:
                    if not opName.endswith('.json'):
                        scriptPath = os.path.join(root, opName)
                        hasError = hasError + importOneFile(opName, dataDir=dataDir, scriptPath=scriptPath, params=params)


def parseArgs():
    parser = argparse.ArgumentParser(description='you should add those paramete')
    parser.add_argument("--baseurl", default='', help="Automation web console address")
    parser.add_argument("--tenant", default='', help="Tenant")
    parser.add_argument("--user", default='', help="username")
    parser.add_argument("--password", default='', help="passWord")
    parser.add_argument("--dir", default='', help="Script's directory")
    parser.add_argument('catalogs', nargs=argparse.REMAINDER, help="Sub direcgory in script direcgory")
    args = parser.parse_args()

    params = Utils.parseCmdArgs(args)

    return params


if __name__ == '__main__':
    params = parseArgs()
    status = importJsonInfo(params)
    exit(status)
