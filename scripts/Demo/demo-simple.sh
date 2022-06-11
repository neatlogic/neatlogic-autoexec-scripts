#!/bin/bash
if [ $# -lt 2 ]; then
    echo "ERROR: Nont enough arguments"
    echo "Arguments: start_date count"
    exit 1
fi

echo "START_DATE:$1"
echo "COUNT:$2"

echo "Do some job..."

#do some job
for idx in `seq 5 -1 0` ;
do
    echo "loop:$idx"
    sleep 1
done

#返回码，返回0代表成功，非0代表失败
RET_CODE=0
exit $RET_CODE

