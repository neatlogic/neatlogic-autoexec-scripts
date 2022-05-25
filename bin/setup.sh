#!/bin/bash
AUTOSCRIPTS_DIR=$(cd $(dirname $0)/.. && pwd)
AUTOEXEC_PDIR=$(basename $AUTOSCRIPTS_DIR)

if [ "$AUTOEXEC_PDIR" = "systems" ]; then
    TS_HOME=$(
        cd $AUTOSCRIPTS_DIR/..
        pwd
    )
else
    TS_HOME=$AUTOSCRIPTS_DIR
fi

echo "DIR:$TS_HOME"

if [ ! -e /usr/bin/python2 ] && [ -e /usr/bin/python ]; then
    mv /usr/bin/python /usr/bin/python2
fi

if [ ! -e /usr/bin/pip2 ] && [ -e /usr/bin/pip ]; then
    mv /usr/bin/pip /usr/bin/pip2
fi

if [ -e "$TS_HOME/serverware/python/bin" ]; then
    rm -f /usr/bin/python
    ln -s $TS_HOME/serverware/python/bin/python3 /usr/bin/python
    rm -f /usr/bin/python3
    ln -s $TS_HOME/serverware/python/bin/python3 /usr/bin/python3
    rm -f /usr/bin/pip3
    ln -s $TS_HOME/serverware/python/bin/pip3 /usr/bin/pip3
fi

if [ -e /usr/bin/yum ]; then
    perl -i -pe 's/\/usr\/bin\/python(?=\b)/\/usr\/bin\/python2/g' /usr/bin/yum
fi

if [ -e /usr/libexec/urlgrabber-ext-down ]; then
    perl -i -pe 's/\/usr\/bin\/python(?=\b)/\/usr\/bin\/python2/g' /usr/libexec/urlgrabber-ext-down
fi
