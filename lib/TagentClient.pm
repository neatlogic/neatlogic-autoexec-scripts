#!/usr/bin/perl
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib";
use lib "$FindBin::Bin/../lib/perl-lib/lib/perl5";

use strict;

package TagentClient;

use Socket;
use Encode;
use POSIX;
use IO::Socket::INET;
use IO::Select;
use File::Basename;
use CharsetDetector;
use HTTP::Tiny;
use Cwd;
use Config;

#no warnings;
use Crypt::RC4;

my $PROTOCOL_VER        = 'Tagent1.1';
my $SECURE_PROTOCOL_VER = 'Tagent1.1s';

sub _rc4_encrypt_hex ($$) {
    my ( $key, $data ) = ( $_[0], $_[1] );
    return join( '', unpack( 'H*', RC4( $key, $data ) ) );
}

sub _rc4_decrypt_hex ($$) {
    my ( $key, $data ) = ( $_[0], $_[1] );
    return RC4( $key, pack( 'H*', $data ) );
}

sub auth {
    my ( $self, $socket, $authKey, $isVerbose ) = @_;

    my ( $challenge, $agentOsType, $agentCharset, $protocolVer );

    #读取agent服务端发来的"ostype|charset|challenge", agent os类型|agent 字符集|加密的验证挑战token, '|'相隔
    $challenge = $self->_readChunk( $socket, 0 );

    ( $agentOsType, $agentCharset, $challenge, $protocolVer ) = split( '\|', $challenge );

    if ( not defined($protocolVer) ) {
        $protocolVer = 'null';
    }

    #if ( $self->{protocolVer} ne $protocolVer ) {
    #    $socket->shutdown(2);
    #    die( "ERROR: server protocol version is $protocolVer, not match client protocol version " . $self->{protocolVer} );
    #}
    if ( $protocolVer eq $SECURE_PROTOCOL_VER ) {
        $self->{encrypt} = 1;
    }
    elsif ( $self->{protocolVer} ne $protocolVer ) {
        $socket->shutdown(2);
        die( "ERROR: Server protocol version is $protocolVer, not match client protocol version " . $self->{protocolVer} );
    }
    $self->{protocolVer} = $protocolVer;

    $self->{agentOsType} = $agentOsType;
    if ( not defined( $self->{agentCharset} ) ) {
        $self->{agentCharset} = $agentCharset;
    }

    #挑战解密后，是逗号相隔的两个整数，把乘积加密发回Agent服务端
    my $plainChlg = _rc4_decrypt_hex( $authKey, $challenge );
    my ( $factor1, $factor2, $serverTime ) = split( ',', $plainChlg );
    if ( not defined($serverTime) or $serverTime eq '0' ) {
        $serverTime = time();
    }

    if ( not defined($factor1) or not defined($factor2) or $factor1 !~ /^\d+$/ or $factor2 !~ /^\d+$/ ) {
        return 0;
    }

    my $reverseChlg = int($factor1) * int($factor2) . ',' . $serverTime;

    my $encryptChlg = _rc4_encrypt_hex( $authKey, $reverseChlg );

    $self->_writeChunk( $socket, $encryptChlg );

    my $authResult;
    $authResult = $self->_readChunk($socket);

    #如果返回内容中出现auth failed，则验证失败
    if ( $authResult ne 'auth succeed' ) {
        if ( $isVerbose == 1 ) {
            my $agentCharset = $self->{agentCharset};
            my $charset      = $self->{charset};
            if ( $charset ne $agentCharset ) {
                print( "ERROR:" . Encode::encode( $charset, Encode::decode( $agentCharset, $authResult ) ) . "\n" );
            }

        }
        return 0;
    }

    return 1;
}

