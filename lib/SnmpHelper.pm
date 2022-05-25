#!/usr/bin/perl
use strict;

package SnmpHelper;
use Net::SNMP qw(:snmp);
use JSON;

my $PORT_STATUS_MAP = {
    1 => 'up',
    2 => 'down',
    3 => 'testing'
};

my $PORT_TYPES_MAP = {
    1  => 'other(1)',
    2  => 'regular1822(2)',
    3  => 'hdh1822(3)',
    4  => 'ddn-x25(4)',
    5  => 'rfc877-x25(5)',
    6  => 'ethernet-csmacd(6)',
    7  => 'iso88023-csmacd(7)',
    8  => 'iso88024-tokenBus(8)',
    9  => 'iso88025-tokenRing(9)',
    10 => 'iso88026-man(10)',
    11 => 'starLan(11)',
    12 => 'proteon-10Mbit(12)',
    13 => 'proteon-80Mbit(13)',
    14 => 'hyperchannel(14)',
    15 => 'fddi(15)',
    16 => 'lapb(16)',
    17 => 'sdlc(17)',
    18 => 'ds1(18)',
    19 => 'e1(19)',
    20 => 'basicISDN(20)',
    21 => 'primaryISDN(21)',
    22 => 'propPointToPointSerial(22)',
    23 => 'ppp(23)',
    24 => 'softwareLoopback(24)',
    25 => 'eon(25)',
    26 => 'ethernet-3Mbit(26)',
    27 => 'nsip(27)',
    28 => 'slip(28)',
    29 => 'ultra(29)',
    30 => 'ds3(30)',
    31 => 'sip(31)',
    32 => 'frame-relay(32)'
};

sub new {
    my ($class) = @_;
    my $self = {};
    bless( $self, $class );
    return $self;
}

sub _errCheck {
    my ( $self, $snmp, $queryResult, $oid, $name ) = @_;
    my $hasError = 0;
    if ( not defined($queryResult) ) {
        $hasError = 1;
        my $error = $snmp->error();
        if ( $error =~ /^No response/i ) {
            print("ERROR: $error, snmp failed, exit.\n");
            exit(-1);
        }
        else {
            print("WARN: $error, $name oid:$oid\n");
        }
    }

    return $hasError;
}

sub hex2mac {
    my ( $self, $hexMac ) = @_;

    #如果字串中含有0字节（数值为0），否则不是正常的MAC地址hex字符串
    if ( $hexMac !~ /\x00/ ) {
        $hexMac = substr( $hexMac, 2 );
        $hexMac =~ s/..\K(?=.)/:/sg;
    }
    else {
        $hexMac = '';
    }

    return $hexMac;
}

sub hex2ip {
    my ( $self, $hexIp ) = @_;

    my $ip;

    #每两个字符作为一个数组元素
    my @array = ( $hexIp =~ m/../g );
    if ( $#array >= 3 ) {
        if ( lc( $array[0] ) eq '0x' ) {

            #去掉开头的0x
            shift(@array);
        }

        if ( $#array == 3 ) {

            #4个字节，IPV4
            @array = map { hex($_) } @array;
            $ip = join( '.', @array );
        }
        else {
            #IPV6
            $ip = join( ':', @array );
        }
    }
    return $ip;
}

#snmp获取到的端口状态是整数，转换为可读性的字串
sub getPortStatus {
    my ( $self, $portStatusCode ) = @_;
    return $PORT_STATUS_MAP->{$portStatusCode};
}

#snmp获取到的端口类型是整数，转换为可读性的字串
sub getPortType {
    my ( $self, $portTypeCode ) = @_;
    return $PORT_TYPES_MAP->{$portTypeCode};
}

#根据$oidDefMap定义获取SNMP 标量（非列表值的简单值），一次性可以获取多个
#一个属性可以列出多个OID，会自动按照顺序尝试发出snmp请求，直到查询到值为止，适用于一个属性在多个型号的OID不一致的情况
# {
#     DEV_NAME    => '1.3.6.1.2.1.1.5.0',               #sysName
#     UPTIME      => '1.3.6.1.2.1.1.3.0',               #sysUpTime
#     VENDOR      => '1.3.6.1.2.1.1.4.0',               #sysContact
#     MODEL       => '1.3.6.1.2.1.1.1.0',               #sysDescr
#     IOS_INFO    => '1.3.6.1.2.1.1.1.0',               #sysDescr
#     SN          => ['1.3.6.1.2.1.47.1.1.1.1.11.1'],
#     PORTS_COUNT => '1.3.6.1.2.1.2.1.0'                #ifNumber
# }
sub getScalar {
    my ( $self, $snmp, $oidDefMap ) = @_;

    my $value;

    my @scalarOids = ();
    foreach my $attr ( keys(%$oidDefMap) ) {
        my $val = $oidDefMap->{$attr};

        #支持单值oid可以定义多个oid进行尝试查询
        if ( ref($val) eq 'ARRAY' ) {
            push( @scalarOids, @$val );
        }
        else {
            push( @scalarOids, $val );
        }
    }

    my $result = $snmp->get_request( -varbindlist => \@scalarOids, );

    my $data = {};
    foreach my $attr ( keys(%$oidDefMap) ) {
        my $oidDesc;
        my $oidVal;
        my $val = $oidDefMap->{$attr};
        if ( ref($val) ne 'ARRAY' ) {
            $oidDesc = $val;
            my $oid    = $val;
            my $tmpVal = $result->{$oid};
            if (    defined($tmpVal)
                and $tmpVal ne 'noSuchObject'
                and $tmpVal ne 'noSuchInstance'
                and $tmpVal ne 'endOfMibView' )
            {
                $oidVal = $tmpVal;
            }
        }
        else {
            $oidDesc = join( ', ', @$val );

            #如果某个属性定义的是多个oid，则按照顺序获取值
            foreach my $oid (@$val) {
                my $tmpVal = $result->{$oid};
                if (    defined($tmpVal)
                    and $tmpVal ne 'noSuchObject'
                    and $tmpVal ne 'noSuchInstance'
                    and $tmpVal ne 'endOfMibView' )
                {
                    $oidVal = $tmpVal;
                    last;
                }
            }
        }

        if ( defined($oidVal) ) {
            $data->{$attr} = $oidVal;
        }
        else {
            $data->{$attr} = undef;
            print("WARN: Can not find value for attr $attr oid:$oidDesc\n");
        }
    }

    return $data;
}

