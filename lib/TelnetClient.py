#!/usr/bin/python
# -*- coding: utf-8 -*-
"""
 Copyright © 2017 TechSure<http://www.techsure.com.cn/>
"""
import os
import telnetlib
import time
from datetime import date

class TelnetClient():

    def __init__(self, ip , port , username , password , timeout , backupdir):
        self.tn = telnetlib.Telnet()
        if port == None or port == '' :
            port = 23
        if timeout == None or timeout == '' :
            timeout = 3
        self.port = port
        self.ip = ip 
        self.timeout = timeout 
        self.username = username
        self.password = password
        backupdir = backupdir + '/' + ip 
        self.path = backupdir
        today = time.strftime("%Y-%m-%d_%H:%M:%S", time.localtime())
        filename = today + ".txt"
        self.filename = filename
        #执行cmd,等待返回的等待时间
        self.sleep = 3 

    # 此函数实现telnet登录主机
    def login( self ):
        try:
            self.tn.open( self.ip , self.port)
        except:
            print('ERROR:: %s connect failed.' %self.ip )
            return False

        self.tn.read_until(b'login: ',self.timeout )
        self.tn.write(self.username.encode('ascii') + b'\n')

        self.tn.read_until(b'Password: ',self.timeout )
        self.tn.write(self.password.encode('ascii') + b'\n')

        time.sleep(self.sleep)
        # read_very_eager()获取到的是的是上次获取之后本次获取之前的所有输出
        result = self.tn.read_very_eager().decode('ascii')
        if 'Login incorrect' not in result:
            print('INFO:: %s login success .'%self.ip)
            return True
        else:
            print('ERROR:: %s login failed ，maybe wrong username or password.' %self.ip)
            return False

    #保存文件
    def saveCfg(self , content):
        filename = self.filename
        path = self.path
        if( os.path.exists(path) == False ):
            os.makedirs(path)
        os.chdir(path)
        f = open( filename , 'w' ,encoding='utf-8')
        f.write(content)
        f.close()

    #执行命令
    def execCmd( self , command ):
        self.tn.write(command.encode('ascii')+b'\n')
        time.sleep(self.sleep)
        result = self.tn.read_very_eager().decode('ascii')
        print('INFO:: cmd result:%s' % result)


    # 执行备份命令，并保存到文件
    def backupCfg(self, command ):
        # 执行命令
        self.tn.write(command.encode('ascii')+b'\n')
        time.sleep(self.sleep)
        # 获取命令结果
        line = self.tn.read_very_eager().decode('ascii')
        print('INFO:: %s' % line)
        result = line 
        while( 'More' in line ):
            self.tn.write(" ".encode('ascii')+b'\n')
            time.sleep(self.sleep)
            line = self.tn.read_very_eager().decode('ascii')
            print('INFO:: %s' % line)
            result += line
        results = result.split('\n')
        content = ''
        for rs in results :
            if 'More' not in rs :
                content += rs + '\n'
        self.saveCfg(content)
 
    # 退出telnet
    def logout( self ) :
        self.tn.write(b"quit\n")

