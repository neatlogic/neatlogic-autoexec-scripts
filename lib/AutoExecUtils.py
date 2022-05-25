#!/usr/bin/python
# -*- coding: utf-8 -*-
"""
 Copyright © 2017 TechSure<http://www.techsure.com.cn/>
"""

import os
import sys
import fcntl
import socket
import json
import time
import binascii
import pymongo
import configparser
import ServerAdapter

PYTHON_VER = sys.version_info.major
AUTOEXEC_CONTEXT = None


class Context:
    def __init__(self, config, tenent=None):
        self.devMode = False
        self.tenant = tenent
        self.config = config
        self.jobId = os.getenv('AUTOEXEC_JOBID')


def setEnv():
    pass


def getAutoexecContext():
    global AUTOEXEC_CONTEXT
    if AUTOEXEC_CONTEXT is None:
        homePath = os.path.split(os.path.realpath(__file__))[0]
        homePath = os.path.realpath(homePath + '/../../../')
        # 读取配置
        cfgPath = homePath + '/conf/config.ini'
        cfg = configparser.ConfigParser()
        cfg.read(cfgPath)

        config = {}
        for section in cfg.sections():
            config[section] = {}
            for confKey in cfg[section]:
                config[section][confKey] = cfg[section][confKey]

        serverPass = config['server']['server.password']
        passKey = config['server']['password.key']
        autoexecDBPass = config['autoexec']['db.password']

        MY_KEY = 'c3H002LGZRrseEPc'
        if passKey.startswith('{ENCRYPTED}'):
            passKey = _rc4_decrypt_hex(MY_KEY, passKey[11:])
            config['server']['password.key'] = passKey

        if serverPass.startswith('{ENCRYPTED}'):
            serverPass = _rc4_decrypt_hex(passKey, serverPass[11:])
            config['server']['server.password'] = serverPass

        if autoexecDBPass.startswith('{ENCRYPTED}'):
            autoexecDBPass = _rc4_decrypt_hex(passKey, autoexecDBPass[11:])
            config['autoexec']['db.password'] = autoexecDBPass

        AUTOEXEC_CONTEXT = Context(config, os.getenv('AUTOEXEC_TENANT'))
    return AUTOEXEC_CONTEXT


def saveOutput(outputData):
    outputPath = os.getenv('OUTPUT_PATH')
    print("INFO: Try save output to {}.\n".format(outputPath))
    if outputPath is not None and outputPath != '':
        outputDir = os.path.dirname(outputPath)
        if not os.path.exists(outputDir):
            outputPDir = os.path.dirname(outputDir)
            if not os.path.exists(outputPDir):
                os.mkdir(outputPDir)
            os.mkdir(outputDir)
        outputFile = open(outputPath, 'w')
        outputFile.write(json.dumps(outputData, ensure_ascii=False))
        outputFile.close()
    else:
        print("WARN: Could not save output file, because of environ OUTPUT_PATH not defined.\n")


def getOutput(output_path):
    outputFile = open(output_path, "r", encoding="utf-8")
    data = json.load(outputFile)
    outputFile.close()
    return data


def _rc4(key, data):
    x = 0
    box = list(range(256))
    for i in range(256):
        x = (x + box[i] + ord(key[i % len(key)])) % 256
        box[i], box[x] = box[x], box[i]
    x = y = 0
    out = []
    for char in data:
        x = (x + 1) % 256
        y = (y + box[x]) % 256
        box[x], box[y] = box[y], box[x]
        out.append(chr(ord(char) ^ box[(box[x] + box[y]) % 256]))
    return ''.join(out)


def _rc4_decrypt_hex(key, data):
    if PYTHON_VER == 2:
        return _rc4(key, binascii.unhexlify(data))
    elif PYTHON_VER == 3:
        return _rc4(key, binascii.unhexlify(data.encode("latin-1")).decode("latin-1"))


def getDB():
    context = getAutoexecContext()
    cfg = context.config
    dburl = cfg['autoexec']['db.url']
    dbname = cfg['autoexec']['db.name']
    dbuser = cfg['autoexec']['db.username']
    dbpwd = cfg['autoexec']['db.password']

    dbclient = pymongo.MongoClient(dburl, username=dbuser, password=dbpwd)
    mydb = dbclient[dbname]

    return (dbclient, mydb)


def getMyNode():
    nodeJson = os.environ['AUTOEXEC_NODE']
    node = None

    if nodeJson is not None and nodeJson != '':
        node = json.load(nodeJson)

    return node


def getNode(resourceId):
    matchNode = None

    if 'AUTOEXEC_NODES_PATH' in os.environ:
        nodesJsonPath = os.environ['AUTOEXEC_NODES_PATH']
        fh = open(nodesJsonPath, 'r')

        while True:
            line = fh.readline()
            if not line:
                break
            node = json.loads(line)
            if node['resourceId'] == resourceId:
                matchNode = node

    return matchNode


