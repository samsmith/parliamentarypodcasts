#!/usr/bin/perl

use warnings;
use strict;

use LWP::Simple;
use DBI;
use XML::RSS;
my $dbh;
&setup ;

my @now=localtime;
my $d= $now[3];
my $m= $now[4]+1;
my $y= $now[5]+1900;

process("http://parliamentlive.tv/Search?Keywords=&Member=&MemberId=&House=&Business=&Start=$d%2F$m%2F$y&End=$d%2F$m%2F$y");

sub process {
	my $results_page= shift;

my $page = get ($results_page);
while ($page =~ m#/Event/Index/([^"]+)"#imscg) {
	my $uuid= $1;
	my $url= 'http://parliamentlive.tv/Event/Index/'.$uuid;
	next if $url =~ /\?/;

#	warn $1;

	# have we seen this UUID before?
	my $check= $dbh->prepare("select * from entries where uuid=?");
	$check->execute($uuid);
	unless (defined $ENV{REBUILD}) {
		next if $check->fetchrow_arrayref;
	}

	# fetch webpage
	my $ctte_webpage = get ($url);
	my ($title, $when, $date, $time,$notes);
	($title)= $ctte_webpage=~ m#<title>Parliamentlive.tv . (.*?)</title>#i;
	($date, $time)=  $ctte_webpage=~ m#<strong>([^<]+)</strong> (Meeting started at[^<]+)#i;
	$notes= "$date - $time\n";

	if ($ctte_webpage=~ /<h4>\s+Subject\s*: ([^<]*)/im){
		$notes .= "Subject: $1\n";
	}
	# XXX witnesses should go in notes here

	my $mp3 ="http://dl.parliamentlive.tv/ukp/vod/_download/${uuid}_01_64.mp3";
#	warn "$title\t$date\t$time\t$mp3";

	my $filename_rss= lc($title .'.rss');
	$filename_rss=~ s#[^A-Z0-9\.]#_#gi;
	
#		warn join "\n\t", $uuid, $title, $date, $time, $mp3, $url, $notes;
	# write entry to database
	$dbh->do("insert into entries set uuid=?, committee=?, date=?, time=?, mp3=?, url=?, notes=? ",undef,
		$uuid, $title, $date, $time, $mp3, $url, $notes);

	# select last few entries 
	my $q= $dbh->prepare("select * from entries where committee=? order by rowid desc limit 10");
	$q->execute($title);
	my $details= $q->fetchrow_hashref;

	use XML::RSS;
 	my $rss = XML::RSS->new (version => '2.0');
 	$rss->channel(title          => $details->{'committee'},
               link           => 'http://parliamentlive.tv/',
               language       => 'en',
               description    => 'podcast of '. $details->{'committee'},
               copyright      => 'Parliamentary Copyright',
               );

 	$rss->add_item(title => $details->{'committee'} . " " . $details->{'date'},
        	permaLink  => $details->{'url'},
        	guid     => "$details->{'uuid'}",
        	enclosure   => { url=>$details->{'mp3'}, type=>"audio/mpeg" },
        	description => $details->{'notes'}
	);

	# older meetings
	while (my $item =$q->fetchrow_hashref) {
 		$rss->add_item(title => $details->{'committee'} . " " . $details->{'date'},
        		# creates a guid field with permaLink=true
        		permaLink  => $details->{'url'},
        		# alternately creates a guid field with permaLink=false
        		guid     => "$details->{'uuid'}",
        		enclosure   => { url=>$details->{'mp3'}, type=>"audio/mpeg" },
        		description => $details->{'notes'}
		);
	}
#	print $rss->as_string;
	# output rss
	$rss->save($filename_rss);

	
	# if there were going to be per-inquiry RSS feeds for select committees, that would happen here based on 
	#	contents of $notes
}
}

sub setup {
	chdir '/data/vhost/parliamentarypodcasts/docs/';

	if (not defined $ENV{DB_USERNAME} or not defined $ENV{DB_DB} or not defined $ENV{DB_PASSWORD}) {
		die " pass DB_USERNAME DB_PASSWORD DB_DB variables via environment.\n";
	}
	my $dsn = "DBI:mysql:$ENV{DB_DB}:localhost"; # DSN connection string
	$dbh=DBI->connect($dsn, $ENV{DB_USERNAME}, $ENV{DB_PASSWORD}, {RaiseError => 0});

}
