#!/usr/bin/perl
use strict;

package MysqlExec;

use POSIX qw(uname);
use Carp;
use Data::Dumper;

#sqlplus的执行工具类，当执行出现ORA错误是会自动exit非0值，失败退出进程

sub new {
    my ( $type, %args ) = @_;
    my $self = {
        host       => $args{host},
        port       => $args{port},
        socketPath => $args{socketPath},
        username   => $args{username},
        password   => $args{password},
        dbname     => $args{dbname},
        osUser     => $args{osUser},
        mysqlHome  => $args{mysqlHome}
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

    my $mysqlCmd;
    if ( defined( $args{mysqlHome} ) and -d $args{mysqlHome} ) {
        $mysqlCmd = "'$args{mysqlHome}/bin/mysql' -t";
    }
    else {
        $mysqlCmd = 'mysql -t';
    }

    if ( defined( $args{socketPath} ) and -e $args{socketPath} ) {
        $mysqlCmd = "$mysqlCmd --socket '$args{socketPath}'";
    }
    elsif ( defined( $args{host} ) or defined( $args{port} ) ) {
        if ( defined( $args{host} ) ) {
            $mysqlCmd = "$mysqlCmd  -h'$args{host}'";
        }
        else {
            $mysqlCmd = "$mysqlCmd -h127.0.0.1";
        }
        if ( defined( $args{port} ) ) {
            $mysqlCmd = "$mysqlCmd -P$args{port}";
        }
        else {
            $mysqlCmd = "$mysqlCmd -P3306";
        }
    }

    if ( defined( $args{username} ) ) {
        $mysqlCmd = "$mysqlCmd -u'$args{username}'";
    }
    else {
        $mysqlCmd = "$mysqlCmd -uroot";
    }

    if ( defined( $args{password} ) ) {
        my $out = `$mysqlCmd -e 'set names utf8;' 2>&1`;

        #探测到需要用密码才设置密码
        if ( $? != 0 ) {
            $mysqlCmd = "$mysqlCmd -p'$args{password}'";
        }
    }

    if ( defined( $args{dbname} ) ) {
        $mysqlCmd = "$mysqlCmd -D'$args{dbname}'";
    }

    if ( $isRoot and defined( $args{osUser} ) ) {
        $mysqlCmd = qq{su - $osUser -c "$mysqlCmd"};
    }
    $self->{mysqlCmd} = $mysqlCmd;

    bless( $self, $type );
    return $self;
}

sub _parseOutput {
    my ( $self, $output, $isVerbose ) = @_;
    my @lines = split( /\n/, $output );
    my $linesCount = scalar(@lines);

    my $hasError   = 0;
    my @fieldNames = ();

    #字段描述信息，分析行头时一行对应一个字段描述数组
    my @fieldDescs = ();
    my @rowsArray  = ();
    my $state      = 'heading';
    my $headingBegin = 0;
    for ( my $i = 0 ; $i < $linesCount ; $i++ ) {
        my $line = $lines[$i];

        #错误识别
        #ERROR at line 1:
        #ORA-00907: missing right parenthesis
        if ( $line =~ /^ERROR\s*[^:]*?:.*?$/ or $line =~ /^ERROR.*?:.*?$/ ) {
            $hasError = 1;
            print( $line,            "\n" );
            print( $lines[ $i + 1 ], "\n" );
        }

        if ( $headingBegin==0 and $line !~ /^[-\+]+$/ ) {
            next;
        }
        else{
            $headingBegin = 1;
        }

        if ( $state eq 'heading' ) {

            #sqlplus的输出根据headsize的设置，一条记录会用多个行进行输出
            my $underLine = $lines[ $i + 1 ];
            if ( $underLine =~ /^[-\+]+$/ ) {
                my $linePos = 1;

                #sqlplus的header字段下的-------，通过减号标记字段的显示字节宽度，通过此计算字段显示宽度，用于截取字段值
                #如果一行多个字段，字段之间的------中间会有空格，譬如：---- ---------
                my @underLineSegs = split( /\+/, $underLine );
                for ( my $j = 1 ; $j < scalar(@underLineSegs) ; $j++ ) {
                    my $segment = $underLineSegs[$j];

                    #减号的数量就时字段的显示字节宽度
                    my $fieldLen = length($segment);

                    #linePos记录了当前行匹配的开始位置，根据字段的显示宽度从当前行抽取字段名
                    my $fieldName = substr( $line, $linePos, $fieldLen );
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
                $i++;
                $state = 'row';
            }
        }
        elsif ( $line =~ /^\|/ ) {
            my $row = {};

            foreach my $fieldDesc (@fieldDescs) {

                #根据字段描述的行中的开始位置和长度，substr抽取字段值
                my $val = substr( $line, $fieldDesc->{start}, $fieldDesc->{len} );
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

    my $cmd = qq{$self->{mysqlCmd} << "EOF"
               $sql
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
