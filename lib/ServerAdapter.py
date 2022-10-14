#!/usr/bin/python
# -*- coding: utf-8 -*-
"""
 Copyright © 2017 TechSure<http://www.techsure.com.cn/>
"""
from ast import Return
import os
import traceback
import stat
import fcntl
from filelock import FileLock
import ssl
import time
import json
import base64
import requests
import urllib.request
import urllib.parse
from urllib.error import URLError
from urllib.error import HTTPError
from hashlib import sha256
import hmac
import base64

from AutoExecError import AutoExecError


class ServerAdapter:

    def __init__(self, context):
        ssl._create_default_https_context = ssl._create_unverified_context

        # api路径的映射
        self.apiMap = {
            'register': '/codedriver/api/rest/autoexec/tool/register',
            'getParams': '/codedriver/api/rest/autoexec/job/create/param/get',
            'getNodes': '/codedriver/api/binary/autoexec/job/phase/nodes/download',
            'fetchFile': '/codedriver/api/binary/file/download',
            'fetchScript': '/codedriver/api/rest/autoexec/job/phase/operation/script/get/forautoexec',
            'getScript': '/codedriver/api/rest/autoexec/script/active/version/get',
            'getAccount': '/codedriver/api/rest/resourcecenter/resource/account/get',
            'getInspectConf': '/codedriver/api/rest/autoexec/inspect/nodeconf/get',
            'updateInspectStatus': '/codedriver/api/rest/cmdb/cientity/updateinspectstatus',
            'updateNodeStatus': '/codedriver/api/rest/autoexec/job/phase/node/status/update',
            'updatePhaseStatus': '/codedriver/api/rest/autoexec/job/phase/status/update',
            'fireNextGroup': '/codedriver/api/rest/autoexec/job/next/group/fire',
            'fireNextPhase': '/codedriver/api/rest/autoexec/job/next/phase/fire',
            'informRoundEnded': '/codedriver/api/rest/autoexec/job/phase/inform/round/end',
            'updateJobStatus': '/codedriver/api/rest/autoexec/job/status/update',
            'exportJobEnv': '/codedriver/api/rest/autoexec/job/env/update',
            'setResourceInspectJobId': '/codedriver/api/rest/autoexec/job/resource/inspect/update',
            'getCmdbCiAttrs': '/codedriver/api/rest/cmdb/cientity/attrentity/get',
            'getAccessEndpoint': '/codedriver/api/rest/resourcecenter/resource/accessendpoint/get',
            'globalLock': '/codedriver/api/rest/global/lock',
            'getDeployIdPath': '/codedriver/api/rest/resourcecenter/resource/appidmoduleidenvid/get',
            'getDeployRunnerGroup': '/codedriver/api/rest/deploy/runner/group/get/forautoexec',
            'getCITxtFilePathList': '/codedriver/api/rest/inspect/configfile/resource/path/list',
            'uploadFile': '/codedriver/api/binary/file/upload',
            'removeUploadedFile': '/codedriver/api/rest/file/delete',
            'txtFileInspectSave': '/codedriver/api/rest/inspect/configfile/audit/save'
        }

        self.context = context
        self.fileFeteched = context.fileFeteched
        self.scriptFetched = context.scriptFetched
        serverBaseUrl = context.config['server']['server.baseurl']
        if(serverBaseUrl[-1] == '/'):
            serverBaseUrl = serverBaseUrl[0:-1]
        self.serverBaseUrl = serverBaseUrl

        self.serverUserName = context.config['server']['server.username']
        self.serverPassword = context.config['server']['server.password']
        # self.authToken = 'Basic ' + str(base64.b64encode(bytes(self.serverUserName + ':' + self.serverPassword, 'utf-8')).decode('ascii', errors='ignore'))

    def addHeaders(self, request, headers):
        for k, v in headers.items():
            if isinstance(v, str):
                request.add_header(k, v)
            else:
                request.add_header(k, str(v))

    def getSignHeaders(self, apiUri, postBody=None):
        signContent = self.serverUserName + '#' + apiUri + '#'
        if postBody is not None and postBody != '':
            signContent = signContent + base64.b64encode(postBody.encode('utf-8')).decode('utf-8')

        digest = 'Hmac ' + hmac.new(self.serverPassword.encode('utf-8'), signContent.encode('utf-8'), digestmod=sha256).hexdigest()
        headers = {
            'Tenant': self.context.tenant,
            'AuthType': 'hmac',
            'x-access-key': self.serverUserName,
            'Authorization': digest
        }
        return headers

    def signRequest(self, request, apiUri, postBody=None):
        headers = self.getSignHeaders(apiUri, postBody)
        for k, v in headers.items():
            request.add_header(k, v)

    def httpPOST(self, apiUri, params):
        if apiUri[0] != "/":
            apiUri = '/' + apiUri

        url = self.serverBaseUrl + apiUri
        headers = {'Content-Type': 'application/x-www-form-urlencoded; charset=utf-8'}

        postBody = json.dumps(params, ensure_ascii=False)
        req = urllib.request.Request(url, postBody.encode('utf-8'))
        self.addHeaders(req, headers)
        try:
            self.signRequest(req, apiUri, postBody)
            response = urllib.request.urlopen(req)
        except HTTPError as ex:
            errMsg = ex.code
            if ex.code > 500:
                content = ex.read()
                errObj = json.loads(content)
                errMsg = errObj['Message']
            raise AutoExecError("Request failed, {}\n".format(errMsg))
        except URLError as ex:
            raise AutoExecError("Request url:{} failed, {}\n".format(url, ex.reason))
        return response

    def httpGET(self, apiUri, params):
        if apiUri[0] != "/":
            apiUri = '/' + apiUri

        data = urllib.parse.urlencode(params)
        apiUri = apiUri + '?' + data

        url = self.serverBaseUrl + apiUri
        req = urllib.request.Request(url)

        try:
            self.signRequest(req, apiUri)
            response = urllib.request.urlopen(req)
        except HTTPError as ex:
            errMsg = ex.code
            if ex.code > 500:
                content = ex.read()
                errObj = json.loads(content)
                errMsg = errObj['Message']
            raise AutoExecError("Request failed, {}".format(errMsg))
        except URLError as ex:
            raise AutoExecError("Request url:{} failed, {}".format(url, ex.reason))

        return response

    def httpJSON(self, apiUri, params):
        if apiUri[0] != "/":
            apiUri = '/' + apiUri

        url = self.serverBaseUrl + apiUri
        headers = {'Content-Type': 'application/json; charset=utf-8'}

        postBody = json.dumps(params, ensure_ascii=False)
        req = urllib.request.Request(url, postBody.encode('utf-8'))
        self.addHeaders(req, headers)
        try:
            self.signRequest(req, apiUri, postBody)
            response = urllib.request.urlopen(req)
        except HTTPError as ex:
            errMsg = ex.code
            if ex.code > 500:
                content = ex.read()
                errObj = json.loads(content)
                errMsg = errObj['Message']
            raise AutoExecError("Request failed, {}".format(errMsg))
        except URLError as ex:
            raise AutoExecError("Request url:{} failed, {}".format(url, ex.reason))

        return response

    # 获取作业的运行参数文件params.json
    def getParams(self):
        params = {
            'jobId': self.context.jobId
        }

        lastModifiedTime = 0
        paramsFilePath = self.context.paramsFilePath
        if os.path.exists(paramsFilePath):
            lastModifiedTime = os.path.getmtime(paramsFilePath)
        params['lastModified'] = lastModifiedTime

        paramsFile = None
        try:
            paramsFile = open(paramsFilePath, 'a+')
            fcntl.flock(paramsFile, fcntl.LOCK_EX)

            response = self.httpJSON(self.apiMap['getParams'],  params)
            charset = response.info().get_content_charset()
            content = response.read().decode(charset, errors='ignore')
            retObj = json.loads(content)
            if response.status == 200:
                if retObj.get('Status') == 'OK':
                    params = retObj['Return']
                    paramsFile.truncate(0)
                    paramsFile.write(json.dumps(params, indent=4, ensure_ascii=False))
                    return params
                else:
                    raise "Get parameters for job {} failed, {}".format(self.context.jobId, retObj['Message'])
            else:
                raise "Get parameters for job {} failed, status code:{} {}".format(self.context.jobId, response.status, content)
        except:
            raise
        finally:
            if paramsFile:
                fcntl.flock(paramsFile, fcntl.LOCK_UN)
                paramsFile.close()

    # 下载运行作业或作业某个阶段的运行目标节点
    def getNodes(self, phase=None, groupNo=None):
        params = {
            'jobId': self.context.jobId,
            'runnerId': self.context.runnerId,
            'passThroughEnv': self.context.passThroughEnv,
            'phase': '',
            'nodeFrom': 'job'
        }

        if phase is not None:
            params['phase'] = phase
            params['nodeFrom'] = 'phase'

        if groupNo is not None:
            params['groupNo'] = groupNo
            params['nodeFrom'] = 'group'

        lastModifiedTime = 0
        nodesFilePath = self.context.getNodesFilePath(phaseName=phase, groupNo=groupNo)
        if os.path.exists(nodesFilePath):
            lastModifiedTime = os.path.getmtime(nodesFilePath)
        params['lastModified'] = lastModifiedTime

        nodesFile = None
        try:
            response = self.httpGET(self.apiMap['getNodes'],  params)

            if response.status == 200:
                nodesFile = open(nodesFilePath, 'a+')
                fcntl.flock(nodesFile, fcntl.LOCK_EX)
                nodesFile.truncate(0)
                for line in response:
                    nodesFile.write(str(line, encoding='utf-8'))

                if phase is not None:
                    self.context.phases[phase].nodesFilePath = nodesFilePath

            # elif response.status == 205:
                # 如果阶段playbook的运行节点跟pipeline一致，阶段节点使用作业节点
            #    pass
            elif response.status == 204:
                # 如果当前已经存在阶段节点文件，而且修改时间大于服务端，则服务端api给出204反馈，代表没有更改，不需要处理
                if phase is not None:
                    self.context.phases[phase].nodesFilePath = nodesFilePath
        finally:
            if nodesFile:
                fcntl.flock(nodesFile, fcntl.LOCK_UN)
                nodesFile.close()

    # 更新运行阶段某个节点的状态到服务端
    def pushNodeStatus(self, groupNo, phaseName, runNode, status, failIgnore=0, warnCount=0):
        if self.context.devMode:
            return {}

        params = {
            'jobId': self.context.jobId,
            'groupNo': groupNo,
            'phase': phaseName,
            'resourceId': runNode.resourceId,
            'host': runNode.host,
            'port': runNode.port,
            'status': status,
            'failIgnore': failIgnore,
            'warnCount': warnCount,
            'time': time.time(),
            'passThroughEnv': self.context.passThroughEnv
        }

        response = self.httpJSON(self.apiMap['updateNodeStatus'],  params)

        try:
            charset = response.info().get_content_charset()
            content = response.read().decode(charset, errors='ignore')
            return json.loads(content)
        except:
            raise

    # 更新运行端阶段的状态
    def pushPhaseStatus(self, groupNo, phaseName, phaseStatus, status):
        if self.context.devMode:
            return {}

        params = {
            'jobId': self.context.jobId,
            'groupNo': groupNo,
            'phase': phaseName,
            'status': status,
            'failNodeCount': phaseStatus.failNodeCount,
            'sucNodeCount': phaseStatus.sucNodeCount,
            'skipNodeCount': phaseStatus.skipNodeCount,
            'ignoreFailNodeCount': phaseStatus.ignoreFailNodeCount,
            'warnCount': phaseStatus.warnCount,
            'time': time.time(),
            'passThroughEnv': self.context.passThroughEnv
        }

        try:
            response = self.httpJSON(self.apiMap['updatePhaseStatus'],  params)
            charset = response.info().get_content_charset()
            content = response.read().decode(charset, errors='ignore')
            return json.loads(content)
        except:
            # 如果更新阶段状态失败，很可能是因为节点和阶段对应关系存在问题，更新节点文件的时间到1970-1-1
            # 促使下次运行主动更新节点文件
            found = False

            phaseNodesFilePath = self.context.getNodesFilePath(phaseName=phaseName)
            if (os.path.exists(phaseNodesFilePath)):
                found = True
                os.utime(phaseNodesFilePath, (0, 0))

            if not found:
                groupNodesFilePath = self.context.getNodesFilePath(groupNo=groupNo)
                if (os.path.exists(groupNodesFilePath)):
                    found = True
                    os.utime(groupNodesFilePath, (0, 0))

            if not found:
                nodesFilePath = self.context.getNodesFilePath()
                if (os.path.exists(nodesFilePath)):
                    os.utime(nodesFilePath, (0, 0))

            raise

    # 通知后端进行下一个组的调度，后端根据当前phase的全局节点运行状态判断是否调度下一个阶段
    def fireNextGroup(self, groupNo):
        if self.context.devMode:
            return {}

        params = {
            'jobId': self.context.jobId,
            'runnerId': self.context.runnerId,
            'groupNo': groupNo,
            'time': time.time(),
            'passThroughEnv': self.context.passThroughEnv
        }
        response = self.httpJSON(self.apiMap['fireNextGroup'],  params)

        try:
            charset = response.info().get_content_charset()
            content = response.read().decode(charset, errors='ignore')
            return json.loads(content)
        except:
            raise

    # 通知后端进行下一个阶段的调度，后端根据当前phase的全局节点运行状态判断是否调度下一个阶段
    def fireNextPhase(self, lastPhase):
        if self.context.devMode:
            return {}

        params = {
            'jobId': self.context.jobId,
            'runnerId': self.context.runnerId,
            'lastPhase': lastPhase,
            'time': time.time(),
            'passThroughEnv': self.context.passThroughEnv
        }
        response = self.httpJSON(self.apiMap['fireNextPhase'],  params)

        try:
            charset = response.info().get_content_charset()
            content = response.read().decode(charset, errors='ignore')
            return json.loads(content)
        except:
            raise

    # 通知后端进行下一个阶段的调度，后端根据当前phase的全局节点运行状态判断是否调度下一个阶段
    def informRoundEnded(self, groupNo, phaseName, roundNo):
        if self.context.devMode:
            return {}

        params = {
            'jobId': self.context.jobId,
            'runnerId': self.context.runnerId,
            'groupNo': groupNo,
            'phase': phaseName,
            'roundNo': roundNo,
            'time': time.time(),
            'pid': os.getpid(),
            'passThroughEnv': self.context.passThroughEnv
        }
        response = self.httpJSON(self.apiMap['informRoundEnded'],  params)

        try:
            charset = response.info().get_content_charset()
            content = response.read().decode(charset, errors='ignore')
            return json.loads(content)
        except:
            raise

    # 通知后端当前job已经暂停完成
    def jobPaused(self):
        if self.context.devMode:
            return {}

        params = {
            'jobId': self.context.jobId,
            'time': time.time(),
            'status': 'paused',
            'passThroughEnv': self.context.passThroughEnv
        }
        response = self.httpJSON(self.apiMap['updateJobStatus'],  params)

        try:
            charset = response.info().get_content_charset()
            content = response.read().decode(charset, errors='ignore')
            return json.loads(content)
        except:
            raise

    # 通知后端当前job已经Kill完成
    def jobKilled(self):
        if self.context.devMode:
            return {}

        params = {
            'jobId': self.context.jobId,
            'time': time.time(),
            'status': 'aborted',
            'passThroughEnv': self.context.passThroughEnv
        }
        response = self.httpJSON(self.apiMap['updateJobStatus'],  params)

        try:
            charset = response.info().get_content_charset()
            content = response.read().decode(charset, errors='ignore')
            return json.loads(content)
        except:
            raise

    # 下载操作运行参数的文件参数对应的文件，下载到cache目录
    def fetchFile(self, savePath, fileId):
        params = {
            'id': fileId
        }

        cachedFilePath = '{}/{}'.format(savePath, fileId)

        lockFilePath = cachedFilePath + '.lock'
        lockFile = None

        cachedFileTmp = None
        fileName = None
        response = None
        try:
            lockFile = open(lockFilePath, 'w+')
            fcntl.flock(lockFile, fcntl.LOCK_EX)

            fileName = self.fileFeteched.get(fileId)
            if fileName is not None:
                return fileName

            lastModifiedTime = 0
            if os.path.exists(cachedFilePath):
                lastModifiedTime = os.path.getmtime(cachedFilePath)
            params['lastModified'] = lastModifiedTime

            response = self.httpGET(self.apiMap['fetchFile'],  params)
            # 获取下载文件的文件名，服务端通过header传送文件名, 例如：'Content-Disposition: attachment; filename="myfile.tar.gz"'
            resHeaders = response.info()
            contentDisposition = resHeaders['Content-Disposition']
            if contentDisposition is not None:
                fileNameIdx = contentDisposition.index('filename="')
                if fileNameIdx > 0:
                    fileName = contentDisposition[fileNameIdx+10:-1]

            if response.status == 200:
                cachedFilePathTmp = cachedFilePath + '.tmp'
                cachedFileTmp = open(cachedFilePathTmp, 'wb')
                CHUNK = 16 * 1024
                while True:
                    chunk = response.read(CHUNK)
                    if not chunk:
                        break
                    cachedFileTmp.write(chunk)
                cachedFileTmp.close()
                cachedFileTmp = None

                if os.path.exists(cachedFilePath):
                    os.unlink(cachedFilePath)
                os.rename(cachedFilePathTmp, cachedFilePath)

            self.fileFeteched[fileId] = fileName

            return fileName
        except:
            raise AutoExecError("ERROR: Fetch file:{} to {} failed.\n".format(fileId, savePath))
        finally:
            if cachedFileTmp is not None:
                cachedFileTmp.close()
            if lockFile is not None:
                fcntl.flock(lockFile, fcntl.LOCK_UN)
                lockFile.close()

    # 从自定义脚本库下载脚本到脚本目录

    def fetchScript(self, pluginParentPath, scriptFileName, opId):
        scriptCatalog = None
        params = {
            'jobId': self.context.jobId,
            'operationId': opId
        }

        cachedFilePath = '%s/%s' % (pluginParentPath, opId)
        lastModifiedTime = 0

        lockFilePath = cachedFilePath + '.lock'
        lockFile = None

        #cachedFileTmp = None
        cachedFile = None
        response = None
        try:
            if self.scriptFetched.get(opId):
                return

            lockFile = open(lockFilePath, 'w+')
            fcntl.flock(lockFile, fcntl.LOCK_EX)

            if self.scriptFetched.get(opId):
                return

            if os.path.exists(cachedFilePath):
                lastModifiedTime = os.path.getmtime(cachedFilePath)
            params['lastModified'] = lastModifiedTime

            response = self.httpGET(self.apiMap['fetchScript'],  params)

            if response.status == 200:
                cachedFile = open(cachedFilePath, 'w')
                fcntl.flock(cachedFile, fcntl.LOCK_EX)
                charset = response.info().get_content_charset()
                content = response.read().decode(charset, errors='ignore')
                retObj = json.loads(content)
                scriptContent = retObj['Return']['script']
                cachedFile.write(scriptContent)
                os.chmod(cachedFilePath, stat.S_IRWXU)

                scriptCatalog = retObj['Return'].get('scriptCatalog')
                if scriptCatalog:
                    scriptFileName = '%s/%s' % (scriptCatalog, scriptFileName)
                    os.makedirs('%s/%s' % (pluginParentPath, scriptCatalog), exist_ok=True)

                scriptSavePath = '%s/%s' % (pluginParentPath, scriptFileName)
                if os.path.exists(scriptSavePath):
                    os.unlink(scriptSavePath)
                os.symlink(cachedFilePath, scriptSavePath)
            elif response.status == 205:
                resHeaders = response.info()
                scriptCatalog = resHeaders['ScriptCatalog']
                if scriptCatalog:
                    scriptFileName = '%s/%s' % (scriptCatalog, scriptFileName)

                scriptSavePath = '%s/%s' % (pluginParentPath, scriptFileName)
                if not os.path.exists(scriptSavePath):
                    os.makedirs('%s/%s' % (pluginParentPath, scriptCatalog), exist_ok=True)
                    os.symlink(cachedFilePath, scriptSavePath)

            self.scriptFetched[opId] = True

            return scriptCatalog

        except:
            raise AutoExecError("ERROR: Fetch {} custom script to {}/{} failed.\n".format(opId, pluginParentPath, scriptFileName))
        finally:
            if cachedFile is not None:
                fcntl.flock(cachedFile, fcntl.LOCK_UN)
                cachedFile.close()
            if lockFile is not None:
                fcntl.flock(lockFile, fcntl.LOCK_UN)
                lockFile.close()

    def getScript(self, scriptId):
        params = {
            'operationId': scriptId
        }

        url = self.serverBaseUrl + self.apiMap['getScript']
        try:
            response = self.httpGET(self.apiMap['getScript'],  params)

            if response.status == 200:
                charset = response.info().get_content_charset()
                content = response.read().decode(charset, errors='ignore')
                retObj = json.loads(content)
                return retObj['Return']
        except:
            raise

    # 注册native工具到服务端工具库
    def registerTool(self, toolObj):
        response = self.httpJSON(self.apiMap['register'],  toolObj)

        try:
            charset = response.info().get_content_charset()
            content = response.read().decode(charset, errors='ignore')
            return json.loads(content)
        except:
            raise

    def callGlobalLock(self, lockParams):
        # Lock reqeust
        # lockParams = {
        #     'lockId': None,
        #     'sysId': 343,
        #     'moduleId': 4353,
        #     'envId': 3,
        #     'sysName': 'mySys',
        #     'moduleName': 'myModule',
        #     'envName': 'SIT',
        #     'version': '2.0.0',
        #     'buildNo': '2',
        #     'action': 'lock',  # unlock
        #     'wait': 1, #0｜1，wait or not
        #     'lockTarget': 'workspace',  # build mirror env/app env/sql
        #     'lockMode': 'read',  # write
        #     'namePath': 'mySys/myModule/SIT'
        # }
        # Unlock request
        # lockParams = {
        #     'lockId': 83205734845,
        # }
        response = self.httpJSON(self.apiMap['globalLock'],  lockParams)

        try:
            charset = response.info().get_content_charset()
            content = response.read().decode(charset, errors='ignore')
            retObj = json.loads(content)
            if retObj.get('Status') == 'OK':
                lockInfo = retObj.get('Return')
                return lockInfo
            else:
                raise AutoExecError("Lock failed, {}".format(retObj['Message']))
        except:
            raise

    def exportEnv(self, name, value):
        if self.context.devMode:
            return {}

        params = {
            'jobId': self.context.jobId,
            'envName': name,
            'envValue': value,
            'time': time.time(),
            'passThroughEnv': self.context.passThroughEnv
        }

        response = self.httpJSON(self.apiMap['exportJobEnv'],  params)

        return

    def getAccount(self, resourceId, host, port, username, protocol, accountId):
        if self.context.devMode:
            return {}

        params = {
            'jobId': self.context.jobId,
            'resourceId': resourceId,
            'host': host,
            'port': port,
            'username': username,
            'accountId': accountId,
            'protocol': protocol
        }

        if username is None:
            username = 'none'

        try:
            response = self.httpJSON(self.apiMap['getAccount'],  params)
            charset = response.info().get_content_charset()
            content = response.read().decode(charset, errors='ignore')
            retObj = json.loads(content)
            if response.status == 200:
                if retObj.get('Status') == 'OK':
                    return retObj['Return']
                else:
                    raise AutoExecError("Get Account for {} user:{} failed, {}".format(protocol, username, retObj['Message']))
            else:
                raise AutoExecError("Get Account for {} user:{} failed, status code:{} {}".format(protocol, username, response.status, content))
        except Exception as ex:
            raise AutoExecError("Get Account for {} user:{} failed, {}".format(protocol, username, ex))

    def getInspectConf(self, ciType, resourceId):
        if self.context.devMode:
            return {}

        params = {
            'tenent': self.context.tenent,
            'jobId': self.context.jobId,
            'ciType': ciType,
            'resourceId': resourceId,
            'time': time.time()
        }

        try:
            response = self.httpJSON(self.apiMap['getInspectConf'],  params)
            charset = response.info().get_content_charset()
            content = response.read().decode(charset, errors='ignore')
            retObj = json.loads(content)
            if response.status == 200:
                if retObj.get('Status') == 'OK':
                    return retObj['Return']
                else:
                    raise AutoExecError("Get Inspect Config for {}/{} failed, {}".format(ciType, resourceId, retObj['Message']))
            else:
                raise AutoExecError("Get Inspect Config for {}/{} failed, status code:{} {}".format(ciType, resourceId, response.status, content))
        except Exception as ex:
            raise AutoExecError("Get Inspect Config for {}/{} failed, {}".format(ciType, resourceId, ex))

    def updateInspectStatus(self, ciType, resourceId, status, alertCount):
        if self.context.devMode:
            return {}

        params = {
            'jobId': self.context.jobId,
            'ciType': ciType,
            'ciEntityId': resourceId,
            'inspectStatus': status,
            'alertCount': alertCount,
            'inspectTime': int(time.time() * 1000)
        }

        try:
            response = self.httpJSON(self.apiMap['updateInspectStatus'],  params)
            charset = response.info().get_content_charset()
            content = response.read().decode(charset, errors='ignore')
            retObj = json.loads(content)
            if response.status == 200:
                if retObj.get('Status') == 'OK':
                    return True
                else:
                    raise AutoExecError("Get Inspect Config for {}/{} failed, {}".format(ciType, resourceId, retObj['Message']))
            else:
                raise AutoExecError("Get Inspect Config for {}/{} failed, status code:{} {}".format(ciType, resourceId, response.status, content))
        except Exception as ex:
            raise AutoExecError("Get Inspect Config for {}/{} failed, {}".format(ciType, resourceId, ex))

    def setResourceInspectJobId(self, resourceId, jobId, phaseName):
        if self.context.devMode:
            return {}

        params = {
            'resourceId': resourceId,
            'jobId': jobId,
            'phaseName': phaseName,
            'inspectTime': int(time.time() * 1000)
        }

        try:
            response = self.httpJSON(self.apiMap['setResourceInspectJobId'],  params)
            charset = response.info().get_content_charset()
            content = response.read().decode(charset, errors='ignore')
            retObj = json.loads(content)
            if response.status == 200:
                if retObj.get('Status') == 'OK':
                    return True
                else:
                    raise AutoExecError("Set resrouce({}) inspect job Id({}) faield, {}".format(resourceId, jobId, retObj['Message']))
            else:
                raise AutoExecError("Set resrouce({}) inspect job Id({}) faield, status code:{} {}".format(resourceId, jobId, response.status, content))
        except Exception as ex:
            raise AutoExecError("Set resrouce({}) inspect job Id({}) failed, {}".format(resourceId, jobId, ex))

    def getCmdbCiAttrs(self, resourceId, attrList):
        if self.context.devMode:
            return {}

        params = {
            'jobId': self.context.jobId,
            'ciEntityId': resourceId,
            'attrList': attrList
        }

        try:
            response = self.httpJSON(self.apiMap['getCmdbCiAttrs'],  params)
            charset = response.info().get_content_charset()
            content = response.read().decode(charset, errors='ignore')
            retObj = json.loads(content)
            if response.status == 200:
                if retObj.get('Status') == 'OK':
                    attrData = retObj['Return']['attrEntityData']
                    attrsMap = {}
                    for attrInfo in attrData.values():
                        name = attrInfo['name']
                        values = attrInfo['actualValueList']
                        if len(values) == 0:
                            attrsMap[name] = None
                        elif len(values) == 1:
                            attrsMap[name] = values[0]
                        else:
                            attrsMap = values

                    return attrsMap
                else:
                    raise AutoExecError("Get attributes for resourceId:{} failed, {}".format(resourceId, retObj['Message']))
            else:
                raise AutoExecError("Get attributes for resourceId:{} failed, status code:{} {}".format(resourceId, response.status, content))
        except Exception as ex:
            raise AutoExecError("Get attributes for resourceId:{} failed, {}".format(resourceId, ex))

    def getAccessEndpointConf(self, resourceId):
        if self.context.devMode:
            return {}

        params = {
            'jobId': self.context.jobId,
            'tenant': self.context.tenant,
            'resourceId': resourceId
        }

        try:
            response = self.httpJSON(self.apiMap['getAccessEndpoint'],  params)
            charset = response.info().get_content_charset()
            content = response.read().decode(charset, errors='ignore')
            retObj = json.loads(content)
            if response.status == 200:
                if retObj.get('Status') == 'OK':
                    return retObj['Return']
                else:
                    raise AutoExecError("Get AccessEndpoint Config for {} failed, {}".format(resourceId, retObj['Message']))
            else:
                raise AutoExecError("Get AccessEndpoint Config for {} failed, status code:{} {}".format(resourceId, response.status, content))
        except Exception as ex:
            raise AutoExecError("Get AccessEndpoint Config for {} failed, {}".format(resourceId, ex))

    def getDeployIdPath(self, namePath):
        namePath = namePath.strip()
        dpNames = namePath.split('/')
        partsName = ('sysName', 'moduleName', 'envName')
        params = {}
        for idx in range(0, len(dpNames)):
            params[partsName[idx]] = dpNames[idx]
        params['tenant'] = self.context.tenant

        try:
            response = self.httpJSON(self.apiMap['getDeployIdPath'],  params)
            charset = response.info().get_content_charset()
            content = response.read().decode(charset, errors='ignore')
            retObj = json.loads(content)
            if response.status == 200:
                if retObj.get('Status') == 'OK':
                    return retObj['Return']
                else:
                    raise AutoExecError("Get deploy id path for {} failed, {}".format(namePath, retObj['Message']))
            else:
                raise AutoExecError("Get deploy id path for {} failed, status code:{} {}".format(namePath, response.status, content))
        except Exception as ex:
            raise AutoExecError("Get deploy id path for {} failed, {}".format(namePath, ex))

    def getDeployRunnerGroup(self, sysId, moduleId, envId):
        idPath = '%s/%s/%s' % (sysId, moduleId, envId)
        params = {'sysId': sysId, 'moduleId': moduleId, 'envId': envId}
        params['tenant'] = self.context.tenant
        try:
            response = self.httpJSON(self.apiMap['getDeployRunnerGroup'],  params)
            charset = response.info().get_content_charset()
            content = response.read().decode(charset, errors='ignore')
            retObj = json.loads(content)
            if response.status == 200:
                if retObj.get('Status') == 'OK':
                    return retObj['Return']
                else:
                    raise AutoExecError("Get deploy runner group config for {} failed, {}".format(idPath, retObj['Message']))
            else:
                raise AutoExecError("Get deploy runner group config for {} failed, status code:{} {}".format(idPath, response.status, content))
        except Exception as ex:
            raise AutoExecError("Get deploy runner group config for {} failed, {}".format(idPath, ex))

    def getCITxtFilePathList(self, resourceId):
        try:
            response = self.httpJSON(self.apiMap['getCITxtFilePathList'],  {'resourceId': resourceId})
            charset = response.info().get_content_charset()
            content = response.read().decode(charset, errors='ignore')
            retObj = json.loads(content)
            if response.status == 200:
                if retObj.get('Status') == 'OK':
                    return retObj['Return'].get('tbodyList')
                else:
                    raise AutoExecError("Get config file list for ci:{} failed, {}".format(resourceId, retObj.get('Message')))
            else:
                raise AutoExecError("Get config file list for ci:{} failed, status code:{} {}".format(resourceId, response.status, content))
        except Exception as ex:
            raise AutoExecError("Get config file list for ci:{} failed, {}".format(resourceId, ex))

    def uploadFile(self, filePath, fileType='inspectconfigfile'):
        try:
            apiUri = self.apiMap['uploadFile']
            if apiUri[0] != "/":
                apiUri = '/' + apiUri + '?param=file&type=%s' % (fileType)

            url = self.serverBaseUrl + apiUri
            headers = self.getSignHeaders(apiUri)
            myFile = {'param': (None, 'file'),
                      'type': (None, fileType),
                      'file': (filePath, open(filePath, 'rb'), 'text/plain')}

            response = requests.post(url, files=myFile, headers=headers)

            retObj = response.json()
            if response.status_code == 200:
                if retObj.get('Status') == 'OK':
                    return retObj['Return']
                else:
                    raise AutoExecError("Upload file:{} failed, {}".format(filePath, retObj.get('Message')))
            else:
                raise AutoExecError("Upload file:{} failed, status code:{} {}".format(filePath, response.status_code, json.dumps(retObj)))
        except Exception as ex:
            raise AutoExecError("Upload file:{} failed, {}".format(filePath, ex))

    def removeUploadedFile(self, fileId):
        try:
            response = self.httpJSON(self.apiMap['removeUploadedFile'],  {'fileId': fileId})
            charset = response.info().get_content_charset()
            content = response.read().decode(charset, errors='ignore')
            retObj = json.loads(content)
            if response.status == 200:
                if retObj.get('Status') != 'OK':
                    raise AutoExecError("Remove uploaded file(fileId={}) failed, {}".format(fileId, retObj.get('Message')))
            else:
                raise AutoExecError("Remove uploaded file(fileId={}) failed, status code:{} {}".format(fileId, response.status, content))
        except Exception as ex:
            raise AutoExecError("Remove uploaded file(fileId={}) failed, {}".format(fileId, ex))

    def txtFileInspectSave(self, params):
        try:
            objHint = 'CI(%s) file(%s):%s' % (params.get('resourceId'), params.get('pathId'), params.get('path'))
            response = self.httpJSON(self.apiMap['txtFileInspectSave'],  params)
            charset = response.info().get_content_charset()
            content = response.read().decode(charset, errors='ignore')
            retObj = json.loads(content)
            if response.status == 200:
                if retObj.get('Status') != 'OK':
                    raise AutoExecError("Save Inspect for {} failed, {}".format(objHint, retObj.get('Message')))
            else:
                raise AutoExecError("Save Inspect for {} failed, status code:{} {}".format(objHint, response.status, content))
        except Exception as ex:
            raise AutoExecError("Save Inspect for {} failed, {}".format(objHint, ex))
