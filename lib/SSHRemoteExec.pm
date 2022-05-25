#!/usr/bin/perl
use strict;

package SSHRemoteExec;
use FindBin;
use Expect;
use IO::File;
use IO::Pty;
use Encode;

use DeployUtils;

$Expect::Multiline_Matching = 0;

sub new {
    my ( $type, %args ) = @_;

    #args keys:host,port,username,password,supassword,verbose,cmd,scriptFile,eofStr,failStr,timeout,sshOpts
    my $self = {};

    $self->{host}       = $args{host};
    $self->{port}       = $args{port};
    $self->{user}       = $args{username};
    $self->{pass}       = $args{password};
    $self->{supass}     = $args{supassword};
    $self->{isVerbose}  = $args{verbose};
    $self->{cmd}        = $args{cmd};
    $self->{scriptFile} = $args{scriptFile};
    $self->{eofStr}     = $args{eofStr};
    $self->{failStr}    = $args{failStr};
    $self->{timeOut}    = $args{timeout};
    $self->{status}     = 'SUCCESS';
    $self->{sshOpts}    = $args{sshOpts};

    return bless( $self, $type );
}

sub terminateExec {
    my ( $self, $spawn ) = @_;

    if ( defined($spawn) ) {
        eval { $spawn->send("\cC\cC"); };
        eval { $spawn->hard_close(); };
    }
}

