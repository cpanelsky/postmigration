Examples:

Run help
-  /usr/local/cpanel/3rdparty/bin/perl <(curl -sL https://raw.githubusercontent.com/cpanelsky/postmigration/master/postmigration.pl) -help

Run in the background, wait for results: 
 - nohup bash -c '/usr/local/cpanel/3rdparty/perl/522/bin/perl <(curl -sL https://raw.githubusercontent.com/cpanelsky/postmigration/master/postmigration.pl) -ipdns -json -local | /usr/local/cpanel/3rdparty/perl/522/bin/json_xs 2>&1 > this.out' &

Download as module, include and use functions from: 
 - wget -O PostMigration.pm  https://raw.githubusercontent.com/cpanelsky/postmigration/master/postmigration.pl
 /usr/local/cpanel/3rdparty/perl/522/bin/perl -I$(pwd) -e 'use PostMigration;$test = &PostMigration::http_web_request("www.google.com"); print $test;'
