#!/usr/bin/perl
use strict;

package MongoDBExec;

use POSIX qw(uname);
use Carp;
use Data::Dumper;

#mongodb的执行工具类，当执行出现ORA错误是会自动exit非0值，失败退出进程

sub new {
    my ( $type, %args ) = @_;
    my $self = {
        host        => $args{host},
        port        => $args{port},
        username    => $args{username},
        password    => $args{password},
        dbname      => $args{dbname},
        osUser      => $args{osUser},
        mongodbHome => $args{mongodbHome}
    };
    my @uname  = uname();
    my $osType = $uname[0];
    $osType =~ s/\s.*$//;
    $self->{osType} = $osType;

    my $osUser = $args{osUser};

    my $isRoot = 0;
    if ( $> == 0 ) {

        #如果EUID是0，那么运行用户就是root
        $isRoot = 1;
    }

    my $mongodbCmd;
    if ( defined( $args{mongodbHome} ) and -d $args{mongodbHome} ) {
        $mongodbCmd = "$args{mongodbHome}/mongo ";
    }
    else {
        $mongodbCmd = 'mongo ';
    }

    if ( defined( $args{host} ) or defined( $args{port} ) or defined( $args{dbname} ) ) {
        if ( defined( $args{host} ) ) {
            $mongodbCmd = "$mongodbCmd  $args{host}";
        }
        else {
            $mongodbCmd = "$mongodbCmd 127.0.0.1";
        }
        if ( defined( $args{port} ) ) {
            $mongodbCmd = "$mongodbCmd" . ":" . $args{port};
        }
        else {
            $mongodbCmd = "$mongodbCmd" . ":" . "27017";
        }

        if ( defined( $args{dbname} ) ) {
            $mongodbCmd = "$mongodbCmd" . "/" + $args{dbname};
        }
        else {
            $mongodbCmd = "$mongodbCmd" . "/admin";
        }
    }

    if ( defined( $args{username} ) ) {
        $mongodbCmd = "$mongodbCmd -u '$args{username}'";
    }

    if ( defined( $args{password} ) ) {
        $mongodbCmd = "$mongodbCmd -p '$args{password}'";
    }

    if ( $isRoot and defined( $args{osUser} ) and $osType ne 'Windows') {
        $mongodbCmd = qq{su - $osUser -c "$mongodbCmd"};
    }
    $self->{mongodbCmd} = $mongodbCmd;

    bless( $self, $type );
    return $self;
}

sub _parseOutput {
    my ( $self, $output, $isVerbose, $parseOutput ) = @_;
    my @lines = split( /\n/, $output );

    my $hasError  = 0;
    my @rowsArray = ();
    my $resultstr = '';

    foreach my $line (@lines) {
        chomp($line);

        #错误识别
        if ( $line =~ /Error: Authentication failed/ ) {
            $hasError = 1;
        }
        elsif ( $line =~ /^Error:/ or $line =~ /exception:/ ) {
            $hasError = 1;
        }

        if (    $line ne ''
            and $line !~ /^#/ig
            and $line !~ /^MongoDB shell/ig
            and $line !~ /^connecting to/ig
            and $line !~ /^Implicit session/ig
            and $line !~ /^MongoDB server/ig
            and $line !~ /^switched to db/ig )
        {
            push( @rowsArray, $line );
            $resultstr = $resultstr . $line . "\n";
        }
    }

    if ( $isVerbose == 1 or $hasError == 1 ) {
        print($output);
    }

    if ($hasError) {
        print("ERROR: Mongodb command script execution failed.\n");
    }
    if ( $parseOutput == 1 ) {
        return ( \@rowsArray, $hasError );
    }
    else {
        return ( $resultstr, $hasError );
    }
}

sub _execSql {
    my ( $self, %args ) = @_;
    my $sql         = $args{sql};
    my $isVerbose   = $args{verbose};
    my $parseOutput = $args{parseOutput};

    my $sqlFH;
    my $cmd;
    if ( $self->{osType} ne 'Windows' ) {
        $cmd = qq{$self->{mongodbCmd} << EOF
            $sql
            exit;
            EOF
        };
        $cmd =~ s/^\s*//mg;
    }
    else{
        use File::Temp;
        $sqlFH = File::Temp->new( UNLINK => 1, SUFFIX => '.sql' );
        my $fname = $sqlFH->filename;
        print $sqlFH ($sql);
        print $sqlFH ("\nexit;\n");
        $sqlFH->close();

        my $mongodbCmd = $self->{mongodbCmd};
        $mongodbCmd =~ s/'/"/g;
        $cmd = qq{$mongodbCmd "$fname"};
    }

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

    return $self->_parseOutput( $output, $isVerbose, $parseOutput );
}

#运行查询sql，返回行数组, 如果vebose=1，打印行数据
sub query {
    my ( $self, %args ) = @_;
    my $sql         = $args{sql};
    my $isVerbose   = $args{verbose};
    my $parseOutput = $args{parseOutput};

    if ( not defined($parseOutput) ) {
        $parseOutput = 1;
    }

    if ( not defined($isVerbose) ) {
        $isVerbose = 1;
    }

    my ( $result, $status ) = $self->_execSql( sql => $sql, verbose => $isVerbose, parseOutput => $parseOutput );
    return ( $status, $result );
}

1;
