#!/usr/bin/perl
# cpanel                                          Copyright(c) 2016 cPanel, Inc.
#                                                           All rights Reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
package PostMigration;
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

# setup defaults
my $mail        = 0;
my $ipdns       = 0;
my $all         = 0;
my $hosts       = 0;
my $help        = 0;
my $jsons       = 0;
my $localcheck  = 0;
my $transferror = 0;
my $humanrun    = "1";
my %domains;
my $file_name = "/etc/userdatadomains";
my @links     = read_file($file_name);
my $link_ref  = \@links;
my $VERSION   = 0.2;
my $dns_toggle;

GetOptions(
    'mail'  => \$mail,
    'ipdns' => \$ipdns,
    'all'   => \$all,
    'hosts' => \$hosts,
    'json'  => \$jsons,
    'local' => \$localcheck,
    'tterr' => \$transferror,
    'help!' => \$help
);

if ($localcheck) { # set these if we havent changed dns
    $dns_toggle = "localhost"; 
}
else {       # otherwise use google for external checks
    $dns_toggle = "8.8.8.8";
}
if ($help) {
    &helpsub();
}
elsif ($jsons) {
    $humanrun = "0";
    &get_webrequest;
}
elsif ($transferror) {
    &transfer_errors();
}
elsif ($mail) {
    &get_mail_accounts();
}
elsif ($ipdns) {
    &get_webrequest;
}
elsif ($all) {
    &get_webrequest;
    &gen_hosts_file();
    &get_mail_accounts();
}
elsif ($hosts) {
    &gen_hosts_file();
}
else {
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

sub http_web_request {
    require LWP::UserAgent;
    #capture ctrl+c 
    $SIG{'INT'} = sub { print "\nCaught CTRL+C!.."; print RESET " Ending..\n"; kill HUP => -$$; };
    #get the url from the argument
    my $url = $_[0];
    if ($url) {
        #build our lwp object
        my $ua = LWP::UserAgent->new( agent => 'Mozilla/5.0', timeout => '1' );
        my $req   = HTTP::Request->new( GET => "http://$url" );
        my $reqIP = "NULL";
        my $code  = "NULL";
        my $res   = $ua->request($req);
        my $body  = $res->decoded_content;
        $code = $res->code();
        #get the headers and parse if valid
        my $headervar = $res->headers()->as_string;
        print $res->header("content-type\r\n\r\n");
        if ( $headervar =~ /Client-Peer:[\s](.*):([0-9].*)/ ) {
            $reqIP = "$1";
        } else {
            $reqIP = "NULL_IP";
            chomp($reqIP);
        } 
        if ( not defined $code ) {
            $code = "NULL_CODE";
        }
        #populate our hash
        $domains{'Domain'} = $url;
        $domains{'Status'} = $code;
        $domains{'PeerIP'} = $reqIP;

    }
}

sub dns_web_request {
    #capture ctrl+c
    $SIG{'INT'} = sub { print "\nCaught CTRL+C!.."; print RESET " Ending..\n"; kill HUP => -$$; };
    my $url = $_[0];
    if ($url) {
        my $domain        = $url;
        my $google_dns    = "NULL_IP";
        my $localhost_dns = "NULL_IP";
        my $cmd           = "dig";
        my @local_args    = ( "\@localhost", "$domain", "A", "+short", "+tries=1" );
        my @google_args   = ( "\@$dns_toggle", "$domain", "A", "+short", "+tries=1" );
        my @google_dnsa   = capture( $cmd, @google_args );
        $google_dns = $google_dnsa[0];
        my @localhost_dnsa = capture( $cmd, @local_args );
        $localhost_dns = $localhost_dnsa[0];

        if ( not defined $google_dns ) {
            $google_dns = "NULL_IP";
        }
        if ( not defined $localhost_dns ) {
            $localhost_dns = "NULL_IP";
        }
        chomp( $domain, $google_dns, $localhost_dns );
        #populate our hash with dns data
        $domains{'Domain'}    = $domain;
        $domains{'RemoteDNS'} = $google_dns;
        $domains{'LocalDNS'}  = $localhost_dns;
        #determine if we want json or human output
        if ( $humanrun eq "1" ) {
            foreach my $key ( keys %domains ) {
                my $value = $domains{$key};

                if ( $key eq "LocalDNS" ) {
                    print "\n";
                }
                if ( $key eq "Domain" ) {
                    printf( "%s: %-30s\t", $key, $value );
                }
                else {
                    printf( "%s:%s\t", $key, $value );
                }
            }
        }
        elsif ( $humanrun eq "0" ) {
            my $jsondata = encode_json \%domains;
            print "$jsondata\n";
        }
    }

}

sub get_webrequest {
    #capture ctrl +c
    $SIG{'INT'} = sub { print "\nCaught CTRL+C!.."; print RESET " Ending..\n"; kill HUP => -$$; };
    #for the domains in the array, perform the requests
    foreach my $uDomain (@links) {
        if ( $uDomain =~ /(.*):[\s]/ ) {
            our $resource = $1;
            &http_web_request("$resource");
            sleep(.2);
            &dns_web_request("$resource");
        }
    }
    print "\n";
}

sub transfer_errors {
    use Path::Class;
    print "\n";
    my $transfer_logdir = "/var/cpanel/transfer_sessions";
    my @files;
    #get the transfer files and push them to an array
    dir("$transfer_logdir")->recurse(
        callback => sub {
            my $file = shift;
            if ( $file =~ /master.log/ ) {
                push @files, $file->absolute->stringify;
            }
        }
    );
    #pass each file in array to sub to find errors
    foreach my $filename (@files) {
        &find_pkgacct_errors("$filename");
    }
}

sub find_pkgacct_errors {
    my %seen; # uniques hash
    my @error_list;
    my $log_file      = $_[0];
    my $last_mod_time = ( stat($log_file) )[9];
    my $humantime     = localtime($last_mod_time);
    my $INPUTFILE;
    #get/print human date format for logs
    print "\n$log_file \n\t ->  dated  -> $humantime -> errors: \n\n";
    open( $INPUTFILE, "<$log_file" ) or die "$!";
    #readh lines in for errors
    while (<$INPUTFILE>) {
        if ( $_ =~ m/ was not successful, or the requested account, (.*) was not found on the server: (.*)”\.","/ ) {
            my $account = $1;
            my $server  = $2;
            $account =~ s/\W//g;
            $server =~ s/\“|\"//g;
            push @error_list, "$account $server";
        }
    }
    #push unique errors array from %seen
    my @unique_error = grep { !$seen{$_}++ } @error_list,;
    foreach (@unique_error) {
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
            #normalize the file format and split
            $host_domain =~ s/:[\s]/==/g;
            my ( $new_domain, $user_name, $user_group, $domain_status, $primary_domain, $home_dir, $IP_port ) =
                split /==/,
                $host_domain, 9;
            my ($IP) = split /:/, $IP_port, 2;
            print "$IP\t\t$new_domain\twww.$new_domain\n";
        }
        else {
            next;
        }
    }
    print "\n";
}

