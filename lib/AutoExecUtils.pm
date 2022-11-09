#!/usr/bin/perl
use strict;

package AutoExecUtils;
use FindBin;
use POSIX;
use Fcntl ':flock';
use IO::Socket;
use IO::Socket::UNIX;
use IO::Select;
use IO::File;
use File::Copy;
use File::Find;
use File::Path;
use Encode;
use Encode::Guess;
use File::Basename;
use Cwd;
use File::Glob qw(bsd_glob);
use JSON qw(from_json to_json);

my $READ_TMOUT = 86400;
my $TERM_CHARSET;

sub setEnv {
    umask(022);

    #hide password in command line
    hidePwdInCmdLine();
}

sub hidePwdInCmdLine {
    my @args = ($0);
    my $arg;
    for ( my $i = 0 ; $i <= $#ARGV ; $i++ ) {
        $arg = $ARGV[$i];
        if ( $arg =~ /[-]+\w*pass\w*[^=]/ or $arg =~ /[-]+\w*pwd\w*[^=]/ or $arg =~ /[-]+\w*account\w*[^=]/ ) {
            push( @args, $arg );
            push( @args, '******' );
            $i = $i + 1;
        }
        else {
            $arg =~ s/"password":\K".*?"/"******"/ig;
            push( @args, $arg );
        }
    }
    $0 = join( ' ', @args );
}

sub getFileContent {
    my ($filePath) = @_;
    my $content;

    if ( -f $filePath ) {
        my $size = -s $filePath;
        my $fh   = new IO::File("<$filePath");

        if ( defined($fh) ) {
            $fh->read( $content, $size );
            $fh->close();
        }
        else {
            print("WARN: File:$filePath not found or can not be readed.\n");
        }
    }

    return $content;
}

sub saveOutput {
    my ($outputData) = @_;
    my $outputPath = $ENV{OUTPUT_PATH};

    print("INFO: Try to save output to $outputPath.\n");
    if ( defined($outputPath) and $outputPath ne '' ) {
        my $outputDir = dirname($outputPath);
        if ( $outputDir ne '' and not -e $outputDir ) {
            mkpath($outputDir);
        }

        my $fh = IO::File->new(">$outputPath");
        if ( defined($fh) ) {
            print $fh ( to_json( $outputData, { utf8 => 0, pretty => 1 } ) );
            $fh->close();
        }
        else {
            die("ERROR: Can not open output file:$outputPath to write.\n");
        }
    }
    else {
        print("WARN: Could not save output file, because of environ OUTPUT_PATH not defined.\n");
    }
}

sub saveLiveData {
    my ($outputData) = @_;
    my $outputPath = $ENV{LIVEDATA_PATH};

    print("INFO: Try to save output to $outputPath.\n");
    if ( defined($outputPath) and $outputPath ne '' ) {
        my $outputDir = dirname($outputPath);
        if ( $outputDir ne '' and not -e $outputDir ) {
            mkpath($outputDir);
        }

        my $fh = IO::File->new(">$outputPath");
        if ( defined($fh) ) {
            print $fh ( to_json( $outputData, { utf8 => 0, pretty => 1 } ) );
            $fh->close();
        }
        else {
            die("ERROR: Can not open output file:$outputPath to write.\n");
        }
    }
    else {
        print("WARN: Could not save output file, because of environ OUTPUT_PATH not defined.\n");
    }
}

sub getMyNode {
    my $nodeJson = $ENV{AUTOEXEC_NODE};
    my $node;

    if ( defined($nodeJson) and $nodeJson ne '' ) {
        $node = from_json($nodeJson);
    }

    return $node;
}

sub getNode {
    my ($resourceId) = @_;
    my $nodesJsonPath = $ENV{AUTOEXEC_NODES_PATH};

    my $node = {};
    my $fh   = IO::File->new("<$nodesJsonPath");
    if ( defined($fh) ) {
        my $line;
        while ( $line = $fh->getline() ) {
            my $cNode = from_json($line);
            if ( $cNode->{resourceId} == $resourceId ) {
                $node = $cNode;
                last;
            }
        }
        $fh->close();
    }

    return $node;
}

sub getNodePipeFile {
    my ( $jobPath, $phaseName, $nodeInfo ) = @_;
    return "$jobPath/log/$phaseName/$nodeInfo->{host}-$nodeInfo->{port}-$nodeInfo->{resourceId}.txt.run.pipe";
}

sub loadNodeOutput {
    my $output     = {};
    my $outputPath = $ENV{NODE_OUTPUT_PATH};

    # 加载操作输出并进行合并
    if ( -f $outputPath ) {
        my $outputFile = IO::File->new("<$outputPath");
        if ( defined($outputFile) ) {
            if ( flock( $outputFile, LOCK_EX ) ) {
                my $content = getFileContent($outputPath);
                flock( $outputFile, LOCK_UN );
                $outputFile->close();
                $output = from_json($content);
            }
        }
    }
    else {
        print("WARN: Output file $outputPath not exist.\n");
    }

    return $output;
}