sub new {
    my ( $type, $host, $port, $password, $readTimeout, $writeTimeout, $agentCharset ) = @_;

    $| = 1;

    $SIG{PIPE} = 'IGNORE';

    my $self = {};
    $self = bless( $self, $type );

    $host = '127.0.0.1' if ( not defined($host) or $host eq '' );
    $port = 3939        if ( not defined($port) or $port eq '' );

    $self->{protocolVer} = $PROTOCOL_VER;
    $self->{encrypt}     = 0;
    $self->{host}        = $host;
    $self->{port}        = $port;
    $self->{password}    = $password;
    if ( not defined($readTimeout) ) {
        $readTimeout = 0;
    }
    $self->{readTimeout} = int($readTimeout);

    if ( not defined($writeTimeout) ) {
        $writeTimeout = 0;
    }
    $self->{writeTimeout} = $writeTimeout;
    $self->{encrypt}      = 0;

    if ( defined($agentCharset) ) {
        $self->{agentCharset} = $agentCharset;
    }

    my $charset = 'UTF-8';

    my @uname  = uname();
    my $ostype = $uname[0];

    #获取os类型名称，只区分windows和unix
    $self->{ostype} = 'unix';
    if ( $ostype =~ 'Windows' ) {
        eval {

            #把运行当前进程的perl所在目录加入Windows Path
            my $perlDir = Cwd::abs_path( dirname( $Config{perlpath} ) );
            if ( index( $ENV{PATH}, "$perlDir;" ) < 0 ) {
                $ENV{PATH} = "$perlDir;" . $ENV{PATH};
            }
        };

        eval(
            q{
                use Win32::API;
                use Win32API::File qw( GetOsFHandle FdGetOsFHandle SetHandleInformation INVALID_HANDLE_VALUE HANDLE_FLAG_INHERIT );

                if ( Win32::API->Import( 'kernel32', 'int GetACP()' ) ) {
                $charset = 'cp' . GetACP();
                }

                $self->{_dont_inherit} = sub {
                    foreach my $handle (@_) {
                        next unless defined($handle);
                        my $fd = $handle;
                        $fd = fileno($fd) if ref($fd);
                             
                        my $osfh = FdGetOsFHandle($fd);
                        if(!defined($osfh) || $osfh == INVALID_HANDLE_VALUE){
                            die($^E);
                        }
                        SetHandleInformation( $osfh, HANDLE_FLAG_INHERIT, 0 );
                    }
                };
            }
        );
        $self->{ostype} = 'windows';

        my $homePath = Cwd::abs_path("$FindBin::Bin\\..");

        #把agent目录中的7-Zip加入windows的Path环境变量
        my $aPath = "$homePath/mod/7-Zip;" . $ENV{ProgramFiles} . "/7-Zip;";
        if ( index( $ENV{PATH}, $aPath ) < 0 ) {
            $ENV{PATH} = $aPath . $ENV{PATH};
        }
    }
    else {
        eval {

            #把运行当前进程的perl所在目录加入PATH
            my $perlDir = Cwd::abs_path( dirname( $Config{perlpath} ) );
            if ( index( $ENV{PATH}, "$perlDir;" ) < 0 ) {
                $ENV{PATH} = "$perlDir:" . $ENV{PATH};
            }
        };

        my ( $lang, $charset );
        my $envLang = $ENV{LANG};

        if ( defined($envLang) and index( $envLang, '.' ) >= 0 ) {
            ( $lang, $charset ) = split( /\./, $envLang );
        }
        else {
            $charset = $envLang;
        }

        $charset = 'iso-8859-1' if ( not defined($charset) );
    }

    $self->{charset} = $charset;

    return $self;
}

#创建Agent连接，并完成验证, 返回TCP连接
sub getConnection {
    my ( $self, $isVerbose ) = @_;

    my $host     = $self->{host};
    my $port     = $self->{port};
    my $password = $self->{password};

    my $socket = IO::Socket::INET->new(
        PeerHost => $host,
        PeerPort => $port
    );

    my $_dont_inherit = $self->{_dont_inherit};
    if ( defined($_dont_inherit) ) {
        &$_dont_inherit($socket);
    }

    if ( defined($socket) ) {
        eval {
            my $ret = $self->auth( $socket, $password, $isVerbose );

            if ( $ret != 1 ) {
                die("Authenticate failed while connect to $host:$port.\n");
                return;
            }
            $self->{socket} = $socket;
        };
        if ($@) {
            my $errMsg = $@;
            $errMsg =~ s/\sat\s.*$//;
            die("ERROR: $errMsg");
        }

    }
    else {
        die("ERROR: Connect to server $host:$port failed.\n");
    }

    return $socket;
}

#读取一个chunk，chunk开头是两个字节的unsigned short(big endian)，用于说明chunk的长度
#先读取chunk的长度，然后依据长度读取payload
#如果chunk的长度是0，则读取到连接关闭为止, chunk长度为0只会出现在最后一个chunk
#使用异常进行异常处理，譬如：连接被reet， 连接已经关闭，返回错误等
sub _readChunk {
    my ( $self, $socket, $encrypt ) = @_;

    if ( not defined($encrypt) ) {
        $encrypt = $self->{encrypt};
    }

    my $chunk;

    my $len       = 0;
    my $readLen   = 0;
    my $chunkHead = '';

    my $readTimeout = $self->{readTimeout};
    my $sel         = new IO::Select($socket);
    my @ready;

    $readLen = 0;
    do {
        @ready = ();

        if ( $readTimeout > 0 ) {
            undef($!);
            @ready = $sel->can_read($readTimeout);
            if ( $!{EINTR} ) {
                next;
            }
        }
        else {
            push( @ready, $socket );
        }

        if ( scalar(@ready) > 0 ) {
            while (1) {
                undef($!);

                my $buf;
                $len = $socket->sysread( $buf, 2 - $readLen );

                if ( not defined($len) and ( $!{EINTR} or $!{EAGAIN} ) ) {
                    next;
                }

                if ( not defined($len) ) {
                    die("Connection reset");
                }
                elsif ( $len == 0 ) {
                    die("Connection closed");
                }
                else {
                    $chunkHead = $chunkHead . $buf;
                    $readLen   = $readLen + $len;
                }

                last;
            }
        }
        else {
            die("Connection read timeout");
        }
    } while ( $readLen < 2 );

    my $chunkLen = unpack( 'n', $chunkHead );

    if ( $chunkLen > 0 ) {
        $chunk   = '';
        $readLen = 0;
        do {
            @ready = ();

            if ( $readTimeout > 0 ) {
                undef($!);
                @ready = $sel->can_read($readTimeout);
                if ( $!{EINTR} ) {
                    next;
                }
            }
            else {
                push( @ready, $socket );
            }

            if ( scalar(@ready) > 0 ) {
                while (1) {
                    undef($!);

                    my $buf;
                    $len = $socket->sysread( $buf, $chunkLen - $readLen );

                    if ( not defined($len) and ( $!{EINTR} or $!{EAGAIN} ) ) {
                        next;
                    }

                    if ( not defined($len) ) {
                        die("Connection reset");
                    }
                    elsif ( $len == 0 and $readLen < $chunkLen ) {
                        die("Connection closed");
                    }
                    elsif ( $len > 0 ) {
                        $chunk   = $chunk . $buf;
                        $readLen = $readLen + $len;
                    }

                    last;
                }
            }
            else {
                die("Connection read timeout");
            }
        } while ( $readLen < $chunkLen );
    }
    else {
        $readLen = 0;
        $chunk   = '';
        do {
            @ready = ();

            if ( $readTimeout > 0 ) {
                undef($!);
                @ready = $sel->can_read($readTimeout);
                if ( $!{EINTR} ) {
                    next;
                }
            }
            else {
                push( @ready, $socket );
            }

            if ( scalar(@ready) > 0 ) {
                undef($!);

                my $buf;
                $readLen = $socket->sysread( $buf, 4096 );

                if ( not defined($readLen) and ( $!{EINTR} or $!{EAGAIN} ) ) {
                    next;
                }

                if ( not defined($readLen) ) {
                    die("Connection reset");
                }
                elsif ( $readLen > 0 ) {
                    $chunk = $chunk . $buf;
                }
            }
            else {
                die("Connection read timeout");
            }
        } while ( $readLen > 0 );

        if ( defined($chunk) and $chunk ne '' ) {
            if ( $encrypt == 1 ) {
                $chunk = RC4( $self->{password}, $chunk );
            }
            my $agentCharset = $self->{agentCharset};
            my $charset      = $self->{charset};

            if ( $charset ne $agentCharset ) {
                $chunk = Encode::encode( $charset, Encode::decode( $agentCharset, $chunk ) );
            }
            die($chunk);
        }
        else {
            undef($chunk);
        }
    }

    if ( $encrypt == 1 ) {
        if ( defined($chunk) and $chunk ne '' ) {
            $chunk = RC4( $self->{password}, $chunk );
        }
    }

    return $chunk;
}