sub get_mail_accounts {
    use Parallel::ForkManager;
    my $hashfile = ("$ENV{\"HOME\"}/.accesshash");
    if ( -f $hashfile ) {
        print "Checking mail users:\n";
    }
    else {
        system("/usr/local/cpanel/bin/realmkaccesshash");
        print "\nCreated new $hashfile as none existed.\n\n";
    }
    #went with API calls to prevent version splintering
    #for jsonand yaml files being used for email cache data based on version
    my $pm1 = new Parallel::ForkManager(4);
    foreach my $host_domain ( @{$link_ref} ) {
        $pm1->start and next;
        if ( $host_domain =~ /==/ ) {
            $host_domain =~ s/:[\s]/==/g;
            my ( $new_domain, $user_name, $user_group, $domain_status, $primary_domain, $home_dir, $IP_port ) = split /==/,
                $host_domain, 9;
            my @userarg = ( "$user_name", "$new_domain" );
            &mail_users_domains(@userarg);
        }
        $pm1->finish;
        $pm1->wait_all_children;
    }
    $pm1->finish;
    $pm1->wait_all_children;
}

sub mail_users_domains {
    require LWP::UserAgent;
    my $hashfile      = ("$ENV{\"HOME\"}/.accesshash");
    my $apiusername   = ("$ENV{\"USER\"}");
    my $cpanelapiuser = $_[0];
    my $maildomain    = $_[1];
    my $request1 =
        "cpanel?cpanel_jsonapi_user=$cpanelapiuser&cpanel_jsonapi_apiversion=2&cpanel_jsonapi_module=Email&cpanel_jsonapi_func=listpopswithdisk&domain=$maildomain";
    my $ahash = read_file("$ENV{\"HOME\"}/.accesshash");
    chomp($ahash);
    $ahash =~ (s/\n//g);
    my $cauth = "WHM " . "$apiusername:" . $ahash;
    $ENV{PERL_LWP_SSL_VERIFY_HOSTNAME} = 0;
    my $ua = LWP::UserAgent->new;
    my $request = HTTP::Request->new( GET => "https://127.0.0.1:2087/json-api/$request1" );
    $request->header( Authorization => $cauth );
    my $response        = $ua->request($request);       #get the api request/response then print
    my $content         = $response->content;
    my %decoded_content = %{ decode_json($content) };
    #take the decoded hash, pull out the child elements until data is found
    while ( my ( $parent_key, $hashref ) = each %decoded_content ) {
        while ( my ( $mail_key, $value ) = each %$hashref ) {
            if ( $mail_key eq "data" ) {
              #when we find data, dereference it's array elements(hashes) and slice based on keys
                foreach my $avar (@$value) {
                    my @mailhashes = $avar;
                    foreach my $href (@mailhashes) {
                        for my $role ( keys %$href ) {
                            if ( $role eq "email" ) {
                                $role = $href->{$role};
                                printf( "\tMail=%-40s ", $role );
                            }
                                elsif ( $role eq "domain" ) {
                                    $maildomain = $href->{$role};
                                 print "Domain=$maildomain ";
                                } elsif ( $role eq "humandiskused" ) {
                                  $role = $href->{$role};
                                  $role =~ s/\xa0//g;
                                  print "DiskUsed=$role\n";
                         }}
                }}
        }}
}}
1;