sub getOutput {
    my ($varKey) = @_;
    my $lastDotPos = rindex( $varKey, '.' );

    my $varName   = substr( $varKey, $lastDotPos + 1 );
    my $pluginId  = substr( $varKey, 0, $lastDotPos );
    my $output    = loadNodeOutput();
    my $pluginOut = $output->{$pluginId};

    my $val;
    if ( defined($pluginOut) ) {
        $val = $pluginOut->{$varName};
    }

    return $val;
}

sub doInteract {
    my (%args) = @_;

    my $pipeFile = $args{pipeFile};    # 管道文件的全路径
    my $message  = $args{message};     # 交互操作文案
    my $opType   = $args{opType};      # 类型：button|input|select|mselect
    my $title    = $args{title};       # 交互操作标题
    my $opts     = $args{options};     # 操作列表json数组，譬如：["commit","rollback"]
    my $role     = $args{role};        # 可以操作此操作的角色，如果空代表不控制

    $args{pipeFile} = $pipeFile;

    my $optsMap = {};

    for my $opt (@$opts) {
        $optsMap->{$opt} = 1;
    }
    my $pipeDescFile = "$pipeFile.json";

    my $pipe;

    END {
        local $?;
        if ( defined($pipe) ) {
            $pipe->close();
        }
        unlink($pipeFile);
        unlink($pipeDescFile);
    }

    my $userId;
    my $enter;

    if ( -e $pipeFile ) {
        unlink($pipeFile);
    }

    my $pipeDescFH = IO::File->new(">$pipeDescFile");
    if ( not defined($pipeDescFH) ) {
        die("ERROR: Create file $pipeDescFile failed $!\n");
    }
    print $pipeDescFH ( to_json( \%args ) );
    close($pipeDescFH);

    POSIX::mkfifo( $pipeFile, 0700 );
    $pipe = IO::File->new("+<$pipeFile");

    if ( defined($pipe) ) {
        my $hasGetInput = 0;
        while ( $hasGetInput == 0 ) {
            print("[Wait Interact]$message\n");
            STDOUT->flush();

            my $select       = IO::Select->new( $pipe, \*STDIN );
            my @inputHandles = $select->can_read($READ_TMOUT);

            if ( not @inputHandles ) {
                print("\nWARN: Wait user input timeout or execution aborted.\n");
                $enter = 'force-exit';
                if ( defined($pipe) ) {
                    $pipe->close();
                }
                unlink($pipeFile);
                die("ERROR: Read from input aborted.");
            }

            foreach my $inputHandle (@inputHandles) {
                $enter = $inputHandle->getline();

                if ( not defined($enter) ) {
                    $enter = 'force-exit';
                }

                $enter =~ s/^\s*|\s*$//g;
                if ( $enter =~ /^\[(.*?)\]# (.*)$/ ) {
                    $userId = $1;
                    $enter  = $2;
                }
                print("INFO: Get input:$enter\n");

                if ( $enter eq 'force-exit' ) {
                    $hasGetInput = 1;
                }
                elsif ( $opType eq 'mselect' ) {
                    my $selVals = from_json($enter);
                    $hasGetInput = 1;
                    if ( scalar(@$selVals) == 0 ) {
                        $hasGetInput = 0;
                    }
                    foreach my $selVal (@$selVals) {
                        if ( not $optsMap->{$selVal} ) {
                            $hasGetInput = 0;
                            last;
                        }
                    }
                }
                elsif ( $opType eq 'input' or $optsMap->{$enter} == 1 ) {
                    $hasGetInput = 1;
                }

                if ( $hasGetInput == 0 ) {
                    print("WARN: Invalid input value:$enter, try again.\n");
                }
            }
        }
    }
    else {
        die("ERROR: Can not get input $!\n");
    }

    if ( defined($pipe) ) {
        $pipe->close();
    }
    unlink($pipeFile);
    unlink($pipeDescFile);

    if ( $enter eq 'force-exit' ) {
        undef($enter);
    }

    return ( $userId, $enter );
}

