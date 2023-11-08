#!/usr/bin/perl
use strict;

sub usage{
    print("Usage: prog START_DATE COUNT\n");
    exit(1);
}

sub main{
    my $argsCount = scalar(@ARGV);
    if ( $argsCount < 2){
        print("Invalid arguments count.\n");
        usage();
    }

    my $retCode = 0;

    my $startDate = $ARGV[0];
    my $count = $ARGV[1];
    print("startDate:$startDate, count:$count\n");

    print("Do some job...\n");
    for(my $i=0; $i<5; $i++){
        print("Loop: $i\n");
        sleep(1);
    }

    #返回码，返回0代表成功，非0代表失败
    return $retCode;
}

exit(main());