#往连接写入chunk，先写入长度（big endian的unsigned short），然后写入数据
#如果设定了trunk长度，则直接使用$trunkLen作为chunk的长度，主要用于长度为0的处理
sub _writeChunk {
    my ( $self, $socket, $chunk, $chunkLen, $encrypt ) = @_;

    if ( not defined($encrypt) ) {
        $encrypt = $self->{encrypt};
    }

    if ( defined($chunk) and $chunk ne '' ) {
        if ( $encrypt == 1 ) {
            $chunk = RC4( $self->{password}, $chunk );
        }

        if ( not defined($chunkLen) ) {
            $chunkLen = length($chunk);
        }
    }
    else {
        $chunkLen = 0;
    }

    my $isClose = 0;
    if ( $chunkLen == 0 ) {
        $isClose = 1;
    }

    my $writeTimeout = $self->{writeTimeout};
    my $sel          = new IO::Select($socket);
    my @ready;

    my $writeLen      = 0;
    my $totalWriteLen = 0;

    do {
        @ready = ();

        if ( $writeTimeout > 0 ) {
            undef($!);
            @ready = $sel->can_write($writeTimeout);
            if ( $!{EINTR} ) {
                next;
            }
        }
        else {
            push( @ready, $socket );
        }

        if ( scalar(@ready) > 0 ) {
            undef($!);
            $writeLen = $socket->syswrite( pack( 'n', $chunkLen ), 2 - $totalWriteLen, $totalWriteLen );
            if ( not defined($writeLen) and ( $!{EINTR} or $!{EAGAIN} ) ) {
                next;
            }

            if ( defined($writeLen) ) {
                $totalWriteLen = $totalWriteLen + $writeLen;
            }
            else {
                die("Connection closed:$!");
            }

        }
        else {
            die("Connection write timeout");
        }
    } while ( $totalWriteLen < 2 );

    if ( defined($chunk) ) {
        if ( $chunkLen == 0 ) {
            $chunkLen = length($chunk);
        }

        $writeLen      = 0;
        $totalWriteLen = 0;
        do {
            @ready = ();

            if ( $writeTimeout > 0 ) {
                undef($!);
                @ready = $sel->can_write($writeTimeout);
                if ( $!{EINTR} ) {
                    next;
                }
            }
            else {
                push( @ready, $socket );
            }

            if ( scalar(@ready) > 0 ) {
                undef($!);
                $writeLen = $socket->syswrite( $chunk, $chunkLen - $totalWriteLen, $totalWriteLen );
                if ( not defined($writeLen) and ( $!{EINTR} or $!{EAGAIN} ) ) {
                    next;
                }

                if ( defined($writeLen) ) {
                    $totalWriteLen = $totalWriteLen + $writeLen;
                }
                else {
                    die("Connection closed");
                }
            }
            else {
                die("Connection write timeout");
            }
        } while ( $totalWriteLen < $chunkLen );
    }

    if ( $isClose == 1 ) {
        $socket->shutdown(1);
    }
}

