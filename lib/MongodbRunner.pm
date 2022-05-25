#!/usr/bin/perl
use strict;

package MongodbRunner;
use FindBin;
use utf8;
use IO::File;
use Getopt::Long;
use File::Basename;
use MongoDB;
use Config::IniFiles;
use Cwd;
use Try::Tiny;
use Crypt::RC4;

sub _rc4_decrypt_hex ($$) {
    my ( $key, $data ) = ( $_[0], $_[1] );
    return RC4( $key, pack( 'H*', $data ) );
}

sub new {
    my ($type) = @_;

    my $pwd         = getcwd;
    my $cfg_path    = $pwd . '/../../../conf/config.ini';
    my $cfg         = Config::IniFiles->new( -file => "$cfg_path" );
    my $db_url      = $cfg->val( 'autoexec', 'db.url' );
    my $db_name     = $cfg->val( 'autoexec', 'db.name' );
    my $db_username = $cfg->val( 'autoexec', 'db.username' );
    my $pass_key    = $cfg->val( 'autoexec', 'password.key' );
    my $db_password = $cfg->val( 'autoexec', 'db.password' );

    if ( $db_password =~ /\{ENCRYPTED\}/ ) {
        my $MY_KEY = 'c3H002LGZRrseEPc';
        $pass_key = _rc4_decrypt_hex( $MY_KEY, $pass_key );
    }

    if ( $db_password =~ /\{ENCRYPTED\}/ ) {
        $db_password =~ s/\{ENCRYPTED\}//;
        $db_password = _rc4_decrypt_hex( $pass_key, $db_password );
    }

    my $dbclient = MongoDB::MongoClient->new(
        host     => $db_url,
        username => $db_username,
        password => $db_password,
        db_name  => $db_name
    ) or die "mongodb connect failed.\n";

    my $mydb = $dbclient->get_database($db_name);
    my $self = {
        db_url      => $db_url,
        db_name     => $db_name,
        db_username => $db_username,
        db_password => $db_password,
        dbclient    => $dbclient,
        mydb        => $mydb
    };
    return bless( $self, $type );
}

sub find {
    my ( $self, %args ) = @_;
    my $table   = $args{table};
    my $filter  = $args{filter};
    my $options = $args{options};
    if ( not defined($filter) or $filter eq '' ) {
        $filter = {};
    }
    if ( not defined($options) or $options eq '' ) {
        $options = {};
    }
    my $mydb       = $self->{mydb};
    my $collection = $mydb->get_collection($table);
    my @content    = ();
    try {
        @content = $collection->find( $filter, $options )->all;
    }
    catch {
        print("ERROR: cmdb query table $table failed ,reason:$_ .\n");
    };
    return @content;
}

sub count {
    my ( $self, %args ) = @_;
    my $table   = $args{table};
    my $filter  = $args{filter};
    my $options = $args{options};
    if ( not defined($filter) or $filter eq '' ) {
        $filter = {};
    }
    if ( not defined($options) or $options eq '' ) {
        $options = {};
    }
    my $mydb       = $self->{mydb};
    my $collection = $mydb->get_collection($table);
    my $count      = 0;
    try {
        $count = $collection->count_documents( $filter, $options );
    }
    catch {
        print("ERROR: cmdb query table $table failed ,reason:$_ .\n");
    };
    return $count;
}

sub insert {
    my ( $self, %args ) = @_;
    my $table      = $args{table};
    my $data       = $args{data};
    my $mydb       = $self->{mydb};
    my $collection = $mydb->get_collection($table);
    my $isSuccess;
    try {
        $collection->insert_one($data);
        $isSuccess = 0;
    }
    catch {
        print("ERROR: cmdb insert table $table failed ,reason:$_ .\n");
        $isSuccess = 1;
    };
    return $isSuccess;
}

sub update {
    my ( $self, %args ) = @_;
    my $table      = $args{table};
    my $data       = $args{data};
    my $filter     = $args{filter};
    my $mydb       = $self->{mydb};
    my $collection = $mydb->get_collection($table);
    my $isSuccess;
    try {
        my $update_data = { "\$set" => $data };
        $collection->update_many( $filter, $update_data );
        $isSuccess = 0;
    }
    catch {
        print("ERROR: cmdb update table $table failed ,reason:$_ .\n");
        $isSuccess = 1;
    };
    return $isSuccess;
}

sub delete {
    my ( $self, %args ) = @_;
    my $table      = $args{table};
    my $filter     = $args{filter};
    my $mydb       = $self->{mydb};
    my $collection = $mydb->get_collection($table);
    my $isSuccess;
    try {
        $collection->delete_many($filter);
        $isSuccess = 0;
    }
    catch {
        print("ERROR: cmdb delete table $table failed ,reason:$_ .\n");
        $isSuccess = 1;
    };
    return $isSuccess;
}

sub close {
    my ($self) = @_;
    my $dbclient = $self->{dbclient};
    try {
        $dbclient->disconnect;
    }
    catch {
        print("ERROR: cmdb close dbclient failed ,reason:$_ .\n");
    };
}

1;
