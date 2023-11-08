#!/usr/bin/python3
# -*- coding: utf-8 -*-
"""
 Copyright © 2017 NeatLogic
"""
import os
import sys
binPaths = os.path.split(os.path.realpath(__file__))
homePath = os.path.realpath(binPaths[0]+'/..')
sys.path.append(homePath + '/lib')
sys.path.append(homePath + '/plib')

os.environ['HISTSIZE'] = '0'
os.environ['PYTHONPATH'] = '{}/lib:{}/plib:{}'.format(homePath, homePath, os.getenv('PYTHONPATH'))