#执行远程命令
sub execCmd {
    my ( $self, $user, $cmd, $isVerbose, $eofStr, $callback, @cbparams ) = @_;
    $cmd =~ s/^\s+//;
    $cmd =~ s/\s*$//;

    if ( not defined($user) ) {
        $user = 'none';
    }

    if ( not defined($isVerbose) ) {
        $isVerbose = 0;
    }
    if ( not defined($eofStr) ) {
        $eofStr = '';
    }

    $eofStr =~ s/^\s+//;
    $eofStr =~ s/\s*$//;

    my $socket = $self->getConnection($isVerbose);

    my $agentCharset  = $self->{agentCharset};
    my $charset       = $self->{charset};
    my $cmdEncoded    = $cmd;
    my $eofStrEncoded = $eofStr;
    my $userEncoded   = $user;

    if ( $charset ne $agentCharset ) {
        $cmdEncoded    = Encode::encode( $agentCharset, Encode::decode( $charset, $cmd ) );
        $eofStrEncoded = Encode::encode( $agentCharset, Encode::decode( $charset, $eofStr ) );
        $userEncoded   = Encode::encode( $agentCharset, Encode::decode( $charset, $user ) );
    }

    #相比老版本，因为用了chunk协议，所以请求里的dataLen就不需要了
    $self->_writeChunk( $socket, "$userEncoded|execmd|$agentCharset|" . unpack( 'H*', $cmdEncoded ) . '|' . unpack( 'H*', $eofStrEncoded ) );

    my $status = 0;

    my $line;
    eval {
        my $outputCharset;

        do {
            $line = $self->_readChunk($socket);

            if ( defined($line) ) {

                #如果agent端的编码和当前程序编码不一致，则进行转码
                $outputCharset = CharsetDetector::detect($line);
                if ( $outputCharset ne $charset ) {
                    $line = Encode::encode( $charset, Encode::decode( $outputCharset, $line ) );
                }

                if ( $isVerbose == 1 ) {
                    print($line );
                }
                if ( defined($callback) ) {
                    &$callback( $line, @cbparams );
                }
            }
        } while ( defined($line) );
    };
    if ($@) {
        $status = -1;
        my $errMsg = $@;
        $errMsg =~ s/\sat\s.*$//;
        my @errContent = split( '\n', $errMsg );
        for my $line (@errContent) {
            if ( $line =~ /^\d+$/ ) {
                $status = int($line);
            }
            if ( $line ne '1' and $line ne '0' ) {
                print("$line\n");
            }
        }
    }

    close($socket);

    return $status;
}

#获取远程命令的所有输出
sub getCmdOut {
    my ( $self, $user, $cmd, $isVerbose, $eofStr ) = @_;

    my @content;
    my $callback = sub {
        my ( $line, $content ) = @_;
        push( @$content, $line );
    };

    my $status = $self->execCmd( $user, $cmd, $isVerbose, $eofStr, $callback, ( \@content ) );

    if ( $status != 0 ) {
        die( join( "\n", @content ) );
    }

    return \@content;
}

#异步执行远程命令，不需要等待远程命令执行完
sub execCmdAsync {
    my ( $self, $user, $cmd, $isVerbose, $eofStr ) = @_;
    $cmd =~ s/^\s+//;
    $cmd =~ s/\s*$//;

    if ( not defined($user) ) {
        $user = 'none';
    }

    if ( not defined($isVerbose) ) {
        $isVerbose = 0;
    }
    if ( not defined($eofStr) ) {
        $eofStr = '';
    }

    $eofStr =~ s/^\s+//;
    $eofStr =~ s/\s*$//;

    my $socket = $self->getConnection($isVerbose);

    my $agentCharset  = $self->{agentCharset};
    my $charset       = $self->{charset};
    my $cmdEncoded    = $cmd;
    my $eofStrEncoded = $eofStr;
    my $userEncoded   = $user;

    if ( $charset ne $agentCharset ) {
        $cmdEncoded    = Encode::encode( $agentCharset, Encode::decode( $charset, $cmd ) );
        $eofStrEncoded = Encode::encode( $agentCharset, Encode::decode( $charset, $eofStr ) );
        $userEncoded   = Encode::encode( $agentCharset, Encode::decode( $charset, $user ) );
    }

    $self->_writeChunk( $socket, "$userEncoded|execmdasync|$agentCharset|" . unpack( 'H*', $cmdEncoded ) . '|' . unpack( 'H*', $eofStrEncoded ) );

    my $status = 0;

    eval { $self->_readChunk($socket); };
    if ($@) {
        $status = -1;
        if ( $isVerbose == 1 ) {
            my $errMsg = $@;
            $errMsg =~ s/\sat\s.*$//;
            print("ERROR: $errMsg\n");
        }
    }
    else {
        $status = 0;
        if ( $isVerbose == 1 ) {
            print("INFO: Launch command asynchronized succeed.\n");
        }
    }

    close($socket);

    return $status;
}

#更改密码
sub updateCred {
    my ( $self, $cred, $isVerbose ) = @_;
    if ( not defined($isVerbose) ) {
        $isVerbose = 0;
    }

    $cred =~ s/^\s+//;
    $cred =~ s/\s*$//;

    my $socket = $self->getConnection($isVerbose);

    my $agentCharset = $self->{agentCharset};
    my $charset      = $self->{charset};
    if ( $charset ne $agentCharset ) {
        $cred = Encode::encode( $agentCharset, Encode::decode( $charset, $cred ) );
    }

    $self->_writeChunk( $socket, "none|updatecred|$agentCharset|" . unpack( 'H*', $cred ) );

    my $status = 0;
    eval { $self->_readChunk($socket); };
    if ($@) {
        $status = -1;
        if ( $isVerbose == 1 ) {
            my $errMsg = $@;
            $errMsg =~ s/\sat\s.*$//;
            print("ERROR: $errMsg\n");
        }
    }
    else {
        $status = 0;
        if ( $isVerbose == 1 ) {
            print("INFO: Change credential succeed.\n");
        }

    }

    close($socket);

    return $status;
}

