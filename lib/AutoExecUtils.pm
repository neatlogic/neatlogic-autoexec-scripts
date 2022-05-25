#!/usr/bin/perl

use FindBin;
use lib "$FindBin::Bin/../lib/perl-lib/lib/perl5";
use lib "$FindBin::Bin/../lib";

use strict;

package AutoExecUtils;

use IO::File;
use JSON qw(to_json from_json encode_json);

sub setEnv {
    hidePwdInCmdLine();
    $ENV{OUTPUT_PATH} = "$FindBin::Bin/output.json";
}

sub hidePwdInCmdLine {
    my @args = ($0);
    my $arg;
    for ( my $i = 0 ; $i <= $#ARGV ; $i++ ) {
        $arg = $ARGV[$i];
        if ( $arg =~ /[-]+\w*pass\w*[^=]/ or  $arg =~ /[-]+\w*account\w*[^=]/ ) {
            push( @args, $arg );
            push( @args, '******' );
            $i = $i + 1;
        }
        else {
            $arg =~ s/"password":\K".*?"/"******"/ig;
            push( @args, $arg );
        }
    }
    $0 = join( ' ', @args );
}

sub saveOutput {
    my ($outputData) = @_;
    my $outputPath = "$FindBin::Bin/output.json";

    if ( defined($outputPath) and $outputPath ne '' ) {
        my $fh = IO::File->new(">$outputPath");
        if ( defined($fh) ) {
            print $fh ( to_json( $outputData, { utf8 => 0 } ) );
            $fh->close();
        }
        else {
            die("ERROR: Can not open output file:$outputPath to write.\n");
        }
    }
}

1;

