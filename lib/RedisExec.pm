#!/usr/bin/perl
use strict;

package RedisExec;

use POSIX qw(uname);
use Carp;
use Data::Dumper;

#redis的执行工具类，当执行出现ORA错误是会自动exit非0值，失败退出进程

sub new {
    my ( $type, %args ) = @_;
    my $self = {
        host      => $args{host},
        port      => $args{port},
        auth      => $args{auth},
        dbname    => $args{dbname},
        osUser    => $args{osUser},
        redisHome => $args{redisHome}
    };

    my @uname  = uname();
    my $osType = $uname[0];
    $self->{osType} = $osType;

    my $osUser = $args{osUser};

    my $isRoot = 0;
    if ( $> == 0 ) {

        #如果EUID是0，那么运行用户就是root
        $isRoot = 1;
    }

    my $redisCmd;
    if ( defined( $args{redisHome} ) and -d $args{redisHome} ) {
        $redisCmd = "$args{redisHome}/redis-cli --raw";
    }
    else {
        $redisCmd = 'redis-cli --raw ';
    }

    if ( defined( $args{host} ) or defined( $args{port} ) ) {
        if ( defined( $args{host} ) ) {
            $redisCmd = "$redisCmd  -h $args{host}";
        }
        else {
            $redisCmd = "$redisCmd -h 127.0.0.1";
        }
        if ( defined( $args{port} ) ) {
            $redisCmd = "$redisCmd -p $args{port}";
        }
        else {
            $redisCmd = "$redisCmd -p 6379";
        }
    }

    if ( defined( $args{auth} ) ) {
        my $out = `$redisCmd -e "info"`;

        #探测到需要用密码才设置密码
        if ( $? != 0 ) {
            $redisCmd = "$redisCmd -a $args{auth}";
        }
    }

    if ( defined( $args{dbname} ) ) {
        $redisCmd = "$redisCmd -n $args{dbname}";
    }

    if ( $isRoot and defined( $args{osUser} ) ) {
        $redisCmd = qq{su - $osUser -c "$redisCmd"};
    }
    $self->{redisCmd} = $redisCmd;

    bless( $self, $type );
    return $self;
}

sub _parseOutput {
    my ( $self, $output, $isVerbose ) = @_;
    my @lines = split( /\n/, $output );

    my $hasError = 0;
    my $result   = {};

    foreach my $line (@lines) {
        chomp($line);

        #错误识别
        if ( $line =~ /^ERR/ ) {
            $hasError = 1;
            print( $line, "\n" );
        }
        elsif ( $line =~ /AUTH failed/ or $line =~ /Authentication required/ or $line =~ /not connected/ ) {
            $hasError = 1;
            print("Execute cmd failed: auth password value is error .\n");
        }

        if ( $line ne '' and $line !~ /^#/ig and $line !~ /^Warning: Using a password/ig ) {
            my @line_arr = split( ':', $line );
            if ( defined( $line_arr[1] ) ) {
                my $key   = $line_arr[0];
                my $value = $line_arr[1];
                $value =~ s/[\n\r]*//g;
                $result->{ uc($key) } = $value;
            }
        }
    }

    if ( $isVerbose == 1 ) {
        print($output);
    }

    if ($hasError) {
        print("ERROR: Sql execution failed.\n");
    }
    return ( $result, $hasError );
}

sub _execSql {
    my ( $self, %args ) = @_;
    my $sql       = $args{sql};
    my $isVerbose = $args{verbose};

    my $cmd = qq{$self->{redisCmd} << EOF
               $sql
	       exit
               EOF
              };

    $cmd =~ s/^\s*//mg;
    if ($isVerbose) {
        print("\nINFO: Execute sql:\n");
        print( $sql, "\n" );
        my $len = length($sql);
        print( '=' x $len, "\n" );
    }

    my $output = `$cmd`;
    my $status = $?;
    if ( $status ne 0 ) {
        print("ERROR: Execute cmd failed\n $output\n");
        return ( undef, $status );
    }

    if ($isVerbose) {
        print($output);
    }
    return $self->_parseOutput( $output, $isVerbose );
}

#运行查询sql，返回行数组, 如果vebose=1，打印行数据
sub query {
    my ( $self, %args ) = @_;
    my $sql       = $args{sql};
    my $isVerbose = $args{verbose};

    if ( not defined($isVerbose) ) {
        $isVerbose = 1;
    }

    my ( $result, $status ) = $self->_execSql( sql => $sql, verbose => $isVerbose );
    return ( $status, $result );
}

1;
