#! /usr/bin/perl
use CGI qw(fatalsToBrowser);
use GD;
use DBI;
use lib '../../include';
use nms;
use strict;
use warnings;
use File::Basename;
my $cgi = CGI->new;
my $cwd = dirname($0);

#my $greentimeout = 7200;
my $greentimeout = 15*60;
my $maxtimeout = $greentimeout*9;

my $dbh = nms::db_connect();

GD::Image->trueColor(1);
my $img = GD::Image->new($cwd.'/tg15-salkart.png');

my $blk = $img->colorResolve(0, 0, 0);

$img->string(gdMediumBoldFont,0,0,"Switch uplink status",$blk);
$img->string(gdSmallFont,0,20,"Number of ports with activity",$blk);

my $red = $img->colorResolve(255, 0, 0);
my $yel = $img->colorResolve(255, 255, 0);
my $grn = $img->colorResolve(0, 255, 0);
my $wht = $img->colorResolve(255, 255, 255);
my $gry = $img->colorResolve(127, 127, 127);

#my $q = $dbh->prepare('select switch,sysname,(select placement from placements where placements.switch=switches.switch) as placement,count((bytes_in > 0 and bytes_out > 0) or null) as active_ports,(max(last_poll_time) >= current_timestamp - interval \'2 minutes\') as fresh from switches natural left join get_current_datarate() natural join placements where switchtype like \'dlink3100%\' group by switch,sysname');
my $q = $dbh->prepare(' select switch,sysname,(select placement from placements where placements.switch = switches.switch) as placement,count((operstatus = 1) or null) as active_ports from switches natural left join get_operstatus() natural join placements where ifdescr like \'ge-0/0/%\'  group by switch,sysname');
$q->execute();
while (my $ref = $q->fetchrow_hashref()) {
	my $ports = $ref->{'active_ports'};
	my $sysname = $ref->{'sysname'};
	my $clr;
	if ($ports < 5) {
		$clr = $red;
	} else {
		if (!$ref->{'fresh'}) {
			$clr = $yel;
		} else {
			$clr = $grn;
		}
	}
	
	$ref->{'placement'} =~ /\((\d+),(\d+)\),\((\d+),(\d+)\)/;
	$img->filledRectangle($3,$4,$1,$2,$clr);
	$img->rectangle($3,$4,$1,$2,$blk);

	my ($x2, $y2, $x1, $y1) = ($1, $2, $3, $4);
	my $max_textlen = ($x2-$x1) > ($y2-$y1) ? $x2-$x1 : $y2-$y1;
	while (length($sysname) * 6 > $max_textlen) {
		# Try to abbreviate sysname if it is too long for the box
		$sysname =~ s/^(.*)[a-z]~?([0-9]+)$/$1~$2/ or last;
	}
	if (($x2-$x1) > ($y2-$y1)) {
		$img->string(gdSmallFont,$x1+2,$y1,$sysname,$blk);
	} else {
		$img->stringUp(gdSmallFont,$x1,$y2-3,$sysname,$blk);
	}
}
$dbh->disconnect;

if (!defined($ARGV[0])) {
	print $cgi->header(-type=>'image/png',
			   -refresh=>'10; ' . CGI::url());
}
print $img->png;