sub exec {
    my ($self) = @_;
    my $hasError = 0;

    $|           = 1;
    $ENV{LANG}   = 'en_US.UTF8';
    $ENV{LC_ALL} = 'en_US.UTF8';
    my $host       = $self->{host};
    my $port       = $self->{port};
    my $user       = $self->{user};
    my $pass       = $self->{pass};
    my $supass     = $self->{supass};
    my $isVerbose  = $self->{isVerbose};
    my $cmd        = $self->{cmd};
    my $scriptFile = $self->{scriptFile};
    my $eofStr     = $self->{eofStr};
    my $failStr    = $self->{failStr};
    my $timeOut    = $self->{timeOut};
    my $sshOpts    = $self->{sshOpts};

    if ( $cmd eq '' ) {
        my $fh = IO::File->new( $scriptFile, "r" );
        if ( defined($fh) ) {
            my $size = -s $scriptFile;
            $fh->read( $cmd, $size );
            $fh->close();
        }
    }

    if ( $cmd eq '' ) {
        $hasError = $hasError + 1;
        print("ERROR: command for ssh remote exec not defined.\n");
    }

    my $suUser = '';
    if ( $cmd =~ /su(\s+)(-\s+)?(\S+\s+)-c/ ) {
        $suUser = $3;
        $suUser =~ s/^\s*//;
        $suUser =~ s/\s*$//;
    }

    my $prompt = '[\]\$\>\#]\s*(?:\x1b[\[\d;]+m){0,}\s*$';
    my $spawn  = Expect->new();
    $spawn->log_stdout(0);
    $spawn->raw_pty(1);
    $spawn->restart_timeout_upon_receive(1);

    #dont set max_accum, it will cut the output, use pattern "/n" to increase performance
    #$spawn->max_accum(512);

    DeployUtils->sigHandler(
        'TERM', 'INT', 'HUP', 'ABRT',
        sub {
            $self->terminateExec($spawn);
        }
    );

    if ( $isVerbose == 1 ) {
        print("execute ssh -x -p$port $user\@$host $cmd\n");
    }

    my $sshCmd;
    if ( defined($sshOpts) and $sshOpts ne '' ) {
        my @sshOptsArray = split( /\s*;\s*/, $sshOpts );
        my $sshOptsStr = '';
        foreach my $sshOpt (@sshOptsArray) {
            $sshOptsStr = $sshOptsStr . "-o $sshOpt ";
        }

        $sshCmd = qq(ssh -x -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no $sshOptsStr -p$port $user\@$host);
    }
    else {
        $sshCmd = qq(ssh -x -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -p$port $user\@$host);
    }

    $spawn->spawn($sshCmd);
    $spawn->slave->stty(qw(raw -echo));

    #set terminal window size, columns enough to display command line
    #unless (eval{$self->clone_winsize_from(\*STDIN);}) {
    my $winsize = pack( 'SSSS', 100, 1024, 0, 0 );    # rows, cols, #pixelsX, pixelsY
    ioctl( $spawn->slave(), &IO::Tty::Constant::TIOCSWINSZ, $winsize );

    #}

    $| = 1;

    my $loginDesc    = "$user\@$host:$port";
    my $hasSendLogin = 0;
    my $hasSendExit  = 0;
    my $hasLogon     = 0;
    my $logonSucceed = 0;
    my $hasSuLogon   = 0;
    my $gotEofStr    = 0;
    my $gotFailStr   = 0;

    my @loginPatterns = (
        [
            timeout => sub {
                my ($spawn) = @_;
                $hasError = $hasError + 1;
                print( "ERROR: " . "ssh connect to $loginDesc timeout." . "\n" );
                $self->terminateExec($spawn);
                $self->{status} = 'ERROR';
            }
        ],
        [
            qr/(ssh: connect to host .*)$/ => sub {
                my ($spawn) = @_;
                if ( $hasLogon eq 0 ) {
                    $hasError = $hasError + 1;
                    print( "ERROR: $loginDesc " . $spawn->match() . "\n" );
                    $self->{status} = 'ERROR';
                }
            }
        ],
        [
            qr/\(yes\/no\)\?\s*$/ => sub {
                my ($spawn) = @_;
                if ( $hasLogon eq 0 ) {
                    $spawn->send("yes\n");
                    $spawn->exp_continue;
                }
            }
        ],
        [
            qr/\nPermission denied, please try again\.\s*/i => sub {
                my ($spawn) = @_;
                if ( $hasLogon eq 1 ) {
                    $hasError = $hasError + 1;
                    print( "ERROR: $loginDesc login failed. " . $spawn->match() . "\n" );
                    $self->terminateExec($spawn);
                    $self->{status} = 'ERROR';
                }
            }
        ],
        [
            qr/\s*password:\s*$/i => sub {
                my ($spawn) = @_;
                if ( $hasLogon eq 0 ) {
                    $spawn->send("$pass\n");
                    $hasLogon = 1;
                    $spawn->exp_continue;
                }
                else {
                    $hasError = $hasError + 1;
                    print("ERROR: $loginDesc invalid login, check username and password.\n");
                    $self->terminateExec($spawn);
                    $self->{status} = 'ERROR';
                }
            }
        ],
        [
            qr/$prompt/ => sub {
                $logonSucceed = 1;
            }
        ],
        [
            qr/login:\s*$/ => sub {
                my ($spawn) = @_;
                if ( $hasSendLogin eq 0 ) {
                    $spawn->send("$user\n");
                    $hasSendLogin = 1;
                }
                $spawn->exp_continue;
            }
        ],
        [
            eof => sub {
                my ($spawn) = @_;

                #$spawn->soft_close();
                $self->{status} = 'ERROR';
            }
        ]
    );

    $spawn->expect( 30, @loginPatterns );

    if ($logonSucceed) {
        if ( $isVerbose == 1 ) {
            print("INFO: ssh logon succeed.\n");
        }

        my $lastLine = '';
        $spawn->log_file(
            sub {
                if ( $isVerbose == 1 ) {
                    my $content = shift;
                    $content = $lastLine . $content;
                    my @lines = split( "\n", $content );
                    my $lineCount = scalar(@lines);

                    for ( my $i = 0 ; $i < $lineCount ; $i++ ) {
                        my $line = $lines[$i];

                        if ( $i == $lineCount - 1 ) {
                            if ( $content !~ /\n$/ ) {
                                $lastLine = $line;
                                last;
                            }
                            else {
                                $lastLine = '';
                            }
                        }

                        $line =~ s/\s*$//;
                        my $charSet = DeployUtils->guessDataEncoding($line);
                        if ( $charSet ne 'UTF-8' ) {
                            $line = Encode::encode( "utf-8", Encode::decode( $charSet, $line ) );
                        }
                        print( $line, "\n" );
                    }
                }
            }
        );

        my $envLine = '';
        if ( defined( $ENV{_INS_PATH} ) and $ENV{_INS_PATH} ne '' ) {
            my $insIdPath   = $ENV{_INS_ID_PATH};
            my $insNamePath = DeployUtils->escapeQuote( $ENV{_INS_PATH} );
            $envLine = "export TS_INSNAME=\"$insNamePath\" || setenv TS_INSNAME \"$insNamePath\"; export TS_INSID=$insIdPath || setenv TS_INSID $insIdPath \&\& ";
        }
        $spawn->send("$envLine$cmd;exit \$?\n");

        if ( $isVerbose == 1 ) {
            print("INFO: Remote cmd sended.\n");
        }

        if ( defined($suUser) and $suUser ne '' ) {
            $spawn->expect(
                10,
                [
                    qr/\s*password:\s*$/i => sub {
                        my ($spawn) = @_;
                        if ( $hasSuLogon eq 0 ) {
                            $spawn->send("$supass\n");
                            $hasSuLogon = 1;
                            $spawn->exp_continue;
                        }
                        else {
                            $hasError = $hasError + 1;
                            print("ERROR: $loginDesc invalid su login, check username and password.\n");
                            $self->terminateExec($spawn);
                            $self->{status} = 'ERROR';
                        }
                    }
                ],
                [
                    qr/su: incorrect password/ => sub {
                        my ($spawn) = @_;
                        $hasError = $hasError + 1;
                        print( "\nERROR: $loginDesc su failed, " . $spawn->match() . "\n" );
                        $self->terminateExec($spawn);
                        $self->{status} = 'ERROR';
                    }
                ],
                [
                    qr/su: user \w+ does not exist/ => sub {
                        my ($spawn) = @_;
                        $hasError = $hasError + 1;
                        print( "\nERROR: $loginDesc su failed, " . $spawn->match() . "\n" );
                        $self->terminateExec($spawn);
                        $self->{status} = 'ERROR';
                    }
                ],
                [
                    qr/.+\n/ => sub {
                    }
                ]
            );
        }

        if ( $self->{status} ne 'ERROR' ) {
            my @expectPatterns;
            push(
                @expectPatterns,
                [
                    eof => sub {
                    }
                ],
                [
                    '-ex',
                    "\n" => sub {
                        my ($spawn) = @_;
                        my $line = $spawn->before();

                        if ( defined($failStr) ) {
                            if ( $line =~ /($failStr)/ and $failStr ne '' ) {
                                $gotFailStr = 1;
                                $self->{status} = 'ERROR';
                                print("\nERROR: $loginDesc catch fail eof string '$1', exit.\n");
                                $self->terminateExec($spawn);
                            }
                        }
                        elsif ( defined($eofStr) and $eofStr ne '' ) {
                            if ( $line =~ /($eofStr)/ ) {
                                $gotEofStr = 1;
                                print("\nINFO: $loginDesc catch eof string '$1', exit.\n");
                                $self->terminateExec($spawn);
                            }
                        }
                        elsif ( index( $line, "ERROR:" ) == 0 ) {
                            $self->{status} = 'ERROR';
                        }

                        if ( $gotFailStr == 0 and $gotEofStr == 0 ) {
                            $spawn->exp_continue;
                        }
                    }
                ],
                [
                    qr/$prompt/ => sub {
                        if ( $hasSendExit == 0 ) {
                            $spawn->send("exit \$?\n");
                            $hasSendExit = 1;
                        }
                        $spawn->exp_continue;
                    }
                ]
            );

            if ( not defined($timeOut) ) {
                $timeOut = 1800;
            }

            $spawn->expect( $timeOut, @expectPatterns );
        }
    }

    if ( $spawn->exitstatus() ne 0 and $gotEofStr == 0 ) {
        $self->{status} = 'ERROR';
    }

    return $hasError;
}

1;

