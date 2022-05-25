#!/usr/bin/perl
use strict;

package WebCtl;
use FindBin;
use IO::Socket::SSL;
use Encode;
use REST::Client;
use HTTP::Cookies;
use Mojo::JSON qw(to_json from_json);
use Data::UUID;
use URI::Escape;
use Digest::SHA qw(hmac_sha1_base64);
use Data::Dumper;
use File::Basename;
use MIME::Base64;

sub new {
    my ($type) = @_;

    my $self = {};

    #$self->{$_} = $attrs->{$_} for keys(%$attrs);
    bless( $self, $type );

    my $client = REST::Client->new();
    $client->setFollow(1);
    $client->setTimeout(60);

    my $ua = $client->getUseragent();    #返回LWP::UserAgent对象
    $ua->ssl_opts( verify_hostname => 0, SSL_verify_mode => IO::Socket::SSL::SSL_VERIFY_NONE, SSL_use_cert => 0 );
    $ua->agent('Mozilla/5.0 (Macintosh; Intel Mac OS X 10_14_3) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/72.0.3626.109 Safari/537.36');
    $ua->max_redirect(100);

    #save cookies
    my $jar = HTTP::Cookies->new();
    $ua->cookie_jar($jar);

    $self->{restClient} = $client;

    my $passStore = {};
    $self->{passStore} = $passStore;

    no warnings 'redefine';

    sub LWP::UserAgent::get_basic_credentials {
        my ( $self, $realm, $url ) = @_;

        my $urlLen  = length($url);
        my $lastIdx = $urlLen;

        my ( $user, $pass );
        while ( $lastIdx > 0 ) {
            my $subUrl = substr( $url, 0, $lastIdx );

            #print("DEBUG:check pass for:$subUrl---------\n");
            my $entry = $passStore->{$subUrl};
            if ( defined($entry) ) {
                $user = $$entry[0];
                $pass = $$entry[1];
                last;
            }

            $lastIdx = $lastIdx - 1;
            $lastIdx = rindex( $url, '/', $lastIdx );
        }

        return $user, $pass;
    }

    return $self;
}

sub addCredentials {
    my ( $self, $url, $user, $pass ) = @_;

    my $passStore = $self->{passStore};

    my $client    = $self->{restClient};
    my $authToken = 'Basic ' . MIME::Base64::encode( $user . ':' . $pass );
    $client->addHeader( 'Authorization', $authToken );

    $url =~ s/^(https?):\/\///;
    my $protocol = $1;

    $url =~ s/\?.*$//;

    my @parts   = split( '/', $url );
    my $service = $parts[0];
    $passStore->{$service}                = [ $user, $pass ];
    $passStore->{"$protocol://$service"}  = [ $user, $pass ];
    $passStore->{"$service/"}             = [ $user, $pass ];
    $passStore->{"$protocol://$service/"} = [ $user, $pass ];

    my $serviceNoPort;
    if ( $service =~ /:80$/ or $service =~ /:443$/ ) {
        $serviceNoPort = $service;
        $serviceNoPort =~ s/:\d+//;
    }
    if ( defined($serviceNoPort) and $serviceNoPort ne '' ) {
        $passStore->{$serviceNoPort}                = [ $user, $pass ];
        $passStore->{"$protocol://$serviceNoPort"}  = [ $user, $pass ];
        $passStore->{"$serviceNoPort/"}             = [ $user, $pass ];
        $passStore->{"$protocol://$serviceNoPort/"} = [ $user, $pass ];
    }

    my $realm = '';
    my $max   = scalar(@parts);
    my $i     = 1;
    for ( $i = 1 ; $i < $max ; $i++ ) {
        $realm = $realm . '/' . $parts[$i];

        #print("DEBUG:add cred:$protocol://$service$realm\n");
        $passStore->{"$service$realm"}             = [ $user, $pass ];
        $passStore->{"$protocol://$service$realm"} = [ $user, $pass ];
        if ( defined($serviceNoPort) and $serviceNoPort ne '' ) {
            $passStore->{"$serviceNoPort$realm"}             = [ $user, $pass ];
            $passStore->{"$protocol://$serviceNoPort$realm"} = [ $user, $pass ];
        }
    }
}

sub convCharSet {
    my ( $self, $content, $charSet ) = @_;
    my $client = $self->{restClient};

    my $contentEncoding;

    if ( not defined($charSet) ) {
        $contentEncoding = 'UTF-8';
        my $contentType = $client->responseHeader('Content-Type');
        if ( $contentType =~ /charset=(.*)$/ ) {
            $contentEncoding = uc($1);
        }
    }
    else {
        $contentEncoding = $charSet;
    }

    # my $lang     = $ENV{LANG};
    # my $encoding = lc( substr( $lang, rindex( $lang, '.' ) + 1 ) );
    # if ( $encoding eq '' or uc($encoding) eq 'UTF8' ) {
    #     $encoding = 'UTF-8';
    # }
    # if ( $encoding ne $contentEncoding ) {
    #     $content = Encode::encode( $encoding, Encode::decode( $contentEncoding, $content ) );
    # }

    if ( $contentEncoding ne 'UTF-8' ) {
        $content = Encode::encode( 'UTF-8', Encode::decode( $contentEncoding, $content ) );
    }

    return $content;
}

