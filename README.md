Examples:

Run help
-  /usr/local/cpanel/3rdparty/bin/perl <(curl -sL https://raw.githubusercontent.com/cpanelsky/postmigration/master/postmigration.pl) -help

Download as module, include and use functions from: 
 - wget -O PostMigration.pm  https://raw.githubusercontent.com/cpanelsky/postmigration/master/postmigration.pl
 - /usr/local/cpanel/3rdparty/bin/perl -I$(pwd) -e 'use PostMigration;$test = &PostMigration::http_web_request("www.google.com"); print "$test\n;"'
