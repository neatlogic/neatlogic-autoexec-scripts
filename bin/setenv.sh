#!/usr/bin/bash
PROG_PATH=${BASH_SOURCE[0]}
echo $PROG_PATH
HOME_DIR=$(cd $(dirname "$PROG_PATH")/.. && pwd)

echo "NOTICE：Please source this script:. $HOME_DIR/bin/setenv.sh"

export PYTHONPATH=.:$HOME_DIR/lib:$HOME_DIR/plib
export PATH=.:$HOME_DIR/bin:$PATH

echo PYTHONPATH=$PYTHONPATH
echo PATH=$PATH
