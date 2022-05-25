#!/usr/bin/perl
use strict;

package SCPExec;
use FindBin;
use Expect;
$Expect::Multiline_Matching = 0;

sub new {
    my ( $type, %args ) = @_;

    #args keys:host,port,username,password,source,destination,verbose,notpreserve
    my $self = {};

    $self->{host}        = $args{host};
    $self->{port}        = $args{port};
    $self->{user}        = $args{username};
    $self->{pass}        = $args{password};
    $self->{src}         = $args{source};
    $self->{dest}        = $args{destination};
    $self->{isVerbose}   = $args{verbose};
    $self->{notpreserve} = $args{notpreserve};

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
    my $np        = $self->{notpreserve};

    my $spawn = Expect->new();
    $spawn->log_stdout(0);
    $spawn->raw_pty(1);

    #here can use max_accum, because scp only use in password input, juse expect in the beginning
    $spawn->max_accum(2048);

    my $quietOpt = '';
    $quietOpt = 'q' if ( $isVerbose == 0 );
    my $preserveOpt = 'p';
    $preserveOpt = '' if ($np);

    my $cmd = "scp -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -P$port -r$preserveOpt$quietOpt $src $dest";
    if ($isVerbose) {
        print("INFO:$cmd\n");
    }

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

    my $rc = $spawn->exitstatus();

    return $rc;
}

1;