#重启
sub reload {
    my ( $self, $isVerbose ) = @_;
    if ( not defined($isVerbose) ) {
        $isVerbose = 0;
    }

    my $socket = $self->getConnection($isVerbose);

    my $agentCharset = $self->{agentCharset};

    $self->_writeChunk( $socket, "none|reload|$agentCharset|" . unpack( 'H*', "none" ) );

    my $status = 0;

    eval { $self->_readChunk($socket); };
    if ($@) {
        $status = -1;
        if ( $isVerbose == 1 ) {
            my $errMsg = $@;
            $errMsg =~ s/\sat\s.*$//;
            print("ERROR: $errMsg\n");
        }
    }
    else {
        $status = 0;
        if ( $isVerbose == 1 ) {
            print("INFO: reload succeed.\n");
        }
    }

    close($socket);

    return $status;
}

sub echo {
    my ( $self, $msg, $isVerbose ) = @_;
    if ( not defined($isVerbose) ) {
        $isVerbose = 0;
    }

    my $socket = $self->getConnection($isVerbose);

    my $agentCharset = $self->{agentCharset};
    $self->_writeChunk( $socket, "none|echo|$agentCharset|" . unpack( 'H*', $msg ) );

    my $feedBack;
    eval { $feedBack = $self->_readChunk($socket); };
    if ($@) {
        my $errMsg = $@;
        $errMsg =~ s/\sat\s.*$//;
        $feedBack = $errMsg;

        if ( $isVerbose == 1 ) {
            print("ERROR: $errMsg\n");
        }
    }
    else {
        if ( $isVerbose == 1 ) {
            print("INFO: echo back:\"$feedBack\".\n");
        }

    }

    close($socket);

    return $feedBack;
}

#把从连接中接收的文件下载数据写入文件，用于文件的下载
sub _writeSockToFile {
    my ( $self, $socket, $destFile, $isVerbose ) = @_;
    if ( not defined($isVerbose) ) {
        $isVerbose = 0;
    }

    my $status = 0;

    my $fh;
    if ( open( $fh, ">$destFile" ) ) {
        my $wrtLen = 0;
        my $chunk;
        eval {
            do {
                $chunk = $self->_readChunk($socket);
                if ( defined($chunk) ) {
                    $wrtLen = syswrite( $fh, $chunk );
                    if ( not defined($wrtLen) ) {
                        $status = -1;
                        print("ERROR: $!\n");
                    }
                }
            } while ( defined($chunk) );
            close($fh);
        };
        if ($@) {
            $status = -1;
            if ( $isVerbose == 1 ) {
                my $errMsg = $@;
                $errMsg =~ s/\sat\s.*$//;
                print("ERROR: $errMsg\n");
            }
        }

    }
    else {
        if ( $isVerbose == 1 ) {
            print("ERROR: Write to file $destFile failed.\n");
        }
        $status = -1;
    }

    return $status;
}