sub buildQuery {
    my ( $self, $data ) = @_;
    my $client = $self->{restClient};
    return $client->buildQuery($data);
}

sub buildData {
    my ( $self, $data ) = @_;
    my $client = $self->{restClient};
    my $params = substr( $client->buildQuery($data), 1 );
    return $params;
}

sub setHeaders {
    my ( $self, $headers ) = @_;

    my $client = $self->{restClient};

    my $res = $client->{_res};
    if ( defined($res) ) {
        my $referer = $client->{_res}->request->uri;
        if ( defined($referer) and $referer ne '' ) {
            $client->addHeader( 'Referer', $referer );
        }
    }

    if ( defined($headers) ) {
        foreach my $keyName ( keys(%$headers) ) {
            $client->addHeader( $keyName, $headers->{$keyName} );
        }
    }
}

sub get {
    my ( $self, $url, $headers ) = @_;

    my $client = $self->{restClient};

    $self->setHeaders($headers);

    $client->GET($url);

    my $content = $self->convCharSet( $client->responseContent() );
    if ( $client->responseCode() eq 500 or $client->responseCode() eq 404 or $client->responseCode() eq 401 ) {
        die( "GET $url failed," . $content . "\n" );
    }

    #print( "DEBUG: \n", $content, "\n" );

    return $content;
}

sub doPost {
    my ( $self, $url, $params ) = @_;

    my $client = $self->{restClient};
    $client->POST( $url, $params );

    my $content = $self->convCharSet( $client->responseContent() );
    if ( $client->responseCode() >= 400 ) {
        die( "POST $url failed," . $content . "\n" );
    }

    if ( $client->responseCode() eq 302 or $client->responseCode() eq 301 ) {
        my $location = $client->{_res}->header('Location');
        $self->get($location);
    }

    #print( "DEBUG: \n", $content, "\n" );

    return $content;
}

sub post {
    my ( $self, $url, $data, $headers ) = @_;

    my $client = $self->{restClient};
    $client->addHeader( 'Content-Type', 'application/x-www-form-urlencoded; charset=UTF-8' );
    $self->setHeaders($headers);

    my $params = $self->buildData($data);

    return $self->doPost( $url, $params );
}

sub postJson {
    my ( $self, $url, $data, $headers ) = @_;

    my $client = $self->{restClient};
    $client->addHeader( 'Content-Type', 'application/json;charset=UTF-8' );
    $self->setHeaders($headers);

    my $params = to_json($data);

    return $self->doPost( $url, $params );
}

sub doRest {
    my ( $self, $method, $url, $data, $headers ) = @_;
    my $params;

    if ( defined($data) ) {
        $params = to_json($data);
    }

    my $client = $self->{restClient};
    $client->addHeader( 'Content-Type', 'application/json;charset=UTF-8' );

    if ( defined($headers) ) {
        $client->request( $method, $url, $params, %$headers );
    }
    else {
        $client->request( $method, $url, $params );
    }

    my $content = $self->convCharSet( $client->responseContent() );
    if ( $client->responseCode() eq 500 or $client->responseCode() eq 404 or $client->responseCode() eq 401 ) {
        die( "Do REST $url failed," . $content . "\n" );
    }

    if ( $client->responseCode() eq 302 or $client->responseCode() eq 301 ) {
        my $location = $client->{_res}->header('Location');
        $self->get($location);
    }

    return $content;
}

sub getBoundary {
    my @charsSet;
    push( @charsSet, chr($_) ) for 48 .. 57;
    push( @charsSet, chr($_) ) for 97 .. 122;
    push( @charsSet, chr($_) ) for 65 .. 90;

    my $randStr = '----';
    $randStr = $randStr . $charsSet[ rand(62) ] for 1 .. 28;
    return $randStr;
}

