#! /usr/bin/perl
use strict;
use warnings;
package nms::util;
use Data::Dumper;

use base 'Exporter';
our @EXPORT = qw(guess_placement parse_switches_txt parse_switches parse_switch);

# Parse a single switches.txt-formatted switch
sub parse_switch {
	my ($switch, $subnet4, $subnet6, $mgtmt4, $mgtmt6, $lolid, $distro) = split(/ /);
	my %foo = guess_placement($switch);
	my %ret = (
		'sysname' => "$switch",
		'subnet4' => "$subnet4",
		'subnet6' => "$subnet6",
		'mgtmt4' => "$mgtmt4",
		'mgtmt6' => "$mgtmt6",
		'lolid' => "$lolid",
		'ip' => "$mgtmt4",
		'distro' => "$distro"
	);
	%{$ret{'placement'}} = guess_placement($switch);
	return %ret;
}

# Parses a switches_txt given as a filehandle on $_[0]
# (e.g.: parse_switches_txt(*STDIN) or parse_switches_txt(whatever).
sub parse_switches_txt {
	my $fh = $_[0];
	my @switches;
	while(<$fh>) {
		chomp;
		my %switch = parse_switch($_);
		push @switches, {%switch};
	}
	return @switches;
}

# Parses switches in switches.txt format given as $_[0].
# E.g: parse_switches("e1-3 88.92.0.0/26 2a06:5840:0a::/64 88.92.54.2/26 2a06:5840:54a::2/64 1013 distro0")
sub parse_switches {
	my @switches;
	my $txt = $_[0];
	foreach (split("\n",$txt)) {
		chomp;
		my %switch = parse_switch($_);
		push @switches, {%switch};
	}
	return @switches;
}

# Guesses placement from name to get a starting point
# Largely courtesy of Knuta
sub guess_placement {
	my ($x, $y, $xx, $yy);

	my $name = $_[0];
	my $src = "unknown";
	if ($name =~ /^e\d+-\d+$/) {
		$name =~ /e(\d+)-(\d+)/;
		my ($e, $s) = ($1, $2);
		$src = "main";

		$x = int(292 + (($e-1)/2) * 31.1);
		$y = undef;

		$x += 14 if ($e >= 13);
		$x += 14 if ($e >= 25);
		$x += 14 if ($e >= 41);
		$x += 14 if ($e >= 59);

		if ($s > 2) {
			$y = 405 - 120 * ($s-2);
		} else {
			$y = 689 - 120 * ($s);
		}

		$xx = $x + 16;
		$yy = $y + 120;

		# Justeringer
		$y += 45 if $name eq "e1-4";
		$y += 20 if $name eq "e3-4";
		$y += 15 if $name eq "e5-4";
		$yy -= 25 if $name eq "e7-1";
		$y += 10 if $name eq "e5-2";
		$yy -= 25 if $name eq "e5-2";
		$y += 20 if ($e >= 81 and $s == 2);
		$yy -= 20 if ($e >= 79 and $s == 1);
		$yy -= 30 if ($e >= 81 and $s == 1);

	} elsif ($name =~ /^sw(\d+)-creativia$/) {
		my ($s) = ($1);
		$src = "creativia";
		$x = 1535;
		$y = int(160 + 32.2 * $s);
		$yy = $y + 20;
		if ($s == 1) {
			$xx = $x + 70;
		} elsif ($s == 2) {
			$xx = $x + 90;
		} elsif ($s == 3) {
			$xx = $x + 102;
		} else {
			$xx = $x + 142;
		}

	} elsif ($name =~ /^crew(\d+)-(\d+)$/) {
		my ($s, $n) = ($1, $2);
		$src = "crew";
		$x = 550 + 65 * $n;
		$y = int(759 + 20.5 * $s);
		$xx = $x + 65;
		$yy = $y + 14;
	} elsif ($name =~ /^distro(\d)/) {
		my $d = ($1);
		$src = "distro";
		$x = 292 + $d * 165;
		$y = 415;
		$xx = $x + 130;
		$yy = $y + 20;
	} else {
		# Fallback to have _some_ position
		$src = "random";
		$x = int(rand(500));
		$y = int(rand(500));
		$xx = $x + 20;
		$yy = $y + 130;
	};


	my %box = (
		'src' => "$src",
		'x1' => $x,
		'y1' => $y,
		'xx' => $xx,
		'yy' => $yy
	);
	return %box;
}
