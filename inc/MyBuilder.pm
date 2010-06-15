package MyBuilder;
use base 'Module::Build';
use warnings;
use strict;
use Config;
use Carp;
use Config::AutoConf;
use Config::AutoConf::Linker;
use ExtUtils::ParseXS;
use ExtUtils::Mkbootstrap;
use File::Spec::Functions qw.catdir catfile.;
use File::Path qw.mkpath.;

sub ACTION_pre_install {
    my $self = shift;

    # Fix the path to the library in case the user specified it during install
    if (defined $self->{properties}{install_base}) {
        my $usrlib = catdir($self->{properties}{install_base} => 'lib');
        $self->install_path( 'usrlib' => $usrlib );
        warn "libjspell.so will install on $usrlib. Be sure to add it to your LIBRARY_PATH\n"
    }

    # Create and prepare for installation the .pc file if not under windows.
    if ($^O ne "MSWin32") {
        _interpolate('jspell.pc.in' => 'jspell.pc',
                     VERSION    => $self->notes('version'),
                     EXECPREFIX => $self->install_destination('bin'),
                     LIBDIR     => $self->install_destination('usrlib'));
        $self->copy_if_modified( from   => "jspell.pc",
                                 to_dir => 'blib/pcfile',
                                 flatten => 1 );
    }

    # Interpolate the script files, and prepare them for installation
    _interpolate(catfile('scripts','ujspell.in') => catfile('scripts','ujspell'),
                 BINDIR => $self->install_destination('bin'));
    _interpolate(catfile('scripts','jspell-dict.in') => catfile('scripts','jspell-dict'),
                 LIBDIR => $self->install_destination('usrlib'));
    _interpolate(catfile('scripts','jspell-installdic.in')=> catfile('scripts','jspell-installdic'),
                 LIBDIR => $self->install_destination('usrlib'));

    for (qw.ujspell jspell-dict jspell-installdic.) {
        $self->copy_if_modified( from   => catfile("scripts",$_),
                                 to_dir => catdir('blib','script'),
                                 flatten => 1 );
        $self->make_executable( catfile('blib','script',$_ ));
    }
}

sub ACTION_fakeinstall {
    my $self = shift;
    $self->dispatch("pre_install");
    $self->SUPER::ACTION_fakeinstall;
}

sub ACTION_install {
    my $self = shift;
    $self->dispatch("pre_install");
    $self->SUPER::ACTION_install;

    # Run ldconfig if root
    if ($^O =~ /linux/ && $ENV{USER} eq 'root') {
        my $ldconfig = Config::AutoConf->check_prog("ldconfig");
        system $ldconfig if (-x $ldconfig);
    }

    print STDERR "Type 'jspell-installdic pt en' to install portuguese and english dictionaries.\n";
    print STDERR "Note that dictionary installation should be performed by a superuser account.\n";
}

sub ACTION_code {
    my $self = shift;

    for my $path (catdir("blib","bindoc"),
                  catdir("blib","pcfile"),
                  catdir("blib","script"),
                  catdir("blib","bin")) {
        mkpath $path unless -d $path;
    }

    my $x = $self->notes('libdir');
    $x =~ s/\\/\\\\/g;
    _interpolate("src/jsconfig.in" => "src/jsconfig.h",
                 VERSION => $self->notes('version'),
                 LIBDIR  => $x,
                );

    $self->dispatch("create_manpages");
    $self->dispatch("create_yacc");
    $self->dispatch("create_objects");
    $self->dispatch("create_library");
    $self->dispatch("create_binaries");

    # $self->dispatch("compile_xscode");

    $self->SUPER::ACTION_code;
}

