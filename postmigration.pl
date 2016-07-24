#!/usr/local/cpanel/3rdparty/perl/522/bin/perl
# cpanel                                          Copyright(c) 2016 cPanel, Inc.
#                                                           All rights Reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
package PostMigration;
use File::Spec;
use strict;
use warnings;
$Term::ANSIColor::AUTORESET = 1;
use Term::ANSIColor qw(colored coloralias);
use lib "/usr/local/cpanel/3rdparty/perl/514/lib64/perl5/cpanel_lib/";
use JSON;
use IPC::System::Simple qw(system capture $EXITVAL);
use File::Slurp qw(read_file);
use Getopt::Long;

my $mail        = 0;                         #defaults go here
my $ipdns       = 0;
my $all         = 0;
my $hosts       = 0;
my $help        = 0;
my $jsons       = 0;
my $localcheck  = 0;
my $transferror = 0;
my $humanrun    = "1";
my %domains;
my %checkedDomains;
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

if ($localcheck) {                           # used for dig
    $dns_toggle = "localhost";
}
else {                                       # default, used if -local is not set
    $dns_toggle = "8.8.8.8";
}
if ($help) {
    &helpsub();
}
                                             
elsif ($jsons) {
    $humanrun = "0";                         # for json output
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

sub http_web_request {                      # we use LWP to get the status code and PeerIP(connectedIP) here
    require LWP::UserAgent;
    $SIG{'INT'} = sub {
        print "\nCaught CTRL+C!..";         # we set a listener for Ctrl+C
        print RESET " Ending..\n";
        kill HUP => -$$;
    };
    my $url = $_[0];                        # this should be passed in as a an argument
    if ($url) {
        my $ua = LWP::UserAgent->new( agent => 'Mozilla/5.0', timeout => '1' );
        my $req   = HTTP::Request->new( GET => "http://$url" );
        my $reqIP = "NoConnect";            # placeholder in case we dont get one
        my $code  = "Missing_Return_Status";# same as above 
        my $res   = $ua->request($req);
        my $body  = $res->decoded_content;
        $code = $res->code();               # get the response, headers as a string, then send the request header
        my $headervar = $res->headers()->as_string; 
        print $res->header("content-type\r\n\r\n");

        if ( $headervar =~ /Client-Peer:[\s](.*):([0-9].*)/ ) {
            $reqIP = "$1";
        }
        else {
            $reqIP = "NoConnect";           # set the request if it doesnt exist
            chomp($reqIP);
        }
        if ( not defined $code ) {
            $code = "Missing_Return_Status";# same as above
        }
                                            # once we get them, we populate our hash with the code and IP
        $checkedDomains{$url}->{Status} = $code; 
        $checkedDomains{$url}->{ReqIP}  = $reqIP;

    }
}

sub dns_web_request {                       # listen for sigint
    $SIG{'INT'} = sub {
        print "\nCaught CTRL+C!..";
        print RESET " Ending..\n";
        kill HUP => -$$;
    };
    my $url = $_[0];                        # set the URL read in from arg passed to sub
    if ($url) {
        my $domain        = $url;
        my $google_dns    = "NoConnect";
        my $localhost_dns = "NoConnect";
        my $cmd           = "dig";          # use dig, set no connect as the default, unless we get an updated value later
        my @local_args =                    # arguments for localhost request
          ( "\@localhost", "$domain", "A", "+short", "+tries=1" );
        my @google_args =                   # arguments for standard request
          ( "\@$dns_toggle", "$domain", "A", "+short", "+tries=1" ); 
        my @google_dnsa = capture( $cmd, @google_args ); 
        $google_dns = $google_dnsa[0];      # get the data from the return array
        my @localhost_dnsa = capture( $cmd, @local_args );
        $localhost_dns = $localhost_dnsa[0];

        if ( not defined $google_dns ) {
            $google_dns = "NoConnect";
        }
        if ( not defined $localhost_dns ) {
            $localhost_dns = "NoConnect";
        }
        chomp( $domain, $google_dns, $localhost_dns );
                                            # add our results to the hash to print
        $checkedDomains{$domain}->{RemoteDNS} = $google_dns; 
        $checkedDomains{$domain}->{Local_DNS} = $localhost_dns;
    }

}

sub get_webrequest {                        # listen for sigint
    $SIG{'INT'} = sub {
        print "\nCaught CTRL+C!..";
        print RESET " Ending..\n";
        kill HUP => -$$;
    };
    foreach my $uDomain (@links) {
        if ( $uDomain =~ /(.*):[\s]/ ) {    # here's where the domains actually get sent into the dns/http subs
            our $resource = $1;
            &http_web_request("$resource");
            sleep(.5);
            &dns_web_request("$resource");
        }
    }
    &print_data();                          # then after we build our hashes from the for loops in the sub, we print it.
}

sub print_data {

    if ( $humanrun eq "1" ) {               # determine if we're printing json or not

        my $item;                           # this is the domain key from checkedDomains
        foreach $item ( keys %checkedDomains ) {
            printf "\l\n\t-> $item: ";      # then the items inside the hashes hash
            foreach my $iteminitem ( sort keys %{ $checkedDomains{$item} } ) { 
                if ( $iteminitem eq "Local_DNS" || $iteminitem eq "RemoteDNS" ) 
                {
                    printf( "\n %s: %-20s", # string format for column-ish output
                        $iteminitem, $checkedDomains{$item}{$iteminitem} );
                }
                 else {                     # otherwise
                 printf( " %s: %-20s",
                        $iteminitem, $checkedDomains{$item}{$iteminitem} );
                 }
            }
            print "\n";
        }

    }
    elsif ( $humanrun eq "0" ) {            # if we're printing json, encode/print our hashed hash
        my $jsondata = encode_json \%checkedDomains;
        print "$jsondata";

    }
}

sub transfer_errors {                       # outdated, needs to be revisited
    use Path::Class;
    print "\n";
    my $transfer_logdir = "/var/cpanel/transfer_sessions";
    my @files; 

    dir("$transfer_logdir")->recurse(
        callback => sub {
            my $file = shift;
            if ( $file =~ /master.log/ ) {  # populate our log array based on master.logs found using Path::Class
                push @files, $file->absolute->stringify; 
            }
        }
    );

    foreach my $filename (@files) {
        &find_pkgacct_errors("$filename");  # pass our logs found to the pkgacct errors subroutine
    }
}

sub find_pkgacct_errors {
    my %seen;
    my @error_list;
    my $log_file =
      $_[0];                                #read in passed arg, stat on it and print human readable
    my $last_mod_time = ( stat($log_file) )[9];
    my $humantime     = localtime($last_mod_time);
    my $INPUTFILE;                          # fh for parsing the logfile
    coloralias('alert', 'blue');
    print colored("\n$log_file\n\t -> $humantime ", 'alert');
    coloralias('starterr', 'red');
    print colored("-> errors:\n\n", 'starterr');
    open( $INPUTFILE, "<$log_file" ) or die "$!";

    while (<$INPUTFILE>) {
        my $error = $_;                     # try to only get the errors, remove non-errors, noise
        if ( $error =~ /warning|failed/i ) {
            $error =~ s/\.\.\.\.\.\.\.\.\.//g;
            $error =~
s/.*msg":\{"warnings":0,"dangerous_items":0,"contents":\{"warnings":null,"dangerous_items":null,"skipped_items":null,"altered_items":null\},"skipped_items":0,"message":null,"altered_items":0.*//g;
            $error =~
s/.*msg":\{"warnings":0,"dangerous_items":0,"contents":\{"warnings":\[\],"dangerous_items":\[\],"skipped_items":\[\],"altered_items":\[\]},"skipped_items":0,"message":null,"altered_items":0.*//g;
            $error =~ s/\n//g;
            if ( $error ne "" ) {
                push @error_list, "$error"; # push the error to our array
            }
        }
    }                                       # print from our array
    my @unique_error = grep { !$seen{$_}++ } @error_list,;
    foreach my $uError (@unique_error) {
        print "$uError\n\n";
    }
}



sub gen_hosts_file {                        # generate a hosts file matching servers, to point workstation to
    print "\n\n\t::Hosts File::\n\n";
    foreach my $host_domain ( @{$link_ref} ) {
        if ( $host_domain =~ /==/ ) {       # just read in the domain/IP here..
            $host_domain =~ s/:[\s]/==/g;
            my ( $new_domain, $user_name, $user_group, $domain_status,
                $primary_domain, $home_dir, $IP_port )
              = split /==/,
              $host_domain, 9;
            my ($IP) = split /:/, $IP_port, 2;
            print "$IP\t\t$new_domain\twww.$new_domain\n";
                                            # print in /etc/hosts format for the servers local IP's to copy/paste
        }
        else {
            next;
        }
    }
    print "\n";
}

sub get_mail_accounts {
    print "\n\n\t::Mail accounts found::\n\n";
    use File::Slurp qw(read_file);

                                            # read in users from passwd
    my @passwd = read_file("/etc/passwd");
    my $dir    = '/var/cpanel/users';
    my %user_list;
    opendir( DIR, $dir ) or die $!;
    while ( my $file = readdir(DIR) ) {
        next if ( $file =~ m/^\./ );
        foreach my $line (@passwd) {

                                            # if we look like a system and cpanel user?
            if ( $line =~ /^$file:[^:]*:[^:]*:[^:]*:[^:]*:([a-z0-9_\/]+):.*/ ) {
                $user_list{$file} = $1;
            }
        }
    }
    closedir(DIR);

                                            # for the users found, if we aren't root look for an etc dir
    foreach my $user ( keys %user_list ) {
        if ( $user ne "root" ) {
            print "User=$user->\n";
            opendir( ETC, "$user_list{$user}/etc" ) || next;
            my $path = $user_list{$user};

                                            # for the domains found in the users etc dir
            while ( my $udomain = readdir(ETC) ) {
                next if $udomain =~ /^\./;  # skip . and .. dirs
                                            # see if we are a valid etc domain and if so, look for mail users and print
                if ( -d "$path/etc/$udomain/" ) {
                    my $PASSWD;
                    open( $PASSWD, "$path/etc/$udomain/passwd" ) || next;
                    while ( my $PWLINE = <$PASSWD> ) {
                        $PWLINE =~ s/:.*//
                          ;                 # only show line data before first colon (username only)
                        chomp( $user, $udomain, $PWLINE );
                        my $sumFile = "$path/mail/$udomain/$PWLINE/maildirsize";
                        open my $SUMLINES, '<', $sumFile || continue;
                        my $total  = "0";
                        my $totals = "0";
                                            #sum our quota lines
                        while (<$SUMLINES>) {
                            my ( $suml, $thing ) = split;  
                            if ( $suml !~ /[a-zA-Z]/ && $suml != 0 ) {
                                $totals += $suml;
                            }
                        }                   #store in M format
                        $totals = ( $totals / 1024 / 1024 ); 
                                            #print the data found for mail
                        my $PWLINED = "$PWLINE\@$udomain";
                        chomp($PWLINED);
                        printf( "   Email=%s\t", $PWLINED );
                        print " Disk=";
                        my $dsval = sprintf( "%06.5f", $totals );
                        printf( "%-05sMB\n", $dsval );

                    }
                    close($PASSWD);
                }
            }
        }
        close(ETC);
    }
    print "\n";
}

1;