#下载文件或者目录
sub download {
    my ( $self, $user, $src, $dest, $isVerbose, $followLinks ) = @_;
    $src =~ s/[\/\\]+/\//g;
    $dest =~ s/[\/\\]+/\//g;

    $src =~ s/^\s+//;
    $src =~ s/\s*$//;

    $dest =~ s/^\s+//;
    $dest =~ s/\s*$//;

    if ( not defined($user) ) {
        $user = 'none';
    }

    my $verboseOpt = '';
    if ( defined($isVerbose) and $isVerbose != 0 ) {
        $isVerbose  = 1;
        $verboseOpt = 'v';
    }
    else {
        $isVerbose = 0;
    }

    my $followLinksOpt = '';

    if ( defined($followLinks) ) {
        $followLinks    = 1;
        $followLinksOpt = 'h';
    }
    else {
        $followLinks = 0;
    }

    my $socket = $self->getConnection($isVerbose);

    my $agentCharset = $self->{agentCharset};
    my $charset      = $self->{charset};
    my $srcEncoded   = $src;
    my $userEncoded  = $user;

    if ( $charset ne $agentCharset ) {
        $srcEncoded  = Encode::encode( $agentCharset, Encode::decode( $charset, $src ) );
        $userEncoded = Encode::encode( $agentCharset, Encode::decode( $charset, $user ) );
    }

    $self->_writeChunk( $socket, "$userEncoded|download|$agentCharset|" . unpack( 'H*', $srcEncoded ) . '|' . unpack( 'H*', $followLinks ) );

    my $statusLine;
    eval { $statusLine = $self->_readChunk($socket); };
    if ($@) {
        $statusLine = $@;
        $statusLine =~ s/\sat\s+.*$//;
    }

    my $status   = 0;
    my $fileType = 'file';
    if ( $statusLine =~ /^Status:200,FileType:(\w+)/ ) {
        $fileType = $1;
        if ( $isVerbose == 1 ) {
            print("INFO: Download $fileType $src to $dest begin...\n");
        }
        $status = 0;
    }
    else {
        $status = -1;
        if ( $charset ne $agentCharset ) {
            $statusLine = Encode::encode( $charset, Encode::decode( $agentCharset, $statusLine ) );
        }
        print("ERROR:  Download $fileType $src to $dest failed.\n");
        close($socket);
        return $status;
    }

    if ( $fileType eq 'file' ) {
        if ( -d $dest ) {
            my $destFile = basename($src);
            $dest =~ s/\/$//;
            $dest = "$dest/$destFile";
        }

        $status = $self->_writeSockToFile( $socket, $dest, $isVerbose );

        close($socket);
    }
    elsif ( $fileType eq 'dir' or $fileType eq 'windir' ) {
        my $srcName = basename($src);
        if ( $dest =~ /[\/\\]$/ and $dest !~ /$srcName[\/\\]?$/ ) {
            $dest = $dest . $srcName;
        }
        $dest =~ s/[\/\\]+$//;

        my $destDir = dirname($dest);
        if ( not -d $destDir ) {
            $status = -1;
            print("ERROR: directory $destDir not exists.\n");
            close($socket);
            return $status;
        }

        if ( not -d $dest and not mkdir($dest) ) {
            $status = -1;

            print("ERROR: create directory $dest failed: $!\n");

            close($socket);
            return $status;
        }

        my $redirectOpt = "2>\&1";
        $redirectOpt = '' if ( $isVerbose != 1 );

        my $curDir = getcwd();
        if ( chdir($dest) ) {
            my $pipe;

            my $cmd = "| tar x${followLinksOpt}${verboseOpt}f - $redirectOpt";
            if ( $self->{ostype} eq 'windows' ) {
                $cmd = "| 7z.exe x -aoa -y -si -ttar";
            }

            my $pid = open( $pipe, $cmd );

            if ( defined($pid) and $pid != 0 ) {
                binmode($pipe);

                eval {
                    my $wrtLen = 0;
                    my $chunk;
                    do {
                        $chunk = $self->_readChunk($socket);
                        if ( defined($chunk) ) {
                            $wrtLen = syswrite( $pipe, $chunk );
                            if ( not defined($wrtLen) ) {
                                $status = -1;
                                print("ERROR: $!\n");
                            }
                        }
                    } while ( defined($chunk) );
                };
                if ($@) {
                    $status = -1;
                    my $errMsg = $@;
                    $errMsg =~ s/\sat\s.*$//;
                    print("ERROR: download failed, $errMsg\n");
                }

                close($pipe);

                if ( $status == 0 ) {
                    $status = $?;
                }
            }
            else {
                print("ERROR: Launch tar command failed:$!\n");
                $status = -1;
            }

            chdir($curDir);
        }
        else {
            print("ERROR: can not cd directory $dest:$!.\n");
            $status = -1;
        }

        close($socket);
    }
    elsif ( $fileType eq 'multiple' ) {
        close($socket);

        if ( $statusLine =~ /^Status:200,FileType:multiple,(.+)$/ ) {
            my @filePaths = split( '\|', $1 );
            foreach my $aFilePath (@filePaths) {
                $aFilePath = Encode::encode( $charset, Encode::decode( $agentCharset, $aFilePath ) );
                $self->download( $user, $aFilePath, $dest, $isVerbose, $followLinks );
            }
        }
    }
    else {
        print("ERROR: FileType $fileType not supported.\n");
        close($socket);
    }

    if ( $isVerbose == 1 ) {
        if ( $status == 0 ) {
            print("INFO: Download $src to $dest succeed.\n");
        }
        else {
            print("ERROR: Download $src to $dest failed.\n");
        }
    }

    return $status;
}

#用于读取tar或者7-zip的打包输出内容，并写入网络连接中
sub _readCmdOutToSock {
    my ( $self, $socket, $cmd, $isVerbose ) = @_;

    if ( not defined($isVerbose) ) {
        $isVerbose = 0;
    }

    my $status = 0;
    my $pipe;
    my $pid = open( $pipe, "$cmd |" );

    if ( defined($pid) and $pid != 0 ) {
        my ( $len, $buf );
        while ( $len = read( $pipe, $buf, 8 * 4096 ) ) {
            eval { $self->_writeChunk( $socket, $buf, $len ); };
            if ($@) {
                $status = -1;
                last;
            }
        }
        waitpid( $pid, 0 );
        my $exitStatus = $?;
        if ( $exitStatus ne 0 ) {
            $status = 1;
            print("ERROR: request ended with status:$exitStatus.\n");
        }
        else {
            eval { $self->_writeChunk( $socket, undef, 0 ); };
            if ($@) {
                $status = -1;
            }
        }

        if ($@) {
            $status = -1;
            my $errMsg = $@;
            $errMsg =~ s/\sat\s.*$//;
            print("ERROR: $errMsg");
        }

        close($pipe);
        $socket->shutdown(1);

        eval { $self->_readChunk($socket); };
        if ($@) {
            $status = -1;
            my $errMsg = $@;
            $errMsg =~ s/\sat\s.*$//;
            print("ERROR: $errMsg");
        }
    }
    else {
        $status = -1;
        print("ERROR: Can not launch command $cmd.\n");
        $socket->shutdown(2);
    }

    return $status;
}

