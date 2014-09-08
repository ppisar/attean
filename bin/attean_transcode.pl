#!/usr/bin/perl

use strict;
use warnings;
use Getopt::Long;
use Time::HiRes qw(gettimeofday tv_interval);
use Attean;

unless (@ARGV) {
	print <<"END";
Usage: $0 -i in_format -o out_format rdf_data.filename

END
	exit;
}

my $verbose		= 0;
my $pull		= 0;
my $push		= 0;
my $block_size	= 25;
my %namespaces;
my $in	= 'ntriples';
my $out	= 'rdfxml';
my $result	= GetOptions ("verbose" => \$verbose, "block=i" => \$block_size, "pull" => \$pull, "push" => \$push, "in=s" => \$in, "out=s" => \$out, "define=s" => \%namespaces, "D=s" => \%namespaces);

unless (@_) { push(@ARGV, '-') }
my $file	= shift or die "An input filename must be given";
my $fh;
if ($file eq '-') {
	$fh	= \*STDIN;
} else {
	open( my $fh, '<:encoding(UTF-8)', $file ) or die $!;
}

my $done :shared;
my $st :shared;

$done			= 0;
my $parser		= Attean->get_parser($in)->new();
my $serializer	= Attean->get_serializer($out)->new(namespaces => \%namespaces);
my $out_io		= \*STDOUT;
$|				= 1;

if ($pull) {
	print "# Pull parsing\n" if ($verbose);
	pull_transcode($parser, $serializer, $out_io);
} elsif ($push) {
	print "# Push parsing\n" if ($verbose);
	push_transcode($parser, $serializer, $out_io);
} elsif ($parser->does('Attean::API::PullParser')) {
	print "# Pull parsing\n" if ($verbose);
	pull_transcode($parser, $serializer, $out_io);
} elsif ($parser->does('Attean::API::PushParser')) {
	print "# Push parsing\n" if ($verbose);
	push_transcode($parser, $serializer, $out_io);
}

sub pull_transcode {
	my $parser		= shift;
	my $serializer	= shift;
	my $out_io		= shift;
	warn "Pull parser";
	my $iter		= $parser->parse_iter_from_io($fh);
	$serializer->serialize_iter_to_io($out_io, $iter);
}

sub push_transcode {
	my $parser		= shift;
	my $serializer	= shift;
	my $out_io		= shift;
	warn "Push parser";
	if ($serializer->does('Attean::API::AppendableSerializer')) {
		my $count	= 0;
		my $start	= [gettimeofday];
		my @queue;
		my $handler	= sub {
			my $triple	= shift;
			$count++;
			print STDERR "\r";
			
			push(@queue, $triple);
			if (scalar(@queue) > 100) {
				$serializer->serialize_list_to_io($out_io, @queue);
				@queue	= ();
			}
			
			if ($count % $block_size == 0) {
				my $elapsed	= tv_interval($start);
				my $tps		= $count / $elapsed;
				print STDERR sprintf("%6d (%9.1f T/s)", $count, $tps);
			}
		};
		$parser->handler($handler);
		$parser->parse_cb_from_io($fh);

		# finish
		$serializer->serialize_list_to_io($out_io, @queue);
		my $elapsed	= tv_interval($start);
		my $tps		= $count / $elapsed;
		print STDERR sprintf("\r%6d (%9.1f T/s)\n", $count, $tps);
	} else {
		pull_transcode($parser, $serializer, $out_io);
	}
}