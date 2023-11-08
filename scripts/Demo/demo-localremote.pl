#!/usr/bin/perl
use strict;

use FindBin;
use IO::File;
use JSON;
use Getopt::Long;

use AutoExecUtils;

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
        'node:s'         => \$node,
        'tinput:s'       => \$tinput,
        'tjson:s'        => \$tjson,
        'tselect:s'      => \$tselect,
        'tmultiselect:s' => \$tmultiselect,
        'tpassword:s'    => \$tpassword,
        'tfile:s'        => \$tfile,
        'tnode:s'        => \$tnode,
        'tdate:s'        => \$tdate,
        'ttime:s'        => \$ttime,
        'tdatetime:s'    => \$tdatetime
    );

    my $hasOptErr = 0;

    my $nodeObj;
    if ( defined($node) and $node ne '' ) {
        $nodeObj = from_json($node);
    }
    else {
        my $nodeJson = $ENV{AUTOEXEC_NODE};
        if ( defined($nodeJson) and $nodeJson ne '' ) {
            $nodeObj = from_json($nodeJson);
        }
    }
    if ( not defined($nodeObj) ) {
        $hasOptErr = 1;
    }

    if ( not defined($tinput) or $tinput eq '' ) {
        $hasOptErr = 1;
    }

    if ( $hasOptErr == 1 ) {

        #usage();
    }

    my $hasError = 0;

    print("=========GetOptions:\n");
    if ( defined($nodeObj) ) {
        $nodeObj->{password} = '********';
        print( "execute for node:", to_json( $nodeObj, { pretty => 1 } ), "\n" );
    }

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

    #Connect to the node and Do some job
    #print( "INFO: Do some job to node:", to_json($node), "\n" );

    #process output
    my $out = {};

    $out->{outtext}     = "this is the text out value";
    $out->{outpassword} = "{RC4}xxxxxxxxxx";
    $out->{outfile}     = "testfile.txt";
    $out->{outjson}     = '{"key1":"value1", "key2":"value2"}';
    $out->{outcsv}      = q{"name","sex","age"\n"张三“,"男“,"30"\n"李四","女“,"35"};
    AutoExecUtils::saveOutput($out);

    return $hasError;
}

exit main();