#读取文件内容，并写入网络连接中
sub _readFileToSock {
    my ( $self, $socket, $filePath, $isVerbose, $convertCharset ) = @_;

    if ( not defined($isVerbose) ) {
        $isVerbose = 0;
    }

    my $agentCharset = $self->{agentCharset};
    my $charset      = $self->{charset};

    my $status = 0;
    my $fh;
    if ( open( $fh, "<$filePath" ) ) {
        my ( $len, $buf );
        binmode($fh);

        if ( $charset ne $agentCharset and defined($convertCharset) and $convertCharset == 1 ) {
            my $line;
            while ( $line = $fh->getline() ) {
                $line = Encode::encode( $agentCharset, Encode::decode( $charset, $line ) );
                eval { $self->_writeChunk( $socket, $line ); };
                if ($@) {
                    $status = -1;
                    last;
                }
            }
        }
        else {
            while ( $len = read( $fh, $buf, 8 * 4096 ) ) {
                eval { $self->_writeChunk( $socket, $buf ); };
                if ($@) {
                    $status = -1;
                    last;
                }
            }
        }

        $fh->close();

        if ( $status == 0 ) {
            if ( $status == 0 ) {
                eval { $self->_writeChunk( $socket, undef, 0 ) };
            }
            else {
                eval { $self->_writeChunk( $socket, "upload failed", 0 ) };
            }
        }

        if ($@) {
            $status = -1;
            if ( $isVerbose == 1 ) {
                my $errMsg = $@;
                $errMsg =~ s/\sat\s.*$//;
                print("ERROR: $errMsg");
            }
        }

        eval { $self->_readChunk($socket); };

        if ($@) {
            $status = -1;
            if ( $isVerbose == 1 ) {
                my $errMsg = $@;
                $errMsg =~ s/\sat\s.*$//;
                print("ERROR: $errMsg");
            }
        }
    }
    else {
        $status = -1;
        if ( $isVerbose == 1 ) {
            print("ERROR: Can not open file:$filePath, $!.\n");
        }
        $socket->shutdown(2);
    }

    return $status;
}

#下载URL中的文件内容，写入网络连接中
sub _readUrlToSock {
    my ( $self, $socket, $url, $isVerbose, $convertCharset ) = @_;

    if ( not defined($isVerbose) ) {
        $isVerbose = 0;
    }

    my $agentCharset = $self->{agentCharset};
    my $httpCharset;

    my $status = 0;

    my $http = HTTP::Tiny->new();
    my $args = {};
    $args->{data_callback} = sub {
        my ( $data, $res ) = @_;
        if ( $res->{status} == 200 ) {
            if ( defined($convertCharset) and $convertCharset == 1 ) {
                if ( not defined($httpCharset) ) {
                    my $contentType = $res->{headers}->{'content-type'};
                    if ( defined($contentType) and $contentType =~ /charset=(.*?)$/ ) {
                        $httpCharset = $1;
                    }
                }
                if ( defined($httpCharset) and $httpCharset ne '' and $httpCharset ne $agentCharset and defined($convertCharset) and $convertCharset == 1 ) {
                    $data = Encode::encode( $agentCharset, Encode::decode( $httpCharset, $data ) );
                }
            }

            $self->_writeChunk( $socket, $data );
        }
        else {
            $status = 3;
        }
    };

    eval { my $response = $http->request( 'GET', $url, $args ); };

    if ( $status == 0 ) {
        eval { $self->_writeChunk( $socket, undef, 0 ) };
        if ($@) {
            $status = -1;
            if ( $isVerbose == 1 ) {
                my $errMsg = $@;
                $errMsg =~ s/\sat\s.*$//;
                print("ERROR: $errMsg");
            }
        }

        $socket->shutdown(1);
        eval { $self->_readChunk($socket); };
        if ($@) {
            $status = -1;
            if ( $isVerbose == 1 ) {
                my $errMsg = $@;
                $errMsg =~ s/\sat\s.*$//;
                print("ERROR: $errMsg");
            }
        }

    }
    elsif ( $status == 3 ) {
        if ( $isVerbose == 1 ) {
            print("ERROR: Can not open or download failed:$url.\n");
        }
        $socket->shutdown(2);
    }
    else {
        eval { $self->_readChunk($socket); };
        if ($@) {
            $status = -1;
            if ( $isVerbose == 1 ) {
                my $errMsg = $@;
                $errMsg =~ s/\sat\s.*$//;
                print("ERROR: $errMsg");
            }
        }
        $socket->shutdown(2);
    }

    return $status;
}

#创建并写入远程文件
sub writeFile {
    my ( $self, $user, $content, $dest, $isVerbose, $convertCharset ) = @_;
    $dest =~ s/\\/\//g;
    my $destName = basename($dest);

    if ( not defined($isVerbose) ) {
        $isVerbose = 0;
    }

    my $ostype = $self->{ostype};

    my $socket = $self->getConnection($isVerbose);

    my $agentCharset    = $self->{agentCharset};
    my $charset         = $self->{charset};
    my $destEncoded     = $dest;
    my $destNameEncoded = $destName;
    my $userEncoded     = $user;

    if ( $charset ne $agentCharset ) {
        if ( defined($convertCharset) and $convertCharset == 1 ) {
            $content = Encode::encode( $agentCharset, Encode::decode( $charset, $content ) );
        }

        $destEncoded     = Encode::encode( $agentCharset, Encode::decode( $charset, $dest ) );
        $destNameEncoded = Encode::encode( $agentCharset, Encode::decode( $charset, $destName ) );
        $userEncoded     = Encode::encode( $agentCharset, Encode::decode( $charset, $user ) );
    }

    my $param = unpack( 'H*', 'file' ) . '|' . unpack( 'H*', $destNameEncoded ) . '|' . unpack( 'H*', $destEncoded );
    $self->_writeChunk( $socket, "$userEncoded|upload|$agentCharset|$param" );

    my $preStatus;
    eval { $preStatus = $self->_readChunk($socket); };
    if ($@) {
        $preStatus = $@;
        $preStatus =~ s/\sat\s+.*$//;
    }

    if ( $preStatus !~ /^\s*Status:200/ ) {
        close($socket);
        if ( $isVerbose == 1 ) {
            print("ERROR: write file failed:$preStatus.\n");
        }
        return -1;
    }

    if ( $isVerbose == 1 ) {
        print("INFO: write reomte file:$dest begin...\n");
    }

    my $status = 0;

    eval {
        $self->_writeChunk( $socket, $content );
        $self->_writeChunk( $socket, undef, 0 );
    };
    if ($@) {
        $status = -1;
        if ( $isVerbose == 1 ) {
            my $errMsg = $@;
            $errMsg =~ s/\sat\s.*$//;
            print("ERROR: $errMsg");
        }
    }

    $socket->shutdown(1);

    eval { $self->_readChunk($socket); };
    if ($@) {
        $status = -1;
        if ( $isVerbose == 1 ) {
            my $errMsg = $@;
            $errMsg =~ s/\sat\s.*$//;
            print("ERROR: $errMsg");
        }
    }

    if ( $isVerbose == 1 ) {
        if ( $status == 0 ) {
            print("INFO: write remote file:$dest succeed.\n");
        }
        else {
            print("ERROR: write remote file:$dest failed.\n");
        }
    }

    close($socket);
    return $status;
}