#根据$oidDefMap定义的Table的列属性获取一个Table的多个列
# {
#     INDEX        => '1.3.6.1.2.1.2.2.1.1',       #ifIndex
#     NAME         => '1.3.6.1.2.1.2.2.1.2',       #ifDescr
#     TYPE         => '1.3.6.1.2.1.2.2.1.3',       #ifType
#     MAC          => '1.3.6.1.2.1.2.2.1.6',       #ifPhysAddress
#     ADMIN_STATUS => '1.3.6.1.2.1.2.2.1.7',       #ifAdminStatus
#     OPER_STATUS  => '1.3.6.1.2.1.2.2.1.8',       #ifOperStatus
#     SPEED        => '1.3.6.1.2.1.2.2.1.5',       #ifSpeed
#     MTU          => '1.3.6.1.2.1.2.2.1.4',       #ifMTU
# }
#注意：列表字段snmp获取的信息中，oid属性最后一位数字是index number，所以必须要求查询的table列属性的OID必须是使用同一个索引号
sub getTable {
    my ( $self, $snmp, $oidDefMap ) = @_;

    my $data   = {};
    my $oidMap = {};
    foreach my $attrName ( keys(%$oidDefMap) ) {
        my $idx2AttrMap = {};    #OID最后一截数字是table字段的索引号
        my $idx2OIDMap  = {};

        my $oidEntrys = $oidDefMap->{$attrName};
        while ( my ( $name, $oid ) = each(%$oidEntrys) ) {
            my $table = $snmp->get_table( -baseoid => $oid );
            $self->_errCheck( $snmp, $table, $oid, "$attrName.$name" );

            while ( my ( $realOid, $val ) = each(%$table) ) {
                $realOid =~ /^\.?\Q$oid\E\.(.*)$/;
                my $idx       = $1;
                my $entryInfo = $idx2AttrMap->{$idx};
                my $oidInfo   = $idx2OIDMap->{$idx};
                if ( not defined($entryInfo) ) {
                    $entryInfo = { INDEX => $idx };
                    $idx2AttrMap->{$idx} = $entryInfo;

                    $oidInfo = {};
                    $idx2OIDMap->{$idx} = $oidInfo;
                }
                $entryInfo->{$name} = $val;
                $oidInfo->{$name}   = $realOid;
            }
        }

        my @attrTable = values(%$idx2AttrMap);
        $data->{$attrName}   = \@attrTable;
        $oidMap->{$attrName} = $idx2OIDMap;
    }

    return ( $oidMap, $data );
}

#根据$oidDefMap定义的Table的列属性获取一个Table的多个列
#跟通用的getTable方法差异的地方是，多列的值的对应不是通过index number来对应，二是通过oid的排序的序号来对应
#适用于跨OID列表查询（本不属于同一个table），这个时候index无法对应上
sub getTableByOrder {
    my ( $self, $snmp, $oidDefMap ) = @_;

    my $data = {};
    my $oids = {};
    foreach my $attrName ( keys(%$oidDefMap) ) {
        my @attrTable = ();    #每个属性会生成一个table
        my @oidTable  = ();

        my $oidEntrys = $oidDefMap->{$attrName};
        while ( my ( $name, $oid ) = each(%$oidEntrys) ) {
            my $table = $snmp->get_table( -baseoid => $oid );
            $self->_errCheck( $snmp, $table, $oid, "$attrName.$name" );

            my @sortedOids = oid_lex_sort( keys(%$table) );
            for ( my $i = 0 ; $i < scalar(@sortedOids) ; $i++ ) {
                my $sortedOid = $sortedOids[$i];

                my $oidInfo = $oidTable[$i];
                if ( not defined($oidInfo) ) {
                    $oidInfo = {};
                    $oidTable[$i] = $oidInfo;
                }
                $oidInfo->{$name} = $sortedOid;

                my $entryInfo = $attrTable[$i];
                if ( not defined($entryInfo) ) {
                    $entryInfo = {};
                    $attrTable[$i] = $entryInfo;
                }
                $entryInfo->{$name} = $table->{$sortedOid};
            }
        }

        $data->{$attrName} = \@attrTable;
        $oids->{$attrName} = \@oidTable;
    }

    return ( $oids, $data );
}

1;

