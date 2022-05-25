#!/usr/bin/perl
use strict;

package TarSCPExec;
use FindBin;
use File::Basename;
use Expect;

use DeployUtils;

$Expect::Multiline_Matching = 0;

sub new {
    my ( $type, %args ) = @_;
    my $self = {};

    $self->{host}      = $args{host};
    $self->{port}      = $args{port};
    $self->{user}      = $args{username};
    $self->{pass}      = $args{password};
    $self->{src}       = $args{source};
    $self->{dest}      = $args{destination};
    $self->{isVerbose} = $args{verbose};
    $self->{isPull}    = $args{isPull};

    $self->{followLinksOpt} = '';
    if ( defined( $args{followLinks} ) ) {
        $self->{followLinksOpt} = 'h';
    }

    return bless( $self, $type );
}

sub exec {
    my ($self) = @_;
    $ENV{LANG}   = 'en_US.UTF8';
    $ENV{LC_ALL} = 'en_US.UTF8';
    my $host      = $self->{host};
    my $port      = $self->{port};
    my $user      = $self->{user};
    my $pass      = $self->{pass};
    my $src       = $self->{src};
    my $dest      = $self->{dest};
    my $isVerbose = $self->{isVerbose};

    my $spawn = Expect->new();
    $spawn->log_stdout(0);
    $spawn->raw_pty(1);

    #here can use max_accum, because scp only use in password input, juse expect in the beginning
    $spawn->max_accum(2048);

    my $quietOpt = 'v';
    $quietOpt = '' if ( $isVerbose == 0 );

    #my $cmd = "scp -P$port -r$preserveOpt$quietOpt $src $dest";
    my $destDir = $dest;
    my $srcDir  = dirname($src);
    $src = basename($src);

    my $followLinksOpt = $self->{followLinksOpt};

    my $errMsg;
    my $cmd;
    if ( $self->{isPull} eq 0 ) {
        if ( not -e "$srcDir/$src" ) {
            $errMsg = "ERROR: Source path:$src not exists or permission deny.";
        }
        $cmd = qq{tar c${followLinksOpt}f - -C '$srcDir' '$src' | ssh -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -P$port $user\@$host "cd '$destDir' && tar x${quietOpt}${followLinksOpt}f -"};

        #print("debug:push:$cmd\n");
    }
    else {
        if ( not -e $destDir ) {
            $errMsg = "ERROR: Destination path:$destDir not exists.";
        }

        #$cmd = "ssh $user\@$host 'tar -C $srcDir -czf - $src' | tar $quietOpt -C $destDir -xzf -";
        #aix机器上的tar命令参数的顺序存在问题，改成下面这种情况是可以跑的，liunx和 aix都测试过
        #ssh root@172.16.92.43 'tar -cvf - -C /tmp/ trunk' | tar  -C /tmp -xvf  -
        $cmd = qq{ssh -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no $user\@$host "tar c${followLinksOpt}f - -C '$srcDir' $src" | tar x${quietOpt}f - -C '$destDir'};

        #print("debug:pull:$cmd\n");
    }

    if ( not defined($errMsg) or $errMsg eq '' ) {
        $spawn->spawn($cmd);

        my $hasSendPass = 0;
        my $ret         = $spawn->expect(
            undef,
            [
                qr/password:\s*$/i => sub {
                    if ( $hasSendPass == 0 ) {
                        $spawn->send("$pass\n");
                        $hasSendPass = 1;
                        $spawn->log_stdout(1);
                        exp_continue;
                    }
                    else {
                        $spawn->send("\cC\cC");
                        $spawn->hard_close();
                        print("\nERROR: $user\@$host login failed check username and password.\n");
                    }
                }
            ],
            [
                eof => sub {
                    my $lastLine = $spawn->before();
                    $spawn->soft_close();
                    if ( $spawn->exitstatus() != 0 and $lastLine =~ /lost connection/ ) {
                        print("ERROR: connect to server failed, $lastLine");
                    }
                }
            ]
        );

    }

    my $rc = $spawn->exitstatus();

    return $rc;
}

1;
