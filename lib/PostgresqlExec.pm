#!/usr/bin/perl
use strict;

package PostgresqlExec;

use POSIX qw(uname);
use Carp;

#postgresql的执行工具类，当执行出现ORA错误是会自动exit非0值，失败退出进程

sub new {
    my ( $type, %args ) = @_;
    my $self = {
        host     => $args{host},
        port     => $args{port},
        username => $args{username},
        password => $args{password},
        sslmode  => $args{sslmode},
        dbname   => $args{dbname},
        osUser   => $args{osUser},
        psqlHome => $args{psqlHome}
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

    my $psqlCmd;
    if ( defined( $args{psqlHome} ) and -d $args{psqlHome} ) {
        $psqlCmd = "'$args{psqlHome}/bin/psql' ";
    }
    else {
        $psqlCmd = 'psql';
    }

    if ( defined( $args{host} ) or defined( $args{port} ) ) {
        if ( defined( $args{host} ) ) {
            $psqlCmd = "$psqlCmd  -h'$args{host}'";
        }
        if ( defined( $args{port} ) ) {
            $psqlCmd = "$psqlCmd -p $args{port}";
        }
        else {
            $psqlCmd = "$psqlCmd -p 5432";
        }
    }

    if ( defined( $args{username} ) and $args{username} ne '' ) {
        $psqlCmd = "$psqlCmd -U '$args{username}'";
    }

    if ( defined( $args{password} ) ) {
        $ENV{PGPASSWORD} = $args{password};
    }

    my $paramsLine = '';
    if ( defined( $args{dbname} ) ) {
        $paramsLine = "$paramsLine dbname=$args{dbname}";
    }

    if ( defined( $args{sslmode} ) ) {
        $paramsLine = "$paramsLine sslmode=$args{sslmode}";
    }

    if ( $paramsLine ne '' ) {
        $psqlCmd = qq{$psqlCmd '$paramsLine'};
    }

    if ( $isRoot and defined( $args{osUser} ) and $osType ne 'Windows' ) {
        $psqlCmd = qq{su - $osUser -c "$psqlCmd"};
    }
    $self->{psqlCmd} = $psqlCmd;

    bless( $self, $type );
    return $self;
}

sub _parseOutput {
    my ( $self, $output, $isVerbose ) = @_;
    my @lines      = split( /\n/, $output );
    my $linesCount = scalar(@lines);

    my $hasError   = 0;
    my @fieldNames = ();

    #字段描述信息，分析行头时一行对应一个字段描述数组
    my @fieldDescs = ();
    my @rowsArray  = ();
    my $state      = 'heading';

    for ( my $i = 0 ; $i < $linesCount - 1 ; $i++ ) {
        my $line = $lines[$i];

        #错误识别
        if ( $line =~ /^ERROR:/ ) {
            $hasError = 1;
            print( $line, "\n" );
        }

        if ( $state eq 'heading' ) {

            #sqlplus的输出根据headsize的设置，一条记录会用多个行进行输出
            if ( $line =~ /^[-\+]+$/ ) {
                my $headerLine = $lines[ $i - 1 ];
                my $linePos    = 1;

                #sqlplus的header字段下的-------，通过减号标记字段的显示字节宽度，通过此计算字段显示宽度，用于截取字段值
                #如果一行多个字段，字段之间的------中间会有空格，譬如：---- ---------
                my @lineSegs = split( /\+/, $line );
                for ( my $j = 0 ; $j < scalar(@lineSegs) ; $j++ ) {
                    my $segment = $lineSegs[$j];

                    #减号的数量就时字段的显示字节宽度
                    my $fieldLen = length($segment);

                    #linePos记录了当前行匹配的开始位置，根据字段的显示宽度从当前行抽取字段名
                    my $fieldName = substr( $headerLine, $linePos, $fieldLen - 1 );
                    $fieldName =~ s/^\s+|\s+$//g;

                    #生成字段描述，记录名称、行中的开始位置、长度信息
                    my $fieldDesc = {};
                    $fieldDesc->{name}  = $fieldName;
                    $fieldDesc->{start} = $linePos;
                    $fieldDesc->{len}   = $fieldLen;

                    push( @fieldDescs, $fieldDesc );

                    #@fieldNames数组用于保留在sqlplus中字段的显示顺序
                    push( @fieldNames, $fieldName );

                    $linePos = $linePos + $fieldLen + 1;
                }
                $state = 'row';
            }
        }
        else {
            my $row = {};

            foreach my $fieldDesc (@fieldDescs) {

                #根据字段描述的行中的开始位置和长度，substr抽取字段值
                my $val = substr( $lines[$i], $fieldDesc->{start}, $fieldDesc->{len} - 1 );
                if ( defined($val) ) {
                    $val =~ s/^\s+|\s+$//g;
                }
                else {
                    $val = '';
                }

                my $fieldName = $fieldDesc->{name};
                $row->{$fieldName} = $val;
            }

            #完成一条记录的抽取，保存到行数组，进入下一条记录的处理
            push( @rowsArray, $row );
        }
    }

    if ( $isVerbose == 1 ) {
        print($output);
    }

    if ($hasError) {
        print("ERROR: Sql execution failed.\n");
    }

    if ( scalar(@rowsArray) > 0 ) {
        return ( \@fieldNames, \@rowsArray, $hasError );
    }
    else {
        return ( undef, undef, $hasError );
    }
}

sub _execSql {
    my ( $self, %args ) = @_;
    my $sql       = $args{sql};
    my $isVerbose = $args{verbose};
    my $parseData = $args{parseData};

    if ( $sql !~ /;\s*$/ ) {
        $sql = $sql . ';';
    }

    my $sqlFH;
    my $cmd;
    if ( $self->{osType} ne 'Windows' ) {
        $cmd = qq{$self->{psqlCmd} << "EOF"
               $sql
               EOF
              };

        $cmd =~ s/^\s*//mg;
    }
    else {
        use File::Temp;
        $sqlFH = File::Temp->new( UNLINK => 1, SUFFIX => '.sql' );
        my $fname = $sqlFH->filename;
        print $sqlFH ($sql);
        print $sqlFH ("\n\\q\n");
        $sqlFH->close();

        my $psqlCmd = $self->{psqlCmd};
        $psqlCmd =~ s/'/"/g;
        $cmd = qq{$psqlCmd -f "$fname"};
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
        return ( undef, undef, $status );
    }

    if ($parseData) {
        return $self->_parseOutput( $output, $isVerbose );
    }
    elsif ($isVerbose) {
        print($output);
    }

    return ( undef, undef, $status );
}

#运行查询sql，返回行数组, 如果vebose=1，打印行数据
sub query {
    my ( $self, %args ) = @_;
    my $sql       = $args{sql};
    my $isVerbose = $args{verbose};

    if ( not defined($isVerbose) ) {
        $isVerbose = 1;
    }

    my ( $fieldNames, $rows, $status ) = $self->_execSql( sql => $sql, verbose => $isVerbose, parseData => 1 );

    return ( $status, $rows );
}

#运行非查询的sql，如果verbose=1，直接输出sqlplus执行的日志
sub do {
    my ( $self, %args ) = @_;
    my $sql       = $args{sql};
    my $isVerbose = $args{verbose};

    if ( not defined($isVerbose) ) {
        $isVerbose = 1;
    }

    my ( $fieldNames, $rows, $status ) = $self->_execSql( sql => $sql, verbose => $isVerbose, parseData => 0 );
    return $status;
}

1;
