function usage(){
    log("Usage: --tinput TextValue --json JsonString")
    log("       --tinput TextValue")
    log("       --json JsonString")
}

function main(){
    Param($tinput)
    Param($tjson)

    log("Get option tinput:$tinput")
    log("Get option tinput:$tjson")

    Out-File -FilePath ".\output.json" "{"
    Out-File -FilePath ".\output.json" -Append "`"outtext`":`"Test value`""
    Out-File -FilePath ".\output.json" -Append "{"
}

exit(main)
