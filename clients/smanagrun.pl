#!/usr/bin/perl
#
#

use warnings;
use strict;
use Net::Telnet;
use DBI;
use POSIX;
use Data::Dumper::Simple;
use lib '../include';
use nms;

BEGIN {
	require "../include/config.pm";
	eval {
		require "../include/config.local.pm";
	};
}
# Tweak and check
my $password = '';
my $delaytime = 30;

my $dbh = db_connect();
$dbh->{AutoCommit} = 0;

my $spoll = $dbh->prepare("
SELECT
  addr,
  sysname
FROM
  squeue
WHERE
  processed = 'f' AND
  disabled = 'f' AND
  (locked='f' OR now() - updated > '10 minutes'::interval) AND
  (delay IS NULL OR delay < now())
ORDER BY
  priority DESC,
  added
LIMIT 1");
my $sgetallpoll = $dbh->prepare("
SELECT
  id,
  gid,
  addr,
  sysname,
  cmd
FROM
  squeue
WHERE
  sysname = ? AND
  disabled = 'f' AND
  processed = 'f'
ORDER BY
  priority DESC,
  added");

my $slock = $dbh->prepare("UPDATE squeue SET locked = 't', updated=now() WHERE sysname = ?")
	or die "Unable to prepare slock";
my $sunlock = $dbh->prepare("UPDATE squeue SET locked = 'f', updated=now() WHERE sysname = ?")
	or die "Unable to prepare sunlock";
my $sresult = $dbh->prepare("UPDATE squeue SET updated = now(), result = ?,
                            processed = 't' WHERE id = ?")
	or die "Unable to prepare sresult";
my $sdelay = $dbh->prepare("UPDATE squeue SET delay = now() + delaytime, updated=now(), result = ? WHERE sysname = ?")
	or die "Unable to prepae sdelay";

sub mylog {
	my $msg = shift;
	my $time = POSIX::ctime(time);
	$time =~ s/\n.*$//;
	printf STDERR "[%s] %s\n", $time, $msg;
}

while (1) {
	$spoll->execute() or die "Could not execute spoll";
	my $switch = $spoll->fetchrow_hashref();
	if (!defined($switch)) {
		$dbh->commit;
		mylog("No available switches in pool, sleeping.");
		sleep 10;
		next;
	}
	$slock->execute($switch->{sysname});
	$dbh->commit();

	if ($switch->{'locked'}) {
		mylog("WARNING: Lock timed out on $switch->{'ip'}, breaking lock");
	}

	mylog("Connecting to $switch->{sysname} on $switch->{addr}");
	eval {
		my $ssh = switch_connect_ssh($switch->{addr});
		my $conn = $ssh->{telnet};
		if (!defined($conn)) {
			mylog("Could not connect to ".$switch->{sysname}."(".$switch->{addr}.")");
			$sdelay->execute("Could not connect to switch, delaying...", $switch->{sysname});
			$sunlock->execute($switch->{sysname});
			$dbh->commit();
			next;
		}
		my $error;
		$error = $sgetallpoll->execute($switch->{sysname});
		if (!$error) {
			print "Could not execute sgetallpoll\n".$dbh->errstr();
			$conn->close;
			next;
		}
		while (my $row = $sgetallpoll->fetchrow_hashref()) {
			my $sysname = $row->{sysname};
			my @data;
			my @commands = split(/[\r\n\000]+/, $row->{cmd});
			for my $cmd (@commands) {
				print "sysname: $sysname cmd: $cmd\n";
				next unless $cmd =~ /\S/; # ignorer linjer med kun whitespace
				push @data, "# $cmd";
				$cmd =~ s/%SYSNAME%/$sysname/g;
				if ($cmd =~ /^#\s*require-version\s+(.*\S)\s*$/) {
					my $required_version = $1;
					my $versions;
					$versions = switch_exec_json("show version", $conn);
					my $version = $versions->{'multi-routing-engine-results'}[0]{'multi-routing-engine-item'}[0]{'software-information'}[0]{'junos-version'}[0]{'data'};
					if ($version ne $required_version) {
						push @data, "# '$version' != '$required_version', aborting script";
						last;
					} else {
						push @data, "# Version matches";
					}
				} elsif ($cmd =~ s/^!//) {
					push @data, switch_exec($cmd, $conn, 1);
				} else {
					push @data, switch_exec($cmd, $conn);
				}
			}
			my $result = join("\n", @data);
			$sresult->execute($result, $row->{id});
		}
		$conn->close();
		waitpid($ssh->{pid}, 0);
		$sunlock->execute($switch->{sysname});
	};
	if ($@) {
		warn $@;
		chomp(my $err = $@);
		$sdelay->execute($err . ", delaying...", $switch->{sysname});
		$sunlock->execute($switch->{sysname});
		$dbh->commit();
	}
}

