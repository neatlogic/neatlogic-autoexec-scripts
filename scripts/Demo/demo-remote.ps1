Param(
	[string]$tinput="", 
	[string]$tjson="", 
	[int]$count=100
	)
#Param arguments define must at the begin of the script file

function usage(){
    write-host("Usage: --tinput TextValue --json JsonString")
    write-host("       --tinput TextValue")
    write-host("       --json JsonString")
}

If ($tinput -eq "")
{
	usage
}

write-host("Get option tinput:$tinput")
write-host("Get option tjson:$tjson")
write-host("Get option tjson:$count")

#Get arguments by array $args, $args[0], $args[1]
write-host("There are a total of $($args.count) arguments")
for ( $i = 0; $i -lt $args.count; $i++ ) 
{
    write-host("Argument  $i is $($args[$i])")
} 

"{" | Out-File -FilePath ".\output.json" 
"`"outtext`":`"Test value`"" | Out-File -FilePath ".\output.json" -Append
"}" | Out-File -FilePath ".\output.json" -Append

