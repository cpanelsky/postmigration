#!/usr/bin/perl
# cpanel                                          Copyright(c) 2016 cPanel, Inc.
#                                                           All rights Reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
package DomainStatus;
use File::Spec;
use strict;
use warnings;
$Term::ANSIColor::AUTORESET = 1;
use Term::ANSIColor qw(:constants);
use lib "/usr/local/cpanel/3rdparty/perl/514/lib64/perl5/cpanel_lib/";
use JSON;
use IPC::System::Simple qw(system capture $EXITVAL);
use File::Slurp qw(read_file);
use Getopt::Long;

# setup my defaults
my $mail        = 0;
my $ipdns       = 0;
my $all         = 0;
my $hosts       = 0;
my $help        = 0;
my $jsons       = 0;
my $localcheck  = 0;
my $transferror = 0;
my $humanrun    = "1";
our %domains;
our $file_name = "/etc/userdatadomains";
our @links     = read_file( $file_name );
our $link_ref  = \@links;
our $VERSION   = 0.2;
our $REMOTEDNSHOST;

GetOptions( 'mail'  => \$mail,
            'ipdns' => \$ipdns,
            'all'   => \$all,
            'hosts' => \$hosts,
            'json'  => \$jsons,
            'local' => \$localcheck,
            'tterr' => \$transferror,
            'help!' => \$help );

if ( $localcheck ) {
    $REMOTEDNSHOST = "localhost";
} else {
    $REMOTEDNSHOST = "8.8.8.8";
}
if ( $help ) {
    &helpsub();
} elsif ( $jsons ) {
    $humanrun = "0";
    &get_webrequest;
} elsif ( $transferror ) {
    &transfer_errors();
} elsif ( $mail ) {
    &get_mail_accounts();
} elsif ( $ipdns ) {
    &get_webrequest;
} elsif ( $all ) {
    &get_webrequest;
    &gen_hosts_file();
    &get_mail_accounts();
} elsif ( $hosts ) {
    &gen_hosts_file();
} else {
    &helpsub();
}

sub helpsub {
    print "\n Options:
     -help   -> This!

Accepts -local ( -ipdns -local )
     -ipdns  -> Check http status, IP's, DNS IP's
     -json   -> Print http/DNS data in JSON
     -all    -> DNS, Mail, http Status codes


Single option:
     -hosts  -> Show suggested /etc/hosts file
     -mail   -> Find mail accounts
     -tterr  -> Find pkgacct transfer errors\n\n";
}
1;

sub http_web_request {
    require LWP::UserAgent;
    $SIG{'INT'} = sub { print "\nCaught CTRL+C!.."; print RESET " Ending..\n"; kill HUP => -$$; };
    my $url = $_[0];
    if ( $url ) {
        my $ua = LWP::UserAgent->new( agent => 'Mozilla/5.0', timeout => '1' );
        my $req   = HTTP::Request->new( GET => "http://$url" );
        my $reqIP = "NULL";
        my $code  = "NULL";
        my $res   = $ua->request( $req );
        my $body  = $res->decoded_content;
        $code = $res->code();
        my $headervar = $res->headers()->as_string;
        print $res->header( "content-type\r\n\r\n" );

        if ( $headervar =~ /Client-Peer:[\s](.*):([0-9].*)/ ) {
            $reqIP = "$1:$2";
        } else {
            $reqIP = "NULL";
            chomp( $reqIP );
        }
        if ( not defined $code ) {
            $code = "NULL";
        }

        $domains{'Domain'} = $url;
        $domains{'Status'} = $code;
        $domains{'PeerIP'} = $reqIP;

    }
}

sub dns_web_request {
    $SIG{'INT'} = sub { print "\nCaught CTRL+C!.."; print RESET " Ending..\n"; kill HUP => -$$; };
    my $REMOTEDNSH = "8.8.8.8";
    my $url        = $_[0];
    if ( $url ) {
        my $domain       = $url;
        my $googleDNS    = "NULL";
        my $localhostDNS = "NULL";
        my $cmd          = "dig";
        my @local_args   = ( "\@localhost", "$domain", "A", "+short", "+tries=1" );
        my @google_args  = ( "\@$REMOTEDNSH", "$domain", "A", "+short", "+tries=1" );
        my @googleDNSA   = capture( $cmd, @google_args );
        $googleDNS = $googleDNSA[0];
        my @localhostDNSA = capture( $cmd, @local_args );
        $localhostDNS = $localhostDNSA[0];

        if ( not defined $googleDNS ) {
            $googleDNS = "NULL";
        }
        if ( not defined $localhostDNS ) {
            $localhostDNS = "NULL";
        }
        chomp( $domain, $googleDNS, $localhostDNS );

        $domains{'Domain'}    = $domain;
        $domains{'RemoteDNS'} = $googleDNS;
        $domains{'LocalDNS'}  = $localhostDNS;
        if ( $humanrun eq "1" ) {
          print "\n\t::Checking HTTP response codes and DNS A records(be patient..)::\n\n";
            foreach my $key ( keys %domains ) {
                my $value = $domains{$key};
                if ( $key eq "LocalDNS" ) {
                    print "\n";
                }
                if ( $key eq "Domain" ) {
                    printf( " %s %-30s", $key, $value );
                } else {
                    print "$key:$value ";
                }
            }
        } elsif ( $humanrun eq "0" ) {
            my $jsondata = encode_json \%domains;
            print "\n$jsondata";
        }
    }
}