# sub ACTION_compile_xscode {
    # my $self = shift;
    # my $cbuilder = $self->cbuilder;

    # my $archdir = catdir( $self->blib, 'arch', 'auto', 'Lingua', 'Jspell');
    # mkpath( $archdir, 0, 0777 ) unless -d $archdir;

    # print STDERR "\n** Preparing XS code\n";
    # my $cfile = catfile("xscode","BibTeX.c");
    # my $xsfile= catfile("xscode","BibTeX.xs");

    # $self->add_to_cleanup($cfile); ## FIXME
    # if (!$self->up_to_date($xsfile, $cfile)) {
    #     ExtUtils::ParseXS::process_file( filename   => $xsfile,
    #                                      prototypes => 0,
    #                                      output     => $cfile);
    # }

    # my $ofile = catfile("xscode","BibTeX.o");
    # $self->add_to_cleanup($ofile); ## FIXME
    # if (!$self->up_to_date($cfile, $ofile)) {
    #     $cbuilder->compile( source               => $cfile,
    #                         include_dirs         => [ catdir("btparse","src") ],
    #                         object_file          => $ofile);
    # }

    # # Create .bs bootstrap file, needed by Dynaloader.
    # my $bs_file = catfile( $archdir, "BibTeX.bs" );
    # if ( !$self->up_to_date( $ofile, $bs_file ) ) {
    #     ExtUtils::Mkbootstrap::Mkbootstrap($bs_file);
    #     if ( !-f $bs_file ) {
    #         # Create file in case Mkbootstrap didn't do anything.
    #         open( my $fh, '>', $bs_file ) or confess "Can't open $bs_file: $!";
    #     }
    #     utime( (time) x 2, $bs_file );    # touch
    # }

    # my $objects = $self->rscan_dir("xscode",qr/\.o$/);
    # # .o => .(a|bundle)
    # my $lib_file = catfile( $archdir, "BibTeX.$Config{dlext}" );
    # if ( !$self->up_to_date( [ @$objects ], $lib_file ) ) {
    #     my $btparselibdir = $self->install_path('usrlib');
    #     $cbuilder->link(
    #                     module_name => 'Text::BibTeX',
    #                     ($^O !~ /darwin/)?
    #                     (extra_linker_flags => "-Lbtparse/src -Wl,-R${btparselibdir} -lbtparse "):
    #                     (extra_linker_flags => "-Lbtparse/src -lbtparse "),
    #                     objects     => $objects,
    #                     lib_file    => $lib_file,
    #                    );
    # }
#}

sub ACTION_create_yacc {
    my $self = shift;

    my $ytabc  = catfile('src','y.tab.c');
    my $parsey = catfile('src','parse.y');

    return if $self->up_to_date($parsey, $ytabc);

    my $yacc = Config::AutoConf->check_prog("yacc","bison");
    if ($yacc) {
        `$yacc -o $ytabc $parsey`;
    }
}

sub ACTION_create_manpages {
    my $self = shift;

    my $pods = $self->rscan_dir("src", qr/\.pod$/);

    my $version = $self->notes('version');
    for my $pod (@$pods) {
        my $man = $pod;
        $man =~ s!.pod!.1!;
        $man =~ s!src!catdir("blib","bindoc")!e;
        next if $self->up_to_date($pod, $man);
        ## FIXME
        `pod2man --section=1 --center="Lingua::Jspell" --release="Lingua-Jspell-$version" $pod $man`;
    }

    my $pod = 'scripts/jspell-dict.in';
    my $man = catfile('blib','bindoc','jspell-dict.1');
    unless ($self->up_to_date($pod, $man)) {
        `pod2man --section=1 --center="Lingua::Jspell" --release="Lingua-Jspell-$version" $pod $man`;
    }

    $pod = 'scripts/jspell-installdic.in';
    $man = catfile('blib','bindoc','jspell-installdic.1');
    unless ($self->up_to_date($pod, $man)) {
        `pod2man --section=1 --center="Lingua::Jspell" --release="Lingua-Jspell-$version" $pod $man`;
    }
}

sub ACTION_create_objects {
    my $self = shift;
    my $cbuilder = $self->cbuilder;

    my $c_files = $self->rscan_dir('src', qr/\.c$/);
    for my $file (@$c_files) {
        my $object = $file;
        $object =~ s/\.c/.o/;
        next if $self->up_to_date($file, $object);
        $cbuilder->compile(object_file  => $object,
                           source       => $file,
                           include_dirs => ["src"],
                           extra_compiler_flags => $self->notes('ccurses'));
    }
}


