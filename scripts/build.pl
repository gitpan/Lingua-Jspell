#!/usr/bin/perl

use warnings;
use strict;

use File::Copy;
use Config::AutoConf;
use ExtUtils::CBuilder;

# Gather some variables
my $VERSION = get_version();
my $prefix = get_prefix();

# Prepare a hash with variables for substitution on jsconfig.in
my %c_config = (PREFIX => $prefix, VERSION => $VERSION);

# Show some information to the user about what are we doing.
print "\n - Building International Jspell $VERSION - \n";

print "\nCompiling software for [$prefix].\n";

print "Checking for a working C compiler...";
if (not Config::AutoConf->check_cc()) {
	die "I need a C compiler. Please install one!\n" 
} else {
	print " [found]\n"
}



# print "Checking for a working YACC processor...";
# my $yacc;
# if (!($yacc = Config::AutoConf->check_prog_yacc())) {
#  	die "I need one of bison, byacc or yacc. Please install one!\n" 	
# } else {
#  	print " [found]\n"
# }

my $LCURSES="";
my $CCURSES="";
print "Checking for ncurses.h header file...";
if (not Config::AutoConf->check_header("ncurses.h")) {
	print " [not found]\n";
	$CCURSES="-DNOCURSES";
} else {
	print " [found]\n"
}

if ($CCURSES ne "-DNOCURSES") {
    # skip the library test if we do not have the header file.
    
    print "Checking for a working ncurses library...";
    if (not Config::AutoConf->check_lib("ncurses", "tgoto")) {
    	print " [not found]\n";
    	$CCURSES="-DNOCURSES";
    } else {
    	$LCURSES="-lncurses";
    	print " [found]\n"
    }    
}


if ($^O eq "MSWin32") {
	$CCURSES.=" -D__WIN__"
}

interpolate('src/jsconfig.in','src/jsconfig.h',%c_config);
interpolate('scripts/jspell-dict.in','scripts/jspell-dict',%c_config);
interpolate('scripts/installdic.in','scripts/installdic.pl',%c_config);
interpolate('jspell.pc.in','jspell.pc',%c_config);

# prepare a C compiler
my $cc = ExtUtils::CBuilder->new(quiet => 0);


### JSpell
print "\nCompiling Jspell.\n";

## print " - parse.y -> y.tab.c\n";
## my $cmd = "cd src; $yacc parse.y";
## print `$cmd`;
## 

my @jspell_source = qw~correct.c    good.c      jmain.c     makedent.c  tgood.c
                       defmt.c      hash.c      jslib.c     tree.c      vars.c
                       dump.c       jbuild.c    jspell.c    sc-corr.c   xgets.c
                       gclass.c     jjflags.c   lookup.c    term.c      y.tab.c~;
my @jspell_objects = map {
	print " - src/$_\n";
	$cc->compile(
		extra_compiler_flags => $CCURSES.' -DVERSION=\\"'.$VERSION.'\\" -Wall',
		source => "src/$_")} @jspell_source;
my @jspell_shared = grep {$_ !~ /jbuild|jmain/ } @jspell_objects;		

my $LIBEXT = ".so";
$LIBEXT = ".dylib" if $^O =~ /darwin/i;
$LIBEXT = ".dll"   if $^O =~ /mswin32/i;

print " - building [jspell] library\n";
$cc->link(extra_linker_flags => "$LCURSES$CCURSES",
          module_name => "jspell",
          objects => [@jspell_shared],  
          lib_file => "src/libjspell$LIBEXT");	


print " - building [jspell] binary\n";
$cc->link_executable(extra_linker_flags => "$LCURSES$CCURSES",
                     objects => [@jspell_shared, 'src/jmain.o'],  
                     exe_file => "src/jspell");
					 
print " - building [jbuild] binary\n";
$cc->link_executable(extra_linker_flags => "$LCURSES$CCURSES",
                     objects => [@jspell_shared, 'src/jbuild.o'], 
                     exe_file => "src/jbuild");

print "\nBuilt International Jspell $VERSION.\n";

open TS, '>_jdummy_' or die ("Cant create timestamp [_jdummy_].\n");
print TS scalar(localtime);
close TS;

# put agrep.1 file on the right place for installation
copy("agrep/agrep.1","blib/man1/agrep.1");


# #-------------------------------------------------------------------
sub interpolate {
	my ($from, $to, %config) = @_;
	
	print "Generating [$to] from template [$from].\n";
	open FROM, $from or die "Cannot open file [$from] for reading.\n";
	open TO, ">", $to or die "Cannot open file [$to] for writing.\n";
	while (<FROM>) {
		s/\[%\s*(\S+)\s*%\]/$config{$1}/ge;		
		print TO;
	}
	close TO;
	close FROM;
}

sub get_prefix {
	my $prefix = undef;
	open MAKEFILE, "Makefile" or die "Cannot open file [Makefile] for reading\n";
	while(<MAKEFILE>) {
		if (m!^SITEPREFIX\s*=\s*(.*)$!) {
			$prefix = $1;
			last;
		}
	}
	close MAKEFILE;
	die "Could not find INSTALLSITEBIN variable on your Makefile.\n" unless $prefix;
	$prefix=~s/\\/\//g;
	return $prefix;
}

sub get_version {
	my $version = undef;
	open PM, "lib/Lingua/Jspell.pm" or die "Cannot open file [lib/Lingua/Jspell.pm] for reading\n";
	while(<PM>) {
		if (m!^our\s+\$VERSION\s*=\s*'([^']+)'!) {
			$version = $1;
			last;
		}
	}
	close PM;
	die "Could not find VERSION on your .pm file. Weirdo!\n" unless $version;
}
