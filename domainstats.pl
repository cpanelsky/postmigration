#!/usr/bin/perl
# cpanel				          Copyright(c) 2016 cPanel, Inc.
#                                                           All rights Reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
package DomainStatus;
use File::Spec;
use strict;
use warnings;
$Term::ANSIColor::AUTORESET = 1;
use Term::ANSIColor qw(:constants);
use threads;
use threads::shared;
use lib "/usr/local/cpanel/3rdparty/perl/514/lib64/perl5/cpanel_lib/";
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
our $file_name = "/etc/userdatadomains";
our @links     = read_file( $file_name );
our $link_ref  = \@links;
our $VERSION   = 0.02;
our $REMOTEDNSHOST;

#this silences stderr
sub supressERR($) {
    open my $saveout, ">&STDERR";
    open STDERR, '>', File::Spec->devnull();
    my $func = $_[0];
    $func->();
    open STDERR, ">&", $saveout;
}

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
    print "\n Options:
     -help   -> This!

Accepts -local ( -ipdns -local )
     -ipdns  -> Check http status, IP's, DNS IP's
     -json   -> Print http/DNS data in JSON
     -all    -> DNS, Mail, http Status codes


Single option:
     -hosts  -> Show suggested /etc/hosts file
     -mail   -> Print http
     -tterr  -> Find pkgacct transfer errors\n\n";
} elsif ( $transferror ) {

    &transfer_errors();

} elsif ( $jsons ) {
    &supressERR( \&json_from_web_requests );
} elsif ( $mail ) {
    print "\n\n";
    &get_mail_accounts();
} elsif ( $ipdns ) {
    print "\n\n";
    &supressERR( \&get_human_webrequest );
} elsif ( $all ) {
    print "\n\n";
    &supressERR( \&get_human_webrequest );
    &gen_hosts_file();
    &get_mail_accounts();
} elsif ( $hosts ) {
    print "\n";
    &gen_hosts_file();
} else {
    print "\n\thWhhut?! try -help ;p\n\n";
}

#this calls the subs with params in threads
sub get_human_webrequest {
    $SIG{'INT'} = sub { print "\nCaught CTRL+C!.."; print RESET " Ending..\n"; kill HUP => -$$; };
    print "\n\t::Checking HTTP response codes and DNS A records(be patient..)::\n\n";
    foreach my $uDomain ( @links ) {
        if ( $uDomain =~ /(.*):[\s]/ ) {
            our $resource = $1;
            my $thread1 = threads->create( \&get_http_status, "$resource" );
            my $thread2 = threads->create( \&get_dns_data,    "$resource" );
            $thread1->join();
            $thread2->join();
        } else {
            print YELLOW
                " Possible bad Domain data enountered, manually check /etc/userdatadomains file after finished.\n";
        }
    }
}

#this is a subroutine to check the http status code for domains
sub get_http_status {
    $SIG{'INT'} = sub { print "\nCaught CTRL+C!.."; print RESET " Ending..\n"; kill HUP => -$$; };

    #we use lwp/time/ansi for output/commands
    require LWP::UserAgent;
    require Time::HiRes;
    $Term::ANSIColor::AUTORESET = 1;
    use Term::ANSIColor qw(:constants);

    #our URL should come in as an argument to the subroutine
    my $url = "@_";

    #we have a basic browser agent and a low timeout for now, here's the request for the URL
    my $ua = LWP::UserAgent->new( agent => 'Mozilla/5.0', timeout => '1' );
    my $req = HTTP::Request->new( GET => "http://$url" );
    my $res = $ua->request( $req );

    #we can parse this for goodies/errors
    my $body = $res->decoded_content;

    #this is the status code
    my $code = $res->code();

    #we can easily check the headers to determine if we had a good request as below
    my $head = $res->headers()->as_string;
    print $res->header( "content-type\r\n\r\n" );

    #blue seems like a good color for requests that process(for now)
    my $bcode = ( BOLD BLUE $code );
    if ( $head =~ /Client-Peer:[\s](.*):([0-9].*)/ ) {
        my $head2 = "$1:$2";

        #here's some terrible formatting, needs improvement
        printf( " %-30s PeerIP=%-15s Status=%s\r\n", $url, $head2, $bcode );
    } else {

        #if we didn't see a normal header, let's print the code red with yellow warnings
        my $rcode = ( BOLD YELLOW $code );
        my $error = BOLD RED " ERROR:\t!!!HTTP Connect Failed : $url : $rcode!!!\n";
        print "$error";
    }
}