sub ACTION_create_binaries {
    my $self = shift;
    my $cbuilder = $self->cbuilder;

    my $EXEEXT = $Config::AutoConf::EXEEXT;

    my ($LD,$CCL) = Config::AutoConf::Linker::detect_library_link_commands($cbuilder);
    die "Can't get a suitable way to compile a C library\n" if (!$LD || !$CCL);

    my $extralinkerflags = $self->notes('lcurses').$self->notes('ccurses');

    my @toinstall;
    my $exe_file = catfile("src","jspell$EXEEXT");
    push @toinstall, $exe_file;
    my $object   = catfile("src","jmain.o");
    my $libdir   = $self->install_path('usrlib');
    if (!$self->up_to_date($object, $exe_file)) {
        $CCL->($cbuilder,
               exe_file => $exe_file,
               objects  => [ $object ],
               ($^O !~ /darwin/)?
               (extra_linker_flags => "-Lsrc -Wl,-R${libdir} -ljspell $extralinkerflags"):
               (extra_linker_flags => "-Lsrc -ljspell $extralinkerflags"));
    }

    $exe_file = catfile("src","jbuild$EXEEXT");
    push @toinstall, $exe_file;
    $object   = catfile("src","jbuild.o");
    if (!$self->up_to_date($object, $exe_file)) {
        $CCL->($cbuilder,
               exe_file => $exe_file,
               objects  => [ $object ],
               ($^O !~ /darwin/)?
               (extra_linker_flags => "-Lsrc -Wl,-R${libdir} -ljspell $extralinkerflags"):
               (extra_linker_flags => "-Lsrc -ljspell $extralinkerflags"));
    }


    for my $file (@toinstall) {
        $self->copy_if_modified( from    => $file,
                                 to_dir  => "blib/bin",
                                 flatten => 1);
    }
}

sub ACTION_create_library {
    my $self = shift;
    my $cbuilder = $self->cbuilder;

    my $LIBEXT = $Config::AutoConf::LIBEXT;

    my @files = qw!correct defmt dump gclass good hash jjflags
                   jslib jspell lookup makedent sc-corr term
                   tgood tree vars xgets y.tab!;

    my @objects = map { catfile("src","$_.o") } @files;

    my ($LD,$CCL) = Config::AutoConf::Linker::detect_library_link_commands($cbuilder);
    die "Can't get a suitable way to compile a C library\n" if (!$LD || !$CCL);

    my $libpath = $self->notes('libdir');
    $libpath = catfile($libpath, "libjspell$LIBEXT");
    my $libfile = catfile("src","libjspell$LIBEXT");

    my $extralinkerflags = $self->notes('lcurses').$self->notes('ccurses');
    $extralinkerflags.=" -install_name $libpath" if $^O =~ /darwin/;

    if (!$self->up_to_date(\@objects, $libfile)) {
        $LD->($cbuilder,
              module_name => 'libjspell',
              extra_linker_flags => $extralinkerflags,
              objects => \@objects,
              lib_file => $libfile,
             );
    }

    my $libdir = catdir($self->blib, 'usrlib');
    mkpath( $libdir, 0, 0777 ) unless -d $libdir;

    $self->copy_if_modified( from   => $libfile,
                             to_dir => $libdir,
                             flatten => 1 );
}

sub ACTION_test {
    my $self = shift;

    if ($^O =~ /mswin32/i) {
        $ENV{PATH} = catdir($self->blib,"usrlib").";$ENV{PATH}";
    } elsif ($^O =~ /darwin/i) {
        $ENV{DYLD_LIBRARY_PATH} = catdir($self->blib,"usrlib");
    }
    elsif ($^O =~ /(?:linux|bsd|sun|sol|dragonfly|hpux|irix)/i) {
        $ENV{LD_LIBRARY_PATH} = catdir($self->blib,"usrlib");
    }
    elsif ($^O =~ /aix/i) {
        my $oldlibpath = $ENV{LIBPATH} || '/lib:/usr/lib';
        $ENV{LIBPATH} = catdir($self->blib,"usrlib").":$oldlibpath";
    }

    $self->SUPER::ACTION_test
}


sub _interpolate {
    my ($from, $to, %config) = @_;
	
    print "Creating new '$to' from '$from'.\n";
    open FROM, $from or die "Cannot open file '$from' for reading.\n";
    open TO, ">", $to or die "Cannot open file '$to' for writing.\n";
    while (<FROM>) {
        s/\[%\s*(\S+)\s*%\]/$config{$1}/ge;		
        print TO;
    }
    close TO;
    close FROM;
}


1;
