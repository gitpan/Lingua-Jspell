#!/usr/bin/perl

use warnings;
use strict;

eval { require LWP::Simple };

if ($@) {
	print STDERR "LWP::Simple not available on your system.\n";
	print STDERR "I'll not try to install any dictionary now.\n";
	exit;
}

LWP::Simple->import();
my $dicurl = 'http://natura.di.uminho.pt/download/sources/Dictionaries/jspell/jspell.pt-latest.tar.gz';
getstore($dicurl, "dic.tar.gz");