use strict;
use warnings;
use ExtUtils::MakeMaker;

use 5.008001;

# NOT SURE IF I WANT THIS OR NOT
# unlink "_jdummy_";

my $EXE = "";
$EXE=".exe" if $^O eq "MSWin32";

my %conf =
  (
   NAME                => 'Lingua::Jspell',
   AUTHOR              => 'Projecto Natura',
   VERSION_FROM        => 'lib/Lingua/Jspell.pm',
   ABSTRACT_FROM       => 'lib/Lingua/Jspell.pm',
   PL_FILES            => {},
   PREREQ_PM => {
                 'Config::AutoConf'   => '0.09',
                 'ExtUtils::CBuilder' => '0.23',
                 'File::Which'        => '0',
                 'Archive::Any'       => '0.0932',
                 'LWP::Simple'        => '0',
                 'Test::More'         => '0',
                 'IPC::Open2'         => '0',
                 'YAML::Any'          => '0.67',
                },
   PM_FILTER => '$(PERL) scripts/changePrefix $(SITEPREFIX)',
   EXE_FILES => ["src/jspell$EXE",
                 "src/jbuild$EXE",
                 "scripts/jspell-dump",
                 "scripts/jspell-dict",
                 "scripts/ujspell"],
   MAN1PODS  => {
                 'src/jspell.pod'      => 'blib/man1/jspell.1',
                 'src/jspellaff.pod'   => 'blib/man1/jspellaff.1',
                 'src/jbuild.pod'      => 'blib/man1/jbuild.1',
                 'scripts/jspell-dict' => 'blib/man1/jspell-dict.1',
                 'scripts/jspell-dump' => 'blib/man1/jspell-dump.1',
                },
   dist      => { COMPRESS => 'gzip -9f', SUFFIX => 'gz', },
   clean     => { FILES => "Lingua-Jspell-* src/*.o src/jbuild$EXE src/jspell$EXE _jdummy_" },
);

WriteMakefile( %conf );

open MAKEFILE, ">>Makefile" or die "Cannot open file [Makefile] for writing\n";
print MAKEFILE "\n\nprintprefix:\n\t\@ \$(ECHO) \$(SITEPREFIX)\n";
close MAKEFILE;

package MY; # so that "SUPER" works right

our @jspell;
our @scripts;

BEGIN {
    ## Construct dependencies lists automagically
    open M, "MANIFEST" or die "Weirdo. I can't read MANIFEST!";
    while (<M>) {
        chomp;
        push @jspell, $_ if /^src.*[ch]$/;
        push @scripts, $_ if /^scripts.*in$/;
    }
    close M;
}

sub install {
    my $inherited = shift->SUPER::install(@_);
	$inherited =~ s!install\s*::\s*all!install :: all installdic!; 
	$inherited
}

sub top_targets {
    my $inherited = shift->SUPER::top_targets(@_);
    $inherited =~ s!^(config\s*::.*)$!$1 jspell!m;
    $inherited;
}

sub postamble {
    return <<"MAKE_FRAG";
installdic:
	\$(PERL) scripts/installdic.pl

jspell: _jdummy_
	\$(NOECHO) \$(NOOP)
	
src/y.tab.c: src/parse.y
	yacc -o src/y.tab.c src/parse.y 
	
_jdummy_: @scripts @jspell scripts/build.pl
	\$(PERL) scripts/build.pl

MAKE_FRAG
}