#上传文件或者目录
sub upload {
    my ( $self, $user, $src, $dest, $isVerbose, $convertCharset, $followLinks ) = @_;
    $src =~ s/\\/\//g;
    $dest =~ s/\\/\//g;

    $src =~ s/^\s+//;
    $src =~ s/\s*$//;

    $dest =~ s/^\s+//;
    $dest =~ s/\s*$//;

    if ( not defined($user) ) {
        $user = 'none';
    }

    my $verboseOpt = '';
    if ( defined($isVerbose) and $isVerbose != 0 ) {
        $isVerbose  = 1;
        $verboseOpt = 'v';
    }
    else {
        $isVerbose = 0;
    }

    my $followLinksOpt = '';

    if ( defined($followLinks) ) {
        $followLinks    = 1;
        $followLinksOpt = 'h';
    }
    else {
        $followLinks = 0;
    }

    my $ostype = $self->{ostype};

    my $fileType = 'file';
    if ( -d $src ) {
        $fileType = 'dir';
        $fileType = 'windir' if ( $ostype eq 'windows' );
    }
    elsif ( $src =~ /^https?:\/\// ) {
        $fileType = 'url';
    }

    if ( $fileType ne 'url' and not -e $src ) {
        print("ERROR: $src not exists.\n");
        return -1;
    }

    my $socket = $self->getConnection($isVerbose);

    my $agentCharset = $self->{agentCharset};
    my $charset      = $self->{charset};
    my $srcEncoded   = $src;
    my $destEncoded  = $dest;
    my $userEncoded  = $user;

    if ( $charset ne $agentCharset ) {
        $srcEncoded  = Encode::encode( $agentCharset, Encode::decode( $charset, $src ) );
        $destEncoded = Encode::encode( $agentCharset, Encode::decode( $charset, $dest ) );
        $userEncoded = Encode::encode( $agentCharset, Encode::decode( $charset, $user ) );
    }

    my $param = unpack( 'H*', $fileType ) . '|' . unpack( 'H*', $srcEncoded ) . '|' . unpack( 'H*', $destEncoded ) . '|' . unpack( 'H*', $followLinks );
    if ( $fileType eq 'url' ) {
        $param = unpack( 'H*', 'file' ) . '|' . unpack( 'H*', $srcEncoded ) . '|' . unpack( 'H*', $destEncoded ) . '|' . unpack( 'H*', $followLinks );
    }

    $self->_writeChunk( $socket, "$userEncoded|upload|$agentCharset|$param" );

    my $preStatus;
    eval { $preStatus = $self->_readChunk($socket); };
    if ($@) {
        $preStatus = $@;
        $preStatus =~ s/\sat\s+.*$//;
    }

    if ( $preStatus !~ /^\s*Status:200/ ) {
        close($socket);
        print("ERROR: Upload failed, server error:$preStatus");
        return -1;
    }

    if ( $isVerbose == 1 ) {
        print("INFO: Upload $fileType $src to $dest begin...\n");
    }

    my $status = 0;
    if ( $fileType eq 'file' ) {
        $status = $self->_readFileToSock( $socket, $src, $isVerbose, $convertCharset );
    }
    elsif ( $fileType eq 'dir' or $fileType eq 'windir' ) {
        my $curDir = getcwd();
        chdir($src);
        my $cmd = "tar c${followLinksOpt}${verboseOpt}f - .";
        if ( $self->{ostype} eq 'windows' ) {
            $cmd = "7z.exe a dummy -ttar -y -so .";
        }

        $status = $self->_readCmdOutToSock( $socket, $cmd, $isVerbose );
        chdir($curDir);
    }
    elsif ( $fileType eq 'url' ) {
        $status = $self->_readUrlToSock( $socket, $src, $isVerbose, $convertCharset );
    }

    #get the error Message, if no errMsg, succeed.
    #my $errMsg = $self->_readChunk($socket);

    if ( $isVerbose == 1 ) {
        if ( $status == 0 ) {
            print("INFO: Upload $src to $dest succeed.\n");
        }
        else {
            print("ERROR: Upload $src to $dest failed.\n");
        }
    }

    close($socket);
    return $status;
}

1;
