# 自动化客户化脚本开发

## 使用
### python3 在Linux上的安装后，更改python3位默认的python执行程序
执行autoscripts目录下的bin/setup.sh切换python3位默认python
```shell
cd autoscripts
./setup.sh
```

### 安装python3第三方库
```
cd autoscripts/media
./ins-modules.sh
```
### 升级python3第三方库
```
cd autoscripts/media
./upgrade-modules.sh
```
### 重新安装单个模块例子
```
cd autoscripts/media
./ins-modules.sh requests ijson
./upgrade-modules.sh requests ijson
```

### 环境变量初始化
```
cd autoscripts
source bin/setenv.sh
```