#!/usr/bin/python
# -*- coding: utf-8 -*-
"""
 Copyright © 2017 TechSure<http://www.techsure.com.cn/>
"""
import os
import sys
import time
import binascii
import configparser
from filelock import FileLock

PYTHON_VER = sys.version_info.major


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


def _rc4_encrypt_hex(key, data):
    if PYTHON_VER == 2:
        return binascii.hexlify(_rc4(key, data))
    elif PYTHON_VER == 3:
        return binascii.hexlify(_rc4(key, data).encode("latin-1")).decode("latin-1")


def _rc4_decrypt_hex(key, data):
    if PYTHON_VER == 2:
        return _rc4(key, binascii.unhexlify(data))
    elif PYTHON_VER == 3:
        return _rc4(key, binascii.unhexlify(data.encode("latin-1")).decode("latin-1"))


def checkPidExists(pid):
    isExists = False
    try:
        os.kill(pid, 0)
        isExists = True
    except:
        pass
    return isExists


def getDateTimeStr():
    nowTime = time.localtime(time.time())
    timeStr = '{}-{:0>2d}-{:0>2d} {:0>2d}:{:0>2d}:{:0>2d}'.format(nowTime.tm_year, nowTime.tm_mon, nowTime.tm_mday, nowTime.tm_hour, nowTime.tm_min, nowTime.tm_sec)
    return timeStr


def getTimeStr():
    nowTime = time.localtime(time.time())
    timeStr = '{:0>2d}:{:0>2d}:{:0>2d} '.format(nowTime.tm_hour, nowTime.tm_min, nowTime.tm_sec)
    return timeStr


def parseCmdArgs(args):
    baseUrl = args.baseurl
    tenant = args.tenant
    user = args.user
    password = args.password
    destDir = args.dir

    homePath = os.path.split(os.path.realpath(__file__))[0]
    homePath = os.path.realpath(homePath + '/..')
    cfgPath = homePath + '/conf/config.ini'
    if os.path.isfile(cfgPath):
        cfg = configparser.ConfigParser()
        cfg.optionxform = str
        cfg.read(cfgPath)
        if baseUrl == '':
            baseUrl = cfg.get('server', 'server.baseurl')
        if user == '':
            user = cfg.get('server', 'server.username')
        if password == '':
            password = cfg.get('server', 'server.password')

            passKey = cfg.get('server', 'password.key')
            MY_KEY = 'c3H002LGZRrseEPc'
            if passKey.startswith('{ENCRYPTED}'):
                passKey = Utils._rc4_decrypt_hex(MY_KEY, passKey[11:])
                cfg.set('server', 'password.key', passKey)
            else:
                hasNoEncrypted = True

            if password.startswith('{ENCRYPTED}'):
                password = Utils._rc4_decrypt_hex(passKey, password[11:])
            else:
                hasNoEncrypted = True

            if hasNoEncrypted:
                if not passKey.startswith('{ENCRYPTED}'):
                    cfg.set('server', 'password.key', '{ENCRYPTED}' + Utils._rc4_encrypt_hex(MY_KEY, passKey))

                if not password.startswith('{ENCRYPTED}'):
                    cfg.set('server', 'server.password', '{ENCRYPTED}' + Utils._rc4_encrypt_hex(passKey, password))

                with FileLock(cfgPath):
                    fp = open(cfgPath, 'w')
                    cfg.write(fp)
                    fp.close()

        if destDir == '':
            destDir = homePath + '/scripts'

    if tenant == '':
        print("INFO: Tenant not set, use default:develop.\n", end='')
        tenant = 'develop'

    params = {
        'baseUrl': baseUrl,
        'tenant': tenant,
        'user': user,
        'password': password,
        'destDir': destDir
    }

    return params
