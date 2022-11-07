function DO_CMD() {
    echo Exec command: $@
    eval "$@"
    EXIT_CODE=$?
    if [ $EXIT_CODE != 0 ]; then
        HAS_ERROR=1
        echo ERROR:: Execute $@ failed.
        exit $EXIT_CODE
    else
        echo FINE:: Execute success.
    fi
}

function SUDO_CMD() {
    USER=$1
    shift
    echo "Exec command: su - '$USER' -c '$@'"
    eval "su - '$USER' -c '$@'"
    EXIT_CODE=$?
    if [ $EXIT_CODE != 0 ]; then
        HAS_ERROR=1
        echo ERROR:: Execute $@ failed.
        exit $EXIT_CODE
    else
        echo FINE:: Execute success.
    fi
}

#获取路径下的某个文件名称的目录名称
function GET_DIRNAME() {
    C_FILE_DIR=$1
    C_FILE_NAME=$2
    shift

    if [ ! -d "$C_FILE_DIR" ]; then
        echo ERROR: Directory $C_FILE_DIR not found.
        exit 1
    fi 

    if [ ! -n "$C_FILE_NAME" ]; then
        echo ERROR:: FileName must defined.
        exit 1
    fi 

    for T_DIR in `ls $C_FILE_DIR`
    do
        if [[ "$T_DIR" == "$C_FILE_NAME"* && -d "$C_FILE_DIR/$T_DIR" ]] ; then 
            DIR_NAME="$T_DIR"
            break 
        fi
    done 

    if [ -n $DIR_NAME ]; then
        echo Directory Name:$DIR_NAME.
    else
        echo Directory $C_FILE_DIR Not found $C_FILE_NAME child dir.
        exit 1
    fi
}