sub upload {
    my ( $self, $url, $fileField, $filePath, $formData, $headers ) = @_;

    my $client = $self->{restClient};
    $self->setHeaders($headers);

    #upload file
    my $ua = $client->getUseragent();

    #my $deployData = [ appId => $appId, deployType => $deployType, deployTo => $deployTo, publishCount => $publishCount, app_package => [ $appPackage, $pkgName, Content_Type => 'application/octet-stream' ] ];
    my $fileName = basename($filePath);
    $formData->{$fileField} = [ $filePath, $fileName, Content_Type => 'application/octet-stream' ];

    my $response = $ua->post(
        $url,
        Content_Type => 'multipart/form-data;boundary=' . $self->getBoundary(),
        Content      => $formData
    );

    my $contentType     = $response->header('Content-Type');
    my $contentEncoding = 'utf-8';
    if ( $contentType =~ /charset=(.*)$/ ) {
        $contentEncoding = $1;
    }

    my $content = $self->convCharSet( $response->content, $contentEncoding );

    if ( $response->code() eq 500 or $response->code() eq 404 or $response->code() eq 401 ) {
        die( "upload failed:$url," . $content . "\n" );
    }

    if ( $response->code() eq 302 or $response->code() eq 301 ) {
        my $location = $response->header('Location');
        $content = $self->get($location);
    }

    #print("INFO:deploy return json=============\n");
    #print($content, "\n");
    #print("INFO:===============================\n");

    return $content;
}

sub download {
    my ( $self, %args ) = @_;

=head
    #使用方法样例
    $webCtl->download(url=>'https://xxxx',
                      method=>'POST',
                      data=>'{"key":"value"}',
                      headers=>{sid=>'xxxxxxx'},
                      saveTo=>'/myapp/mydir/'
                      );
=cut

    my $url        = $args{url};         #访问的URL
    my $method     = $args{method};      #GET|POST
    my $data       = $args{data};        #如果传入的data是HASH，就当成是post form的data来处理, 否则当成是json文本来处理
    my $headers    = $args{headers};     #自定义的header的Hasp的引用，譬如：验证Token的Header或其他特殊Header
    my $saveToFile = $args{saveTo};      #Save的目标，如果是目录(目录要提前创建），则自动计算文件名，否则直接存放到指定的文件
    my $callback   = $args{callback};    #如果定义了saveTo，此选项失效，用户自行处理下载的内容

    my $client = $self->{restClient};
    $client->setFollow(1);

    my $formData;

    #根据提交的数据的类型，判断是post form data还是post json
    if ( defined($data) ) {
        if ( ref($data) eq 'HASH' ) {

            #如果传入的data是HASH，就当成是post form的data来处理
            $formData = $self->buildData($data);
            $client->addHeader( 'Content-Type', 'application/x-www-form-urlencoded; charset=UTF-8' );
        }
        else {
            #否则当成是json文本来处理
            $formData = $data;
            $client->addHeader( 'Content-Type', 'application/json;charset=UTF-8' );
        }
    }
    if ( defined($headers) ) {
        $self->setHeaders($headers);
    }

    my $fileWriter;
    if ( defined($saveToFile) ) {
        if ( -d $saveToFile ) {

            #如果指定保存到的目标是目录，则通过HTTP Response header里的Content-Disposition自动计算文件名
            my $checked = 0;

            #save to directory
            my $saveCallback = sub {
                my ( $chunk, $res ) = @_;
                if ( $checked == 0 ) {
                    $checked = 1;
                    if ( $res->code eq 200 ) {
                        my $contentDisposition = $res->header('Content-Disposition');

                        #attachment; filename="filename.jpg"
                        #attachment;filename*=UTF-8''文件名.txt
                        my $fileName = 'unknown';
                        if ( $contentDisposition =~ /filename="(.*?)"$/ ) {
                            $fileName = $1;
                        }
                        elsif ( $contentDisposition =~ /filename=(.*?)$/ ) {
                            $fileName = $1;
                        }
                        elsif ( $contentDisposition =~ /filename*=(.*?)''(.*?)$/ ) {
                            my $charSet = $1;
                            $fileName = uc($2);
                            if ( $charSet ne 'UTF-8' ) {
                                $fileName = Encode::encode( 'UTF-8', Encode::decode( $charSet, $fileName ) );
                            }
                        }
                        $saveToFile = "$saveToFile/$fileName";
                        $fileWriter = IO::File->new(">$saveToFile");
                        if ( not defined($fileWriter) ) {
                            die("ERROR: Create file $saveToFile failed, $!");
                        }
                    }
                }

                print $fileWriter($chunk);
            };

            $client->setContentFile( \&$saveCallback );
        }
        else {
            #如果指定的目标不是存在的目录，则当成存储目标来处理，直接存放到改指定的文件
            my $saveToFileDir = dirname($saveToFile);
            if ( -d $saveToFileDir ) {
                $client->setContentFile($saveToFile);
            }
            else {
                die("Directory $saveToFileDir not exists.");
            }
        }
    }
    elsif ( defined($callback) ) {

        #如果传入的是callback函数，则调用callback函数进行下载数据的处理
        $client->setContentFile( \&$callback );
    }

    #发出请求
    $client->request( $method, $url, $formData );

    if ( defined($fileWriter) ) {
        $fileWriter->close();
    }

    if ( $client->responseCode() ne 200 ) {
        my $errMsg = $client->responseContent();
        die("ERROR: download $url failed, cause by:$errMsg\n");
    }
}

1;

