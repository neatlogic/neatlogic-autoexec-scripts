#!/usr/bin/env bash
#显示帮助信息
#####################################
function DO_CMD() {
    echo Exec command: $@
    $@

    if [ $? != 0 ]; then
        echo ERROR: Execute failed.
        exit $?
    else
        echo FIND: Execute success.
    fi
}

function DO_CMD_CONT() {
    echo Exec command: $@
    $@

    if [ $? != 0 ]; then
        echo ERROR: Execute failed.
        HAS_ERROR=1
    else
        echo FIND: Execute success.
    fi
}

function DO_CMD_IGNOR() {
    echo Exec command: $@
    $@

    if [ $? != 0 ]; then
        echo WARN: Execute failed.
        HAS_WARN=1
    else
        echo FIND: Execute success.
    fi
}

usage() {
    pname=$(basename $0)
    echo "$pname --tinput <tinput> --tjson <tjson> --tselect <tselect> --tmultiselect <tmultiselect> --tpassword <tpassword> --tfile <tfile> --tnode <node id> --tdate <tdate>
 -- ttime <ttime> --tdatetime <tdatetime>"
    exit 2
}

#参数处理,全部用长参数
######################################
parseOpts() {
    OPT_SPEC=":h-:"
    while getopts "$OPT_SPEC" optchar; do
        case "${optchar}" in
        -)
            case "${OPTARG}" in
            tinput)
                tinput="${!OPTIND}"
                OPTIND=$(($OPTIND + 1))
                ;;
            tjson)
                tjson="${!OPTIND}"
                OPTIND=$(($OPTIND + 1))
                ;;
            tselect)
                tselect="${!OPTIND}"
                OPTIND=$(($OPTIND + 1))
                ;;
            tmultiselect)
                tmultiselect="${!OPTIND}"
                OPTIND=$(($OPTIND + 1))
                ;;
            tpassword)
                tpassword="${!OPTIND}"
                OPTIND=$(($OPTIND + 1))
                ;;
            tfile)
                tfile="${!OPTIND}"
                OPTIND=$(($OPTIND + 1))
                ;;
            tnode)
                tnode="${!OPTIND}"
                OPTIND=$(($OPTIND + 1))
                ;;
            tdate)
                tdate="${!OPTIND}"
                OPTIND=$(($OPTIND + 1))
                ;;
            ttime)
                ttime="${!OPTIND}"
                OPTIND=$(($OPTIND + 1))
                ;;
            tdatetime)
                tdatetime="${!OPTIND}"
                OPTIND=$(($OPTIND + 1))
                ;;
            *)
                if [ "$OPTERR" = 1 ] && [ "${OPT_SPEC:0:1}" != ":" ]; then
                    echo "Unknown option --${OPTARG}" >&2
                fi
                ;;
            esac
            ;;
        h)
            usage
            exit 2
            ;;
        *)
            if [ "$OPTERR" != 1 ] || [ "${OPT_SPEC:0:1}" = ":" ]; then
                echo "Non-option argument: '-${OPTARG}'" >&2
            fi
            ;;
        esac
    done
}

parseOpts "$@"

echo "===get options======"
echo "tinput: $tinput"
echo "tjson: $tjson"
echo "tselect: $tselect"
echo "tmultiselect: $tmultiselect"
echo "tpassword: $tpassword"
echo "tfile: $tfile"
echo "tnode: $tnode"
echo "tdate: $tdate"
echo "ttime: $ttime"
echo "tdatetime: $tdatetime"

#Do some job
###########################################
echo "Do some jobs."
DO_CMD ls -l /tmp
#Save output
###########################################
echo "======Save output to output file"
outtext="This the outText"
outfile="testfile.txt"

if [ ! -z "$OUTPUT_PATH" ]; then
    cat <<EOF >"$OUTPUT_PATH"
{
    "outtext":"$outtext",
    "outfile":"$outfile"
}
EOF
fi
##########################################
