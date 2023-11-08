#!/bin/bash
SCRIPT_DIR=$(dirname "$0")
AUTOEXEC_HOME="$SCRIPT_DIR/.."

GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m' # No Color

declare -a INS_SUC_PKGS
declare -a INS_FAIL_PKGS

PKGS=(requests filelock ijson)

if [[ $# > 0 ]]; then
    PKGS=($*)
fi

for PKG in ${PKGS[@]}; do
    pip3 install --upgrade $PKG -t $AUTOEXEC_HOME/plib

    if [[ $? -ne 0 ]]; then
        echo -e "${RED}ERROR: Install package:$PKG failed.${NC}"
        INS_FAIL_PKGS+=($PKG)
    else
        echo -e "${GREEN}Package:$PKG install success.${NC}"
        INS_SUC_PKGS+=($PKG)
    fi
done

for PKG in ${INS_SUC_PKGS[@]}; do
    echo -e "${GREEN}${PKG} install success.${NC}"
done

for PKG in ${INS_FAIL_PKGS[@]}; do
    echo -e "${RED}${PKG} install failed.${NC}"
done