sub informNodeWaitInput {
    my (%args) = @_;

    # $args{phaseName}   # 当前phase名称
    # $args{resourceId}  # 节点Id
    # $args{pipeFile};   # 管道文件的全路径
    # $args{message};    # 交互操作文案
    # $args{opType};     # 类型：button|input|select|mselect
    # $args{title};      # 交互操作标题
    # $args{options};    # 操作列表json数组，譬如：["commit","rollback"]
    # $args{role};       # 可以操作此操作的角色，如果空代表不控制

    my $sockPath   = $ENV{AUTOEXEC_JOB_SOCK};
    my $phaseName  = $args{phaseName};
    my $resourceId = $args{resourceId};

    my $destStatus = 'waitInput';
    my $doClean;
    if ( defined( $args{clean} ) and $args{clean} == 1 ) {
        $destStatus = 'running';
        $doClean    = 1;
    }

    if ( -e $sockPath ) {
        eval {
            my $client = IO::Socket::UNIX->new(
                Peer    => $sockPath,
                Type    => IO::Socket::SOCK_DGRAM,
                Timeout => 10
            );

            my $request = {};
            $request->{action}     = 'informNodeWaitInput';
            $request->{phaseName}  = $phaseName;
            $request->{resourceId} = $resourceId;
            $request->{clean}      = $doClean;

            if (    %args
                and defined( $args{pipeFile} )
                and defined( $args{options} )
                and ref( $args{options} ) eq 'ARRAY' )
            {

                if ( not defined( $args{opType} ) ) {
                    $args{opType} = 'button';
                }
                if ( not defined( $args{message} ) ) {
                    $args{message} = 'Please select';
                }
                $request->{interact} = {
                    title    => $args{title},      #交互操作标题
                    opType   => $args{opType},     #类型：button|input|select|mselect
                    message  => $args{message},    #交互操作文案
                    options  => $args{options},    #操作列表json数组，譬如：["commit","rollback"]
                    role     => $args{role},       #可以操作此操作的角色，如果空代表不控制
                    pipeFile => $args{pipeFile}    #交互管道文件
                };
            }
            else {
                $request->{interact} = undef;
            }

            $client->send( to_json($request) );
            $client->close();
            print("INFO: Inform runner udpate status to $destStatus success.\n");
        };
        if ($@) {
            print("WARN: Inform runner udpate status to $destStatus failed, $@\n");
        }
    }
    else {
        print("WARN: Inform runner update status to $destStatus failed:socket file $sockPath not exist.\n");
    }
    return;
}

sub setJobEnv {
    my ( $onlyInProcess, $items ) = @_;

    if ( not %$items ) {
        return;
    }

    my $sockPath = $ENV{AUTOEXEC_JOB_SOCK};

    if ( -e $sockPath ) {
        eval {
            my $client = IO::Socket::UNIX->new(
                Peer    => $sockPath,
                Type    => IO::Socket::SOCK_DGRAM,
                Timeout => 10
            );

            my $request = {};
            $request->{action}        = 'setEnv';
            $request->{onlyInProcess} = $onlyInProcess;

            $request->{items} = $items;

            $client->send( to_json($request) );
            $client->close();
        };
        if ($@) {
            die("ERROR: Set job enviroment failed, $@\n");
        }
    }

    return;
}

sub getNodes {
    my ( $phaseName, $groupNo ) = @_;
    my $nodesJsonPath = $ENV{AUTOEXEC_NODES_PATH};

    my $found        = 0;
    my $nodesJsonDir = dirname($nodesJsonPath);
    if ( defined($phaseName) and $phaseName ne '' ) {
        $nodesJsonPath = "$nodesJsonDir/nodes-ph-$phaseName.json";
        if ( -f $nodesJsonPath ) {
            $found = 1;
        }
    }

    if ( $found != 1 and defined($groupNo) and $groupNo ne '' ) {
        $nodesJsonPath = "$nodesJsonDir/nodes-gp-$groupNo.json";
        if ( -f $nodesJsonPath ) {
            $found = 1;
        }
    }

    if ( $found != 1 ) {
        $nodesJsonPath = "$nodesJsonDir/nodes.json";
    }

    my $nodesMap = {};
    my $fh       = IO::File->new("<$nodesJsonPath");
    if ( defined($fh) ) {
        my $line = $fh->getline();
        while ( $line = $fh->getline() ) {
            my $node = from_json($line);
            delete( $node->{password} );
            $nodesMap->{ $node->{resourceId} } = $node;
        }
        $fh->close();
    }

    return $nodesMap;
}

sub getNodesArray {
    my ( $phaseName, $groupNo ) = @_;
    my $nodesJsonPath = $ENV{AUTOEXEC_NODES_PATH};

    my $found        = 0;
    my $nodesJsonDir = dirname($nodesJsonPath);
    if ( defined($phaseName) and $phaseName ne '' ) {
        $nodesJsonPath = "$nodesJsonDir/nodes-ph-$phaseName.json";
        if ( -f $nodesJsonPath ) {
            $found = 1;
        }
    }

    if ( $found != 1 and defined($groupNo) and $groupNo ne '' ) {
        $nodesJsonPath = "$nodesJsonDir/nodes-gp-$groupNo.json";
        if ( -f $nodesJsonPath ) {
            $found = 1;
        }
    }

    if ( $found != 1 ) {
        $nodesJsonPath = "$nodesJsonDir/nodes.json";
    }

    my @nodesArray = ();
    my $fh         = IO::File->new("<$nodesJsonPath");
    if ( defined($fh) ) {
        my $line = $fh->getline();
        while ( $line = $fh->getline() ) {
            my $node = from_json($line);
            delete( $node->{password} );
            push( @nodesArray, $node );
        }
        $fh->close();
    }

    return \@nodesArray;
}

1;

