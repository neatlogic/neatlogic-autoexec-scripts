#!/usr/bin/perl
use FindBin;
use lib "$FindBin::Bin/lib";
use lib "$FindBin::Bin/lib/perl-lib/lib/perl5";

package MysqlConfParser;

use strict;
use Getopt::Long;
use File::Basename;
use IO::File;
use File::Copy;
use File::Path qw(make_path);
use POSIX qw(strftime);
use File::Spec::Functions qw(catfile rel2abs);

use AutoExecUtils;

#Mysql option文件配置读取和修改，支持!include和!includedir
#支持多文件式的mysql配置的增加、修改，但不支持删除配置
#因为多文件配置，同一个section声明可以存在于多个文件中，所以新增的option会自动选择文件名和section名最为接近的文件进行相应的修改
sub new {
    my ( $pkg, $filePath, $needBackup ) = @_;

    my $self = {
        hasError       => 0,
        needBackup     => $needBackup,
        ini            => { sectionComments => {}, optComments => {} },
        sectionFileMap => {},                                             #section和配置文件的关联，记录最佳的配置文件
        modified       => 0,                                              #从整体上标记配置是否发生过修改
        changedMap     => {},
        backupMap      => {},                                             # #标记在修改过程中，哪些配置文件是否发生过修改
        current        => undef                                           #当前的section名称
    };

    $self->{multipleOptions} = {
        'binlog-do-db'     => 1,
        'binlog-ignore-db' => 1,
        'plugin-load'      => 1
    };

    #记录已经修改过的可重复option
    $self->{multipleOptionsModifed} = {};

    bless( $self, $pkg );

    if ( defined($filePath) ) {
        if ( not -e $filePath ) {
            $self->{hasError} = 1;
            print("ERROR: $filePath not exists.\n");
        }
        if ( not -f $filePath ) {
            $self->{hasError} = 1;
            print("ERROR: $filePath is not a file.\n");
        }

        $self->{rootDir} = dirname($filePath);
        my $dateTimeStr = strftime( "%Y%m%d-%H%M%S", localtime() );
        my $backupDir   = "$filePath.$dateTimeStr";
        $self->{backupDir} = $backupDir;
    }

    if ( defined($filePath) ) {
        $self->__read_config( $filePath, 'file' );
    }

    return $self;
}

sub getFileContent {
    my ( $self, $filePath ) = @_;
    my $content;

    if ( -f $filePath ) {
        my $size = -s $filePath;
        my $fh   = new IO::File("<$filePath");

        if ( defined($fh) ) {
            $fh->read( $content, $size );
            $fh->close();
        }
        else {
            die("ERROR: File:$filePath open failed, $!.\n");
        }
    }

    return $content;
}

sub getConfig {
    my ( $self, $confTxt ) = @_;

    if ( defined($confTxt) ) {
        $self->{ini} = { sectionComments => {}, optComments => {} };
        $self->__read_config( $confTxt, 'text' );
    }

    return $self->{ini};
}

sub __read_config {
    my ( $self, $path, $what ) = @_;

    if ( not defined($what) ) {
        $what = 'file';
    }

    my $content = "";

    # store the names to skip when reading directories
    my %skip;
    my @skip_names = qw(. ..);
    @skip{@skip_names} = (1) x @skip_names;

    if ( $what eq 'text' ) {
        $content = $path;
        $self->__parseINI( $content, $path );
    }
    elsif ( $what eq "file" ) {
        if ( not -f ($path) ) {
            $self->{hasError} = 1;
            print("ERROR: $path is not a file.\n");
        }

        $content = $self->getFileContent($path);
        $self->__parseINI( $content, $path );
    }
    elsif ( $what eq "dir" ) {
        my $dirh;
        if ( not opendir( $dirh, $path ) ) {
            $self->{hasError} = 1;
            print("ERROR: Open directory $path failed, $!.\n");
        }

        while ( my $file = readdir($dirh) ) {

            # skip invisible files and directories we shouldn't
            # recurse into, like ../ or CVS/
            next if $skip{$file} or index( $file, "." ) == 0;

            my $filepath = catfile( $path, $file );

            if ( -f $filepath ) {
                __read_config( $self, $filepath, 'file' );
            }
            elsif ( -d $filepath ) {
                __read_config( $self, $filepath, 'dir' );
            }
        }

        closedir($dirh);
    }
}