sub get_webrequest {
    $SIG{'INT'} = sub { print "\nCaught CTRL+C!.."; print RESET " Ending..\n"; kill HUP => -$$; };
    foreach my $uDomain ( @links ) {
        if ( $uDomain =~ /(.*):[\s]/ ) {
            our $resource = $1;
            &http_web_request( "$resource" );
            sleep( .5 );
            &dns_web_request( "$resource" );
        }
    }
    print "\n";
}

sub get_mail_accounts {
    print "\n\n\t::Mail accounts found::\n\n";
    use File::Slurp qw(read_file);

    #read in users from passwd
    my @passwd = read_file( "/etc/passwd" );
    my $dir    = '/var/cpanel/users';
    my %user_list;
    opendir( DIR, $dir ) or die $!;
    while ( my $file = readdir( DIR ) ) {
        next if ( $file =~ m/^\./ );
        foreach my $line ( @passwd ) {

            #if we look like a system and cpanel user?
            if ( $line =~ /^$file:[^:]*:[^:]*:[^:]*:[^:]*:([a-z0-9_\/]+):.*/ ) {
                $user_list{$file} = $1;
            }
        }
    }
    closedir( DIR );

    #for the users found, if we aren't root look for an etc dir
    foreach my $user ( keys %user_list ) {
        if ( $user ne "root" ) {
            opendir( ETC, "$user_list{$user}/etc" ) || warn $! . "$user_list{$user}/etc";
            my $path = $user_list{$user};

            #for the domains found in the users etc dir
            while ( my $udomain = readdir( ETC ) ) {
                next if $udomain =~ /^\./;  # skip . and .. dirs
                                            #see if we are a valid etc domain and if so, look for mail users and print
                if ( -d "$path/etc/$udomain/" ) {
                    open( PASSWD, "$path/etc/$udomain/passwd" ) || die $! . "/home/$user/etc/$udomain/passwd";
                    while ( my $PWLINE = <PASSWD> ) {
                        $PWLINE =~ s/:.*//;    # only show line data before first colon (username only)
                        chomp( $user, $udomain, $PWLINE );
                        my $PWLINED = "$PWLINE\@$udomain";
                        chomp( $PWLINED );
                        printf( "User=%-10s Domain=%-35s Email=%s\n", $user, $udomain, $PWLINED );
                    }
                    close( PASSWD );
                }
            }
        }
        close( ETC );
    }
    print "\n";
}

sub transfer_errors {
    use Path::Class;
    print "\n";
    my $transfer_logdir = "/var/cpanel/transfer_sessions";
    my @files;

    dir( "$transfer_logdir" )->recurse(
        callback => sub {
            my $file = shift;
            if ( $file =~ /master.log/ ) {
                push @files, $file->absolute->stringify;
            }
        } );

    foreach my $filename ( @files ) {
        &find_pkgacct_errors( "$filename" );
    }
}

sub find_pkgacct_errors {
    my %seen;
    my @error_list;
    my $log_file      = $_[0];
    my $last_mod_time = ( stat( $log_file ) )[9];
    my $humantime     = localtime( $last_mod_time );
    print "\n$log_file \n\t ->  dated  -> $humantime -> errors: \n\n";
    open( INPUTFILE, "<$log_file" ) or die "$!";

    while ( <INPUTFILE> ) {
        if ( $_ =~ m/ was not successful, or the requested account, (.*) was not found on the server: (.*)”\.","/ )
        {
            my $account = $1;
            my $server  = $2;
            $account =~ s/\W//g;
            $server =~ s/\“|\"//g;
            push @error_list, "$account $server";
        }
    }
    my @unique_error = grep { !$seen{$_}++ } @error_list,;
    foreach ( @unique_error ) {
        if ( $_ =~ /(.*)[\s+](.*)/ ) {
            printf( "Account: %-16s encountered pkgacct/cpmove errors from $2\n", $1 );
        }
    }
    print "\n";
}

sub gen_hosts_file {
    print "\n\n\t::Hosts File::\n\n";
    foreach my $host_domain ( @{$link_ref} ) {
        if ( $host_domain =~ /==/ ) {
            $host_domain =~ s/:[\s]/==/g;
            my ( $new_domain, $user_name, $user_group, $domain_status, $primary_domain, $home_dir, $IP_port ) =
                split /==/,
                $host_domain, 9;
            my ( $IP ) = split /:/, $IP_port, 2;
            print "$IP\t\t$new_domain\twww.$new_domain\n";
        } else {
            next;
        }
    }
    print "\n";
}