#this is a subroutine for DNS checks
sub get_dns_data {
    $SIG{'INT'} = sub { print "\nCaught CTRL+C!.."; print RESET " Ending..\n"; exit; die; kill HUP => -$$; };

    use IPC::System::Simple qw(system capture $EXITVAL);

    #colors again
    $Term::ANSIColor::AUTORESET = 1;
    use Term::ANSIColor qw(:constants);

    #here we can get the domain as a parameter and make some dig arguments
    my $REMOTEDNSH  = $REMOTEDNSHOST;
    my $domain      = "@_";
    my $cmd         = "dig";
    my @local_args  = ( "\@localhost", "$domain", "A", "+short", "+tries=1" );
    my @google_args = ( "\@$REMOTEDNSH", "$domain", "A", "+short", "+tries=1" );

    #so, this uses the lib found to capture stdout of the called system command
    #first we populate it into an array
    my @googleDNSA = capture( $cmd, @google_args );

    #then we reference out the first element because we want a singular return
    #then we do the same for localhost requests
    my $googleDNS     = $googleDNSA[0];
    my @localhostDNSA = capture( $cmd, @local_args );
    my $localhostDNS  = $localhostDNSA[0];
    chomp( $googleDNS, $localhostDNS );

    #if the request is defined but doesn't match:
    if ( ( $localhostDNS ) && ( $localhostDNS ne $googleDNS ) ) {
        my $IPM1      = BOLD YELLOW " WARN: Local IP:";
        my $IPM2      = BOLD YELLOW " doesn't match remote DNS ";
        my $RlocalIP  = ( BOLD RED $localhostDNS );
        my $RgoogleIP = ( BOLD RED $googleDNS );
        chomp( $RlocalIP, $RgoogleIP );
        print "$IPM1" . "$RlocalIP" . "$IPM2" . "$RgoogleIP\n";
    } else {

        #if it's defined and matches, we do a normal thing:
        if ( ( $localhostDNS ) && ( "$localhostDNS" eq "$googleDNS" ) ) {
            print "$domain :: DNS IP: $googleDNS\n";
        } else {

            #else print yellow warning if nothing was returned
            print YELLOW "WARN: Something happened to DNS requests for $domain, is DNS set?\n";
        }
    }
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

sub json_from_web_requests {
    require LWP::UserAgent;
    print "\n";
    $SIG{'INT'} = sub { print "\nCaught CTRL+C!.."; print RESET " Ending..\n"; kill HUP => -$$; };
    my $head4;
    my $REMOTEDNSH = $REMOTEDNSHOST;
    foreach my $jDomain ( @{$link_ref} ) {
        if ( $jDomain =~ /(.*):[\s]/ ) {
            my $url2          = $1;
            my $ua            = LWP::UserAgent->new( agent => 'Mozilla/5.0', timeout => '1' );
            my $req           = HTTP::Request->new( GET => "http://$url2" );
            my $reqIP         = "NULL";
            my $res2          = $ua->request( $req );
            my $body2         = $res2->decoded_content;
            my $code2         = $res2->code();
            my $head3         = $res2->headers()->as_string;
            my $localhostDNS2 = "NULL";
            print $res2->header( "content-type\r\n\r\n" );

            if ( $head3 =~ /Client-Peer:[\s](.*):([0-9].*)/ ) {
                $reqIP = "$1:$2";
            } else {
                $reqIP = "NULL";
                $code2 = "NULL";
            }
            my ( $domain, $status ) = ( $url2, $code2 );
            my $cmd2           = "dig";
            my @local_args2    = ( "\@localhost", "$domain", "A", "+short", "+tries=1" );
            my @google_args2   = ( "\@$REMOTEDNSH", "$domain", "A", "+short", "+tries=1" );
            my @googleDNSA2    = capture( $cmd2, @google_args2 );
            my $googleDNS2     = $googleDNSA2[0];
            my @localhostDNSA2 = capture( $cmd2, @local_args2 );
            $localhostDNS2 = $localhostDNSA2[0];
            chomp( $googleDNS2, $localhostDNS2 );

            sub TO_JSON { return { %{ shift() } }; }

            use JSON;
            my $JSON = JSON->new->utf8;
            $JSON->convert_blessed( 1 );
            my $e = jsons DomainStatus( "$domain", "$reqIP", "$status", "$localhostDNS2", "$googleDNS2" );
            my $json = $JSON->encode( $e );
            print "$json\n";
        }
    }
    print "\n";
}

sub jsons {

    my $class = shift;
    my $self = { Domain     => shift,
                 IP         => shift,
                 httpStatus => shift,
                 LocalDNS   => shift,
                 GoogleDNS  => shift };
    bless $self, $class;
    return $self;
}

sub transfer_errors {
    use Path::Class;

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

    my $log_file = $_[0];

    #    my @timestamp = stat($log_fiile);
    my $last_mod_time = ( stat( $log_file ) )[9];
    my $humantime     = localtime( $last_mod_time );
    print "\n$log_file \n\t ->  dated  -> $humantime -> errors: \n\n";
    open( INPUTFILE, "<$log_file" ) or die "$!";
    my $previous_line;
    print "Extracting errors\n";
    while ( <INPUTFILE> ) {

        if ( $_ =~ m/ was not successful, or the requested account, (.*) was not found on the server: (.*)”\.","/ )
        {
            my $account = $1;
            my $server  = $2;
            $account =~ s/\W//g;
            $server =~ s/\“|\"//g;
            printf( "Account: %-17s encountered pkgacct/cpmove errors from $server\n", $account );
        }
    }
}

1;