sub __parseINI {
    my ( $self, $content, $filePath ) = @_;

    my $baseDir         = dirname($filePath);
    my $ini             = $self->{ini};
    my $sectionComments = $ini->{sectionComments};
    my $optComments     = $ini->{optComments};
    my $sectionFileMap  = $self->{sectionFileMap};
    my $current         = $self->{current};
    my $section         = {};

    my $comment = '';
    $content =~ s/^\s*|\s*$//g;
    foreach my $line ( split( /\n/, $content ) ) {
        $line =~ s/^\s*|\s*$//g;

        # handle comments
        if ( $line =~ /^[;#]/ ) {
            $comment = $comment . $line . "\n";
            next;
        }
        elsif ( $line eq '' ) {
            $comment = $comment . "\n";
            next;
        }

        # handle includes
        if ( $line =~ /^\s*!include(dir)?\s+(.+)\s*$/ ) {
            my $incDir   = $1;
            my $filePath = $2;
            if ( defined($incDir) ) {
                $self->__read_config( rel2abs( $filePath, $baseDir ), 'dir' );
            }
            else {
                $self->__read_config( rel2abs( $filePath, $baseDir ), 'file' );
            }
            next;
        }

        #handle section
        elsif ( $line =~ /^\s*\[(.*)\]\s*$/ ) {
            $current = $1;
            if ( defined( $ini->{$current} ) ) {

                #如果已经存在section，那么此section在多个文件中有配置，计算最匹配的文件，用于配置增加的option
                $section = $ini->{$current};
                my $preSectionFile = basename( $sectionFileMap->{$current} );
                my $curSectionFile = basename($filePath);
                if ( not defined($preSectionFile) ) {
                    $sectionFileMap->{$current} = $filePath;
                }
                elsif ( not $preSectionFile =~ /$current/ and $curSectionFile =~ /$current/ ) {
                    $sectionFileMap->{$current} = $filePath;
                }
                elsif ( length($curSectionFile) < length($preSectionFile) ) {
                    $sectionFileMap->{$current} = $filePath;
                }
            }
            else {
                my $newSection = {};
                $ini->{$current} = $newSection;
                $section = $newSection;

                if ( defined($comment) and $comment ne '' ) {
                    my $thisComment = $comment;
                    $thisComment =~ s/^\s*|\s*$//g;
                    $sectionComments->{$current} = $thisComment;
                    undef($comment);
                    $comment = '';
                }
                $sectionFileMap->{$current} = $filePath;
            }
            next;
        }

        if ( $line !~ /=/ ) {
            $line = join( '=', $line, 1 );
        }

        my ( $k, $v ) = split( /\s*=\s*/, $line, 2 );
        my $oldV = $section->{$k};

        my $multipleOptions = $self->{multipleOptions};

        #mysql的配置中binlog-do-db和binlog-ignore-db以及plugin-load是可以重复配置的
        if ( $multipleOptions->{$k} ) {
            if ( ref($oldV) eq "ARRAY" ) {
                push( @$oldV, $v );
            }
            else {
                $section->{$k} = [$v];
            }
        }
        else {
            $section->{$k} = $v;
        }

        if ( defined($comment) and $comment ne '' ) {
            my $thisComment = $comment;
            $thisComment =~ s/^\s*|\s*$//g;
            $optComments->{"$current.$k"} = $thisComment;
            undef($comment);
            $comment = '';
        }
    }
}

sub modifyConf {
    my ( $self, $filePath, $updateINI, $needBackup ) = @_;

    my $changedMap = $self->{changedMap};

    $self->__modify_config( $filePath, $updateINI, 'file' );

    #处理全新增加的section
    my $topFileContent = $self->getFileContent($filePath);
    $topFileContent = $self->__appendNewSection( $topFileContent, $filePath, $updateINI );
    if ( defined( $changedMap->{$filePath} ) and defined($topFileContent) ) {
        $self->{modified} = 1;
        $self->backup($filePath);
        my $fh = IO::File->new(">$filePath");
        if ( defined($fh) ) {
            print $fh ($topFileContent);
            $fh->close();
        }
        else {
            $self->{hasError} = 1;
            die("ERROR: Can not write to file $filePath, $!\n");
        }
    }
}

sub backup {
    my ( $self, $filePath ) = @_;

    if ( $self->{needBackup} != 1 ) {
        return;
    }

    my $backupMap = $self->{backupMap};

    if ( defined( $backupMap->{$filePath} ) ) {
        return;
    }

    if ( not -e $filePath ) {
        return;
    }

    my $rootDir   = $self->{rootDir};
    my $backupDir = $self->{backupDir};

    if ( not -e $backupDir ) {
        mkdir($backupDir);
    }

    my $relPath = $filePath;
    $relPath =~ s/^$rootDir\///;
    my $backupPath = "$backupDir/$relPath";
    make_path( dirname($backupPath) );
    if ( not copy( "$filePath", "$backupDir/$relPath" ) ) {
        die("ERROR: Backup $filePath to $backupDir/$relPath failed, $!.\n");
    }
    $backupMap->{$filePath} = 1;

    return;
}

sub __modify_config {
    my ( $self, $path, $updateINI, $what ) = @_;

    my $changedMap = $self->{changedMap};
    my $oldINI     = $self->getConfig();

    if ( not defined($what) ) {
        $what = 'file';
    }

    my $content = "";

    # store the names to skip when reading directories
    my %skip;
    my @skip_names = qw(. ..);
    @skip{@skip_names} = (1) x @skip_names;

    if ( $what eq "file" ) {
        if ( not -f $path ) {
            $self->{hasError} = 1;
            die("ERROR: $path is not a file.\n");
        }
        $content = $self->getFileContent($path);
        my $newContent = $self->__modifyINI( $content, $path, $updateINI );
        if ( defined( $changedMap->{$path} ) and defined($newContent) ) {
            $self->{modified} = 1;
            $self->backup($path);
            my $fh = IO::File->new(">$path");
            if ( defined($fh) ) {
                print $fh ($newContent);
                $fh->close();
            }
            else {
                $self->{hasError} = 1;
                die("ERROR: Can not write to file $path, $!\n");
            }
        }
    }
    elsif ( $what eq "dir" ) {
        opendir( my $dirh, $path ) or return "";

        while ( my $file = readdir($dirh) ) {

            # skip invisible files and directories we shouldn't
            # recurse into, like ../ or CVS/
            next if $skip{$file} or index( $file, "." ) == 0;

            my $filepath = catfile( $path, $file );

            if ( -f $filepath ) {
                $self->__modify_config( $filepath, $updateINI, 'file' );
            }
            elsif ( -d $filepath ) {
                $self->__modify_config( $filepath, $updateINI, 'dir' );
            }
        }

        closedir($dirh);
    }
}

sub __modifyINI {
    my ( $self, $content, $filePath, $updateINI ) = @_;

    my $changedMap     = $self->{changedMap};
    my $oldINI         = $self->getConfig();
    my $sectionFileMap = $self->{sectionFileMap};

    my $baseDir = dirname($filePath);
    my $current;
    my $currentSection = {};

    my $optComments     = $updateINI->{optComments};
    my $multipleOptions = $self->{multipleOptions};

    my $newContent = '';
    $content =~ s/^\s*|\s*$//g;
    foreach my $line ( split( /\n/, $content ) ) {
        $line =~ s/^\s*|\s*$//g;
        if ( $line =~ /[;#].*$/ ) {
            $newContent = $newContent . $line . "\n";
            next;
        }
        elsif ( $line eq '' ) {
            $newContent = $newContent . $line . "\n";
            next;
        }

        # handle includes
        if ( $line =~ /^\s*!include(dir)?\s+(.+)\s*$/ ) {
            $newContent = $newContent . $line . "\n";
            my $incDir   = $1;
            my $filePath = $2;
            if ( defined($incDir) ) {
                $self->__modify_config( rel2abs( $filePath, $baseDir ), $updateINI, 'dir' );
            }
            else {
                $self->__modify_config( rel2abs( $filePath, $baseDir ), $updateINI, 'file' );
            }
            next;
        }
        elsif ( $line =~ /^\s*\[(.*)\]\s*$/ ) {
            my $newSection = $1;
            if ( $sectionFileMap->{$newSection} eq $filePath ) {
                $newContent = $self->__appendSectionOpts( $filePath, $newContent, $current, $updateINI );
            }
            $current        = $newSection;
            $newContent     = $newContent . $line . "\n";
            $currentSection = $oldINI->{$current};
            next;
        }

        if ( $line !~ /=/ ) {
            $line = join( '=', $line, 1 );
        }

        my $oldSection = $oldINI->{$current};
        my $updSection = $updateINI->{$current};

        my ( $k, $v ) = split( /\s*=\s*/, $line, 2 );

        my $newV;
        if ( defined($updSection) ) {
            $newV = $updSection->{$k};
        }

        if ( defined($newV) ) {
            my $optComment = $optComments->{"$current.$k"};
            if ( $multipleOptions->{$k} ) {

                #新旧值进行比较
                my $oldV = [];
                if ( defined($oldSection) ) {
                    $oldV = $oldSection->{$k};
                    my @tmp = sort(@$oldV);
                    $oldV = \@tmp;
                }

                my @tmp = sort(@$newV);
                $newV = \@tmp;

                #compare the values
                my $equals = 0;
                if ( scalar(@$oldV) != scalar(@$newV) ) {
                    $equals = 0;
                }
                else {
                    $equals = 1;
                    foreach ( my $i = 0 ; $i < scalar(@$oldV) ; $i++ ) {
                        if ( $$oldV[$i] ne $$newV[$i] ) {
                            $equals = 0;
                            last;
                        }
                    }
                }

                if ( not defined( $self->{multipleOptionsModifed}->{$k} ) ) {
                    $self->{multipleOptionsModifed}->{$k} = 1;
                    if ( defined($optComment) and $optComment ne '' and $newContent !~ /$optComment\n$/is ) {
                        $newContent = $newContent . $optComment . "\n";
                    }

                    foreach my $val (@$newV) {
                        $newContent = $newContent . "$k = $val\n";
                    }
                }

                if ( $equals == 0 ) {
                    $changedMap->{$filePath} = 1;
                    print( "Changed option: $k = [" . join( ',', @$newV ) . "] in section:$current file:$filePath.\n" );
                    $oldSection->{$k} = $newV;
                }
            }
            else {
                if ( $newV ne $v ) {
                    $changedMap->{$filePath} = 1;
                    if ( defined($optComment) and $optComment ne '' and $newContent !~ /$optComment\n$/is ) {
                        $newContent = $newContent . $optComment . "\n";
                    }
                    $newContent = $newContent . "$k = $newV\n";
                    print("Changed option: $k = $newV in section:$current file:$filePath.\n");
                    $oldSection->{$k} = $newV;
                }
                else {
                    $newContent = $newContent . $line . "\n";
                }
            }
        }
        else {
            $newContent = $newContent . $line . "\n";
        }
    }
    $newContent = $self->__appendSectionOpts( $filePath, $newContent, $current, $updateINI );

    return $newContent;
}

sub __appendSectionOpts {
    my ( $self, $filePath, $newContent, $section, $updateINI ) = @_;

    my $changedMap  = $self->{changedMap};
    my $oldINI      = $self->getConfig();
    my $oldSection  = $oldINI->{$section};
    my $updSection  = $updateINI->{$section};
    my $optComments = $updateINI->{optComments};

    while ( my ( $updK, $updV ) = each(%$updSection) ) {
        if ( not defined( $oldSection->{$updK} ) ) {
            $changedMap->{$filePath} = 1;
            my $optComment = $optComments->{"$section.$updK"};
            if ( defined($optComment) and $optComment ne '' and $newContent !~ /$optComment\n$/is ) {
                $newContent = $newContent . $optComment . "\n";
            }

            if ( ref($updV) eq 'ARRAY' ) {
                foreach my $val (@$updV) {
                    $newContent = $newContent . "$updK = $val\n";
                }
                print( "Append option: $updK = [" . join( ',', @$updV ) . "] in section:$section file:$filePath.\n" );
            }
            else {
                $newContent = $newContent . "$updK = $updV\n";
                print("Append option: $updK = $updV in section:$section file:$filePath.\n");
            }

            $oldSection->{$updK} = $updV;

        }
    }

    return $newContent;
}

sub __appendNewSection {
    my ( $self, $content, $filePath, $updateINI ) = @_;

    my $changedMap = $self->{changedMap};

    my $oldINI          = $self->getConfig();
    my $sectionComments = $updateINI->{sectionComments};

    while ( my ( $updSectionName, $updSection ) = each(%$updateINI) ) {
        my $oldSection = $oldINI->{$updSectionName};
        if ( not defined($oldSection) ) {
            $changedMap->{$filePath} = 1;
            my $sectionComment = $sectionComments->{$updSectionName};
            if ( defined($sectionComment) and $sectionComment ne '' and $content !~ /$sectionComment\n$/is ) {
                $content = $content . $sectionComment . "\n";
            }
            $content = $content . "[$updSectionName]\n";
            print("Append section: [$updSectionName] file:$filePath.\n");
            $content = $self->__appendSectionOpts( $filePath, $content, $updSectionName, $updateINI );
        }
    }
    return $content;
}

1;