def loadNodeOutput():
    output = {}
    outputPath = os.getenv('NODE_OUTPUT_PATH')
    # 加载操作输出并进行合并
    if os.path.exists(outputPath):
        outputFile = None
        try:
            outputFile = open(outputPath, 'r')
            fcntl.lockf(outputFile, fcntl.LOCK_SH)
            content = outputFile.read()
            if content:
                output = json.loads(content)
        except Exception as ex:
            print('ERROR: Load output file:{}, failed {}\n'.format(outputPath, ex))
        finally:
            if outputFile is not None:
                fcntl.lockf(outputFile, fcntl.LOCK_UN)
                outputFile.close()
    else:
        print('WARN: Output file:{} not found.\n'.format(outputPath))

    return output


def informNodeWaitInput(resourceId, title=None, opType='button', message='Please select', options=None, role=None, pipeFile=None):
    sockPath = os.getenv('AUTOEXEC_WORK_PATH') + '/job.sock'
    phaseName = os.getenv('AUTOEXEC_PHASE_NAME')
    if os.path.exists(sockPath):
        try:
            client = socket.socket(socket.AF_UNIX, socket.SOCK_DGRAM)
            client.connect(sockPath)
            request = {}
            request['action'] = 'informNodeWaitInput'
            request['phaseName'] = phaseName
            request['resourceId'] = resourceId

            if (options is not None and (isinstance(options, tuple) or isinstance(options, list))):
                request['interact'] = {
                    'title': title,  # 交互操作标题
                    'opType': opType,  # 类型：button|input|select|mselect
                    'message': message,  # 交互操作文案
                    'options': options,  # 操作列表json数组，譬如：["commit","rollback"]
                    'role': role,  # 可以操作此操作的角色，如果空代表不控制
                    'pipeFile': pipeFile  # 交互管道文件
                }
            else:
                request['interact'] = None

            client.send(json.dumps(request))
            client.close()
            print("INFO: Inform node:{} udpate status to waitInput success.\n".format(resourceId))
        except Exception as ex:
            print("WARN: Inform node:{} udpate status to waitInput failed, {}\n".format(resourceId, ex))
    else:
        print("WARN: Inform node:{} update status to waitInput failed:socket file {} not exist.\n".format(resourceId, sockPath))
    return


def getNodes():
    nodesMap = {}

    if 'AUTOEXEC_NODES_PATH' in os.environ:
        nodesJsonPath = os.environ['AUTOEXEC_NODES_PATH']
        fh = open(nodesJsonPath, 'r')

        while True:
            line = fh.readline()
            if not line:
                break
            node = json.loads(line)
            nodesMap[node['resourceId']] = node

    return nodesMap


def isJson(data):
    valid = False
    try:
        json.load(data, encoding='utf-8')
        valid = True
    except ValueError:
        pass
    return valid

# 以下几种JSON字符都会影响json字符串转换成JSON格式


def handleJsonstr(jsonstr):
    # 将字符串里的单引号替换成双引号
    jsonstr = jsonstr.replace('\'', '\"')
    # 带u'的字符串
    jsonstr = jsonstr.replace('u\'', '\'')
    # None数据
    jsonstr = jsonstr.replace('None', '""')
    return jsonstr


# def getInspectConf(ciType, resourceId):
#     context = getAutoexecContext()
#     serverAdapter = ServerAdapter.ServerAdapter(context)
#     return serverAdapter.getInspectConf(ciType, resourceId)


def updateInspectStatus(ciType, resourceId, status, alertCount):
    context = getAutoexecContext()
    serverAdapter = ServerAdapter.ServerAdapter(context)
    return serverAdapter.updateInspectStatus(ciType, resourceId, status, alertCount)


def setResourceInspectJobId(resourceId, jobId, phaseName):
    context = getAutoexecContext()
    serverAdapter = ServerAdapter.ServerAdapter(context)
    return serverAdapter.setResourceInspectJobId(resourceId, jobId, phaseName)


def getCmdbCiAttrs(resourceId, attrList):
    context = getAutoexecContext()
    serverAdapter = ServerAdapter.ServerAdapter(context)
    return serverAdapter.getCmdbCiAttrs(resourceId, attrList)


def getAccessEndpointConf(resourceId):
    context = getAutoexecContext()
    serverAdapter = ServerAdapter.ServerAdapter(context)
    return serverAdapter.getAccessEndpointConf(resourceId)


def getScript(scriptId):
    context = getAutoexecContext()
    serverAdapter = ServerAdapter.ServerAdapter(context)
    return serverAdapter.getScript(scriptId)
