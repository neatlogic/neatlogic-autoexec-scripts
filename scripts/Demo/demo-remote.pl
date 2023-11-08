#!/usr/bin/perl

use FindBin;
use lib "$FindBin::Bin/lib";

use strict;
use IO::File;

use AutoExecUtils;
use Getopt::Long;
Getopt::Long::Configure("pass_through");

sub usage {
    my $pname = $FindBin::Script;

    print("$pname --node <node json> --tinput <tinput> --tjson <tjson> --tselect <tselect> --tmultiselect <tmultiselect> --tpassword <tpassword> --tfile <tfile> --tnode <node id> --tdate <tdate> --ttime <ttime> --tdatetime <tdatetime>\n");
    exit(1);
}

sub main {
    $| = 1;    #不对输出进行buffer，便于实时看到输出日志
    AutoExecUtils::setEnv();

    my ( $ishelp, $node, $tinput, $tjson, $tselect, $tmultiselect, $tpassword, $tfile, $tnode, $tdate, $ttime, $tdatetime );

    GetOptions(
        'help'           => \$ishelp,
        'node=s'         => \$node,
        'tinput=s'       => \$tinput,
        'tjson=s'        => \$tjson,
        'tselect=s'      => \$tselect,
        'tmultiselect=s' => \$tmultiselect,
        'tpassword=s'    => \$tpassword,
        'tfile=s'        => \$tfile,
        'tnode=s'        => \$tnode,
        'tdate=s'        => \$tdate,
        'ttime=s'        => \$ttime,
        'tdatetime=s'    => \$tdatetime
    );

    my $hasOptErr = 0;
    if ( not defined($tinput) or $tinput eq '' ) {
        $hasOptErr = 1;
        print("ERROR: Option --tinput not defined.\n");
    }
    if ( not defined($tselect) or $tselect eq '' ) {
        $hasOptErr = 1;
        print("ERROR: Option --tselect not defined.\n");
    }

    if ( $hasOptErr == 1 ) {
        usage();
    }

    my $hasError = 0;

    my $scriptDir = $FindBin::Bin;
    chdir($scriptDir);

    print("=========GetOptions:\n");
    print("tinput:$tinput\n");
    print("tjson:$tjson\n");
    print("tselect:$tselect\n");
    print("tmultiselect:$tmultiselect\n");
    print("tpassword:$tpassword\n");
    print("tfile:$tfile\n");
    print("tnode:$tnode\n");
    print("tdate:$tdate\n");
    print("ttime:$ttime\n");
    print("tdatetime:$tdatetime\n");
    print("===================\n");

    my $fh = IO::File->new(">testfile.txt");
    if ( defined($fh) ) {
        $fh->print("This a test output file.\n");
        $fh->close();
    }

    print("INFO: Sleep 5 seconds to pretend do some jobs.\n");
    for ( my $i = 0 ; $i < 5 ; $i++ ) {
        print("INFO: Sleep $i....\n");
        sleep(1);
    }

    #Do some job
    #process output
    my $out = {};

    $out->{outtext}     = "this is the text out value";
    $out->{outpassword} = "{RC4}xxxxxxxxxx";
    $out->{outfile}     = "testfile.txt";
    $out->{outjson}     = '{"key1":"value1", "key2":"value2"}';
    $out->{outcsv}      = q{"name","sex","age"\n"张三“,"男“,"30"\n"李四","女“,"35"};
    AutoExecUtils::saveOutput($out);

    print("TMPDIR:$ENV{TMPDIR}\n");

    return $hasError;
}

exit main();

