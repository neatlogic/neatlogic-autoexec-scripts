#!/usr/bin/perl

package SSHExpect;
use strict;
use Expect;

sub new {
    my ( $type, %attr ) = @_;

    $| = 1;

    my $self   = {};
    my $PROMPT = '[\]\$\>\#]\s*$';
    if ( defined( $attr{PROMPT} ) ) {
        $PROMPT = $attr{PROMPT};
    }
    $self->{exitCmd} = 'exit';
    if ( defined( $attr{exitCmd} ) ) {
        $self->{exitCmd} = $attr{exitCmd};
    }

    $self->{PROMPT} = $PROMPT;

    $self->{host}     = $attr{host};
    $self->{port}     = $attr{port};
    $self->{username} = $attr{username};
    $self->{password} = $attr{password};
    $self->{timeout}  = $attr{timeout};

    bless( $self, $type );

    return $self;
}

sub login {
    my ($self) = @_;

    my $PROMPT   = $self->{PROMPT};
    my $host     = $self->{host};
    my $port     = $self->{port};
    my $username = $self->{username};
    my $password = $self->{password};

    my $spawn = Expect->new();
    $spawn->log_stdout(0);    #if debug the ssh interact, change to log_stdout(1)
    $spawn->raw_pty(1);
    $spawn->restart_timeout_upon_receive(1);
    $spawn->max_accum(512);

    my $sshCmd = qq(ssh -x -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -p$port $username\@$host);

    my $cmdOut = '';

    $spawn->spawn($sshCmd);
    $spawn->slave->stty(qw(raw -echo));

    $spawn->expect(
        3,
        [
            qr/password:/i => sub {
                $spawn->send("$password\n");
            }
        ]
    );

    $spawn->expect(
        5,
        [
            qr/$PROMPT/ => sub {
                print("INFO: login $username\@$host:$port success.\n");
            }
        ],
        [
            qr/password:/i => sub {
                print( $spawn->before() );
                print("ERROR: login $username\@$host:$port failed.\n");
                $spawn->hard_close();
                exit(2);
            }
        ],
        [
            timeout => sub {
                print("ERROR: login $username\@$host:$port failed.\n");
                $spawn->hard_close();
                exit(3);
            }
        ]
    );

    END {
        local $?;
        if ( defined($spawn) ) {
            $spawn->send( $self->{exitCmd} . "\n" );
            $spawn->soft_close();
        }
    }

    $self->{spawn} = $spawn;
}

sub configTerminal {
    my ( $self, $command ) = @_;
    my $spawn  = $self->{spawn};
    my $PROMPT = $self->{PROMPT};

    if ( not defined($spawn) ) {
        $self->login();
    }

    $spawn->send("$command\n");
    $spawn->expect( 3, '-re', $PROMPT );
}

sub runCmd {
    my ( $self, $cmd, $leadingLineCount ) = @_;

    my $timeout = $self->{timeout};
    my $spawn   = $self->{spawn};
    my $PROMPT  = $self->{PROMPT};

    if ( not defined($spawn) ) {
        print("ERROR: not login yet.\n");
        exit(2);
    }

    if ( not defined($leadingLineCount) ) {
        $leadingLineCount = 1;
    }

    my $cmdOut = '';

    $spawn->log_file(
        sub {
            my $content = shift;
            $cmdOut = $cmdOut . $content;
        }
    );

    $spawn->send("$cmd\n");
    $spawn->expect( $timeout, '-re', $PROMPT );
    $spawn->log_file(undef);

    #去掉最后一行的命令提示行
    $cmdOut = substr( $cmdOut, 0, rindex( $cmdOut, "\n" ) + 1 );

    #去掉命令输出的头几行
    for ( my $i = 0 ; $i < $leadingLineCount ; $i++ ) {
        $cmdOut = substr( $cmdOut, index( $cmdOut, "\n" ) + 1 );
    }

    return $cmdOut;
}

sub runCmds {
    my ( $self, $cmds, $leadingLineCount ) = @_;

    my $cmdsOut = '';
    foreach my $cmd (@$cmds) {
        $cmdsOut = $cmdsOut . $self->runCmd($cmd);
    }

    return $cmdsOut;
}

1;
