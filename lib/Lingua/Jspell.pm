package Lingua::Jspell;

use warnings;
use strict;

use POSIX qw(locale_h);
setlocale(LC_CTYPE, "pt_PT");
use locale;

use base 'Exporter';
our @EXPORT_OK = (qw.onethat verif nlgrep setstopwords ok any2str hash2str.);
our %EXPORT_TAGS = (basic => [qw.onethat verif ok any2str hash2str.],
                    greps => [qw.nlgrep setstopwords.]);

use File::Which qw/which/;
use IPC::Open3;

=head1 NAME

Lingua::Jspell - Perl interface to the Jspell morphological analyser.

=cut

our $VERSION = '1.50';
our $JSPELL;
our $JSPELLLIB;
our $MODE = { nm => "af", flags => 0 };
our $DELIM = '===';
our %STOP =();

BEGIN {
  # Search for jspell binary.
  $JSPELL = which("jspell");
  my $JSPELLDICT = which("jspell-dict");
  if (!$JSPELL) {
	# check if we are running under make test
	$JSPELL = "blib/script/jspell";
	$JSPELLDICT = "blib/script/jspell-dict";
	$JSPELL = undef unless -e $JSPELL;
  }
  die "jspell binary cannot be found!\n" unless -e $JSPELL;

  chomp($JSPELLLIB = `$JSPELLDICT --dic-dir`);
}

=head1 SYNOPSIS

    use Lingua::Jspell;

    my $dic = Lingua::Jspell->new( "dict_name");
    my $dic = Lingua::Jspell->new( "dict_name" , "personal_dict_name");

    $dict->rad("gatinho");      # list of radicals (gato)

    $dict->fea("gatinho");      # list of possible analysis

    $dict->der("gato");         # list of derivated words

    $dict->flags("gato");       # list of roots and flags

=head1 FUNCTIONS

=head2 new

Use to open a dictionary. Pass it the dictionary name and optionally a
personal dictionary name. A new jspell dictionary object will be
returned.

=cut

sub new {
  my ($self, $dr, $pers, $flag);
  local $/="\n";
  my $class = shift;

  $self->{dictionary} = shift;
  $self->{pdictionary} = shift ||
    (defined($ENV{HOME})?"$ENV{HOME}/.jspell.$self->{dictionary}":"");

  $pers = $self->{pdictionary}?"-p $self->{pdictionary}":"";
  $flag = defined($self->{'undef'})?$self->{'undef'}:"-y";

  ## Get meta info
  my $meta_file = _meta_file($self->{dictionary});
  if (-f $meta_file) {
    open META, $meta_file or die "$!";
    while(<META>) {
      next if m!^\s*$!;
      next if m!^\s*#!;
      s!#.*$!!;
      if (m!^(\w+):\s*(.*)!) {
        $self->{meta}{_}{$1} = $2;
      }
      if (m!^(\w+)=(\w+):\s*(.*)!) {
        $self->{meta}{$1}{$2} = $3;
      }
    }
    close META;
  } else {
    $self->{meta} = {};
  }

  $self->{pid} = open3($self->{DW},$self->{DR},$self->{DE},
		       "$JSPELL -d $self->{dictionary} -a $pers -W 0 $flag -o'%s!%s:%s:%s:%s'") ||
			 die "Cannot find 'jspell'";
  binmode($self->{DW},":bytes");
  binmode($self->{DR},":bytes");
  $dr = $self->{DR};
  my $first_line = <$dr>;

  $self->{mode} ||= $MODE;
  my $dw = $self->{DW};
  print $dw _mode($self->{mode});

  if ($first_line  =~ /Jspell/) { return bless $self, $class }  #amen
  else                          { return undef}
}

=head2 setmode

=cut

sub setmode {
  my ($self, $mode) = @_;

  my $dw = $self->{DW};
  if (defined($mode)) {
    $self->{mode} = $mode;
    print $dw _mode($mode);
  } else {
    return $self->{mode}
  }
}

=head2 fea

Returns a list of analisys of a word. Each analisys is a list of
attribute value pairs. Attributes available: CAT, T, G, N, P, ....

  @l = $dic->fea($word)

=cut


sub fea{
  my ($self,$w) = @_;

  local $/="\n";

  my @r = ();
  my ($a, $rad, $cla, $flags);

  return () if $w =~ /\!/;

  my ($dw,$dr) = ($self->{DW},$self->{DR});

  print $dw " $w\n";
  $a = <$dr>;

  for (;($a ne "\n"); $a=<$dr>) {       # l^e as respostas
    for($a){
      chop;
      my ($lixo,$clas);
      if(/(.*?) :(.*)/){$clas = $2 ; $lixo =$1}
      else             {$clas = $_ ; $lixo =""}

      for(split(/[,;] /,$clas)){
        ($rad,$cla)= m{(.+?)\!:*(.*)$};

	# Não sei porquê, mas acontece por vezes de $cla ser 'undef'
	# Não sei bem o que devemos fazer... de momento, estou simplesmente
	# a passar o código à frente.
	if ($cla) {
	  if ($cla =~ s/\/(.*)$//) { $flags = $1 }
	  else                     { $flags = "" }

	  $cla =~ s/:+$//g;
	  $cla =~ s/:+/,/g;

	  my %ana;
	  my @attrs = split /,/, $cla;
	  for (@attrs) {
	    if (m!=!) {
	      $ana{$`}=$';
	    } else {
	      print STDERR "** WARNING: Feature-structure parse error: $cla (for word '$w')\n";
	    }
	  }

	  $ana{"flags"} = $flags if $flags;

	  if ($lixo =~ /^&/) {
	    $rad =~ s/(.*?)= //;
	    $ana{"guess"} = lc($1);
	    $ana{"unknown"} = 1;
	  }
	  if ($rad ne "" ) {
	    push(@r,+{"rad" => $rad, %ana});
	  }
	}
      }
    }
  }
  return @r;
}

=head2 flags

=cut

sub flags {
  my $self = shift;
  my $w = shift;
  my ($a,$dr);
  local $/="\n";

  print {$self->{DW}} "\$\"$w\n";
  $dr = $self->{DR};
  $a = <$dr>;

  chop $a;
  return split(/[# ,]+/,$a);
}

=head2 rad

Returns the list of all possible radicals/lemmas for the supplied word.

  @l = $dic->rad($word)

=cut

sub rad {
  my $self = shift;
  my $word = shift;

  return () if $word =~ /\!/;

  my %rad = ();
  my $a_ = "";
  local $/ = "\n";

  my ($dw,$dr) = ($self->{DW},$self->{DR});

  print $dw " $word\n";

  for ($a_ = <$dr>; $a_ ne "\n"; $a_ = <$dr>) {
    chop $a_;
    %rad = ($a_ =~ m/(?: |:)([^ =:,!]+)(\!)/g ) ;
  }

  return (keys %rad);
}


=head2 der

Returns the list of all possible words using the word as radical.

  @l = $dic->der($word);

=cut

sub der {
  my ($self, $w) = @_;
  my @der = $self->flags($w);
  my %res = ();
  my $command;

  $command = sprintf("echo '%s'|$JSPELL -d $self->{dictionary} -e -o '' ",join("\n",@der));

  local $/ = "\n";

  for (`$command`) {
    chop;
    s/(=|, | $)//g;
    for(split) { $res{$_}++; }
  }

  my $irrcomm;

  # This need to be tested
  my $irr_file = _irr_file($self->{dictionary});
  $irrcomm = sprintf("grep '^%s=' $irr_file",$w);

  for (`$irrcomm`){
    chop;
    for (split(/[= ]+/,$_)) { $res{$_}++; }
  }

  return keys %res;
}

=head2 onethat

Returns the first Feature Structure from the supplied list that
verifies the Feature Structure Pattern used.

   $analysis = onethat( { CAT=>'adj' }, @features);

=cut

sub onethat {
  my ($a, @b) = @_;
  for (@b) {
    return %$_ if verif($a,$_);
  }
  return () ;
}

=head2 verif

Retuurns a true value if the second Feature Structure verifies the
first Feature Structure Pattern.

   if (verif( $pattern, $feature) )  { ... }

=cut

sub verif {
  my ($a, $b) = @_;
  for (keys %$a) {
    return 0 if (!defined($b->{$_}) || $a->{$_} ne $b->{$_}); 
  }
  return 1;
}

=head2 nlgrep

=cut

sub nlgrep {
  # max=int, sep:str, radtxt:bool
  my %opt = (max=>10000, sep => "\n",radtxt=>0);
  %opt = (%opt,%{shift(@_)}) if ref($_[0]) eq "HASH";

  my $p = shift;

  my $pattern = $opt{radtxt} ? $p : join("|",(der($p)));
  my $p2 = qr/\b(?:$pattern)\b/i;

  my @file_list=@_;
  local $/=$opt{sep};

  my @res=();
  my $n = 0;
  for(@file_list) {
    open(F,$_) or die("cant open $_\n");
    while(<F>) {
      # if(/\b(?:$pattern)\b/io){}
      if (/$p2/) {
        chomp;
        s/$DELIM.*//g if $opt{radtxt};
        push(@res,$_);
        last if $n++ == $opt{max};
      }
    }
    close F;
    last if $n == $opt{max};
  }
  return @res;
}

=head2 setstopwords

=cut

sub setstopwords {
  $STOP{$_} = 1 for @_;
}

=head2 cat2small

Note: This function is specific for the Portuguese jspell dictionary

=cut

# NOTA: Esta funcao é específica da língua TUGA!
sub _cat2small {
  my %b = @_;

  if ($b{'CAT'} eq 'art') {
    # Artigos: o léxico já prevê todos...
    # por isso, NUNCA SE DEVE CHEGAR AQUI!!!
    return "ART";
    # 16 tags

  } elsif ($b{'CAT'} eq 'card') {
    # Numerais cardinais:
    return "DNCNP";
    # o léxico já prevê os que flectem (1 e 2); o resto é tudo neutro plural.

  } elsif ($b{'CAT'} eq 'nord') {
    # Numerais ordinais:
    return "\UDNO$b{'G'}$b{'N'}";

  } elsif ($b{'CAT'} eq 'ppes' || $b{'CAT'} eq 'prel' ||
           $b{'CAT'} eq 'ppos' || $b{'CAT'} eq 'pdem' ||
           $b{'CAT'} eq 'pind' || $b{'CAT'} eq 'pint') {
    # Pronomes:
    if ($b{'CAT'} eq 'ppes') {
      # Pronomes pessoais
      $b{'CAT'} = 'PS';
    } elsif ($b{'CAT'} eq 'prel') {
      # Pronomes relativos
      $b{'CAT'} = 'PR';
    } elsif ($b{'CAT'} eq 'ppos') {
      # Pronomes possessivos
      $b{'CAT'} = 'PP';
    } elsif ($b{'CAT'} eq 'pdem') {
      # Pronomes demonstrativos
      $b{'CAT'} = 'PD';
    } elsif ($b{'CAT'} eq 'pint') {
      # Pronomes interrogativos
      $b{'CAT'} = 'PI';
    } elsif ($b{'CAT'} eq 'pind') {
      # Pronomes indefinidos
      $b{'CAT'} = 'PF';
    }

    $b{'G'} = 'N' if $b{'G'} eq '_';
    $b{'N'} = 'N' if $b{'N'} eq '_';

    return "\U$b{'CAT'}$b{'C'}$b{'G'}$b{'P'}$b{'N'}";
    #                        $b{'C'}: caso latino.

  } elsif ($b{'CAT'} eq 'nc') {
    # Nomes comuns:
    $b{'G'} = 'N' if $b{'G'} eq '_' || $b{'G'} eq '';
    $b{'N'} = 'N' if $b{'N'} eq '_' || $b{'N'} eq '';
    return "\U$b{'CAT'}$b{'G'}$b{'N'}";

  } elsif ($b{'CAT'} eq 'np') {
    # Nomes próprios:
    $b{'G'} = 'N' if $b{'G'} eq '_' || $b{'G'} eq '';
    $b{'N'} = 'N' if $b{'N'} eq '_' || $b{'N'} eq '';
    return "\U$b{'CAT'}$b{'G'}$b{'N'}";

  } elsif ($b{'CAT'} eq 'adj') {
    # Adjectivos:
    $b{'G'} = 'N' if $b{'G'} eq '_';
    $b{'G'} = 'N' if $b{'G'} eq '2';
    $b{'N'} = 'N' if $b{'N'} eq '_';
    #    elsif ($b{'N'} eq ''){
    #      $b{'N'} = 'N';
    #    }
    return "\UJ$b{'G'}$b{'N'}";

  } elsif ($b{'CAT'} eq 'a_nc') {
    # Adjectivos que podem funcionar como nomes comuns:
    $b{'G'} = 'N' if $b{'G'} eq '_';
    $b{'G'} = 'N' if $b{'G'} eq '2';
    $b{'N'} = 'N' if $b{'N'} eq '_';
    #    elsif ($b{'N'} eq ''){
    #      $b{'N'} = 'N';
    #    }
    return "\UX$b{'G'}$b{'N'}";

  } elsif ($b{'CAT'} eq 'v') {
    # Verbos:

    # formas nominais:
    if ($b{'T'} eq 'inf') {
      # infinitivo impessoal
      $b{'T'} = 'N';

    } elsif ($b{'T'} eq 'ppa') {
      # Particípio Passado
      $b{'T'} = 'PP';

    } elsif ($b{'T'} eq 'g') {
      # Gerúndio
      $b{'T'} = 'G';

    } elsif ($b{'T'} eq 'p') {
      # modo indicativo: presente (Hoje)
      $b{'T'} = 'IH';

    } elsif ($b{'T'} eq 'pp') {
      # modo indicativo: pretérito Perfeito
      $b{'T'} = 'IP';

    } elsif ($b{'T'} eq 'pi') {
      # modo indicativo: pretérito Imperfeito
      $b{'T'} = 'II';

    } elsif ($b{'T'} eq 'pmp') {
      # modo indicativo: pretérito Mais-que-perfeito
      $b{'T'} = 'IM';

    } elsif ($b{'T'} eq 'f') {
      # modo indicativo: Futuro
      $b{'T'} = 'IF';

    } elsif ($b{'T'} eq 'pc') {
      # modo conjuntivo (Se): presente (Hoje)
      $b{'T'} = 'SH';

    } elsif ($b{'T'} eq 'pic') {
      # modo conjuntivo (Se): pretérito Imperfeito
      $b{'T'} = 'SI';

    } elsif ($b{'T'} eq 'fc') {
      # modo conjuntivo (Se): Futuro
      $b{'T'} = 'PI';

    } elsif ($b{'T'} eq 'i') {
      # modo Imperativo: presente (Hoje)
      $b{'T'} = 'MH';

    } elsif ($b{'T'} eq 'c') {
      # modo Condicional: presente (Hoje)
      $b{'T'} = 'CH';

    } elsif ($b{'T'} eq 'ip') {
      # modo Infinitivo (Pessoal ou Presente): 
      $b{'T'} = 'PI';

      # Futuro conjuntivo? Só se tiver um "se" antes! -> regras sintácticas...
      # modo&tempo não previstos ainda...

    } else {
      $b{'T'} = '_UNKNOWN';
    }

    # converter 'P=1_3' em 'P=_': provisório(?)!
    $b{'P'} = '_' if $b{'P'} eq '1_3'; # único sítio com '_' como rhs!!!

    return "\U$b{'CAT'}$b{'T'}$b{'G'}$b{'P'}$b{'N'}";
    #                               Género, só para VPP.
    # +/- 70 tags

  } elsif ($b{'CAT'} eq 'prep') {
    # Preposições¹:
    return "\UP";

  } elsif ($b{'CAT'} eq 'adv') {
    # Advérbios²:
    return "\UADV";

  } elsif ($b{'CAT'} eq 'con') {
    # Conjunções²:
    return "\UC";

  } elsif ($b{'CAT'} eq 'in') {
    # Interjeições¹:
    return "\UI";

    # ¹: não sei se a tag devia ser tão atómica, mas para já não há confusão!

  } elsif ($b{'CAT'} =~ m/^cp(.*)/) {
    # Contracções¹:
    $b{'G'} = 'N' if $b{'G'} eq '_';
    $b{'N'} = 'N' if $b{'N'} eq '_';
    return "\U&$b{'G'}$b{'N'}";

    # ²: falta estruturar estes no próprio dicionário...
    # Palavras do dicionário com categoria vazia ou sem categoria,
    # palavras não existentes ou sequências aleatórias de caracteres:

  } elsif ($b{'CAT'} eq '') {
    return "\UUNDEFINED";

  } else {   # restantes categorias (...?)
    return "\UUNTREATED";
  }
}

=head2 featags

=cut

sub featags{
  my ($self, $palavra) = @_;
  return (map {_cat2small(%$_)} ($self->fea($palavra)));
}

=head2 ok

 # ok: cond:fs x ele:fs-set -> bool
 # exist x in ele : verif(cond , x)

=cut

sub ok {
  my ($a, @b) = @_;
  for (@b) {
    return 1 if verif($a,$_);
  }
  return 0 ;
}

=head2 mkradtxt

=cut

sub mkradtxt {
  my ($self, $f1, $f2) = @_;
  open F1, $f1 or die "Can't open '$f1'\n";
  open F2, "> $f2" or die "Can't create '$f2'\n";
  while(<F1>) {
    chomp;
    print F2 "$_$DELIM";
    while (/((\w|-)+)/g) {
      print F2 " ",join(" ",$self->rad($1)) unless $STOP{$1}
    }
    print F2 "\n";
  }
  close F1;
  close F2;
}

=head2 any2str

=cut

sub any2str {
  my ($r, $i) = @_;
  $i ||= 0;
  if ($i eq "compact") {
    if (ref($r) eq "HASH") {
      return "{". hash2str($r,$i) . "}"
    } elsif (ref($r) eq "ARRAY") {
      return "[" . join(",", map (any2str($_,$i), @$r)) . "]" 
    } else {
      return "$r"
    }
  } else {
    my $ind = ($i >= 0)? (" " x $i) : "";
    if (ref($r) eq "HASH") {
      return "$ind {". hash2str($r,abs($i)+3) . "}"
    } elsif (ref($r) eq "ARRAY") {
      return "$ind [\n" . join("\n", map (any2str($_,abs($i)+3), @$r)) . "]"
    } else {
      return "$ind$r"
    }
  }
}

=head2 hash2str

=cut

sub hash2str {
  my ($r, $i) = @_;
  my $c = "";
  if ($i eq "compact") {
    for (keys %$r) {
      $c .= any2str($_,$i). "=". any2str($r->{$_},$i). ",";
    }
    chop($c);
  } else {
    for (keys %$r) {
      $c .= "\n". any2str($_,$i). " => ". any2str($r->{$_},-$i);
    }
  }
  return $c;
}

=head1 AUTHOR

Jose Joao Almeida, C<< <jj@di.uminho.pt> >>
Alberto Simões, C<< <ambs@di.uminho.pt> >>

=head1 BUGS

Please report any bugs or feature requests to
C<bug-lingua-jspell@rt.cpan.org>, or through the web interface at
L<http://rt.cpan.org/NoAuth/ReportBug.html?Queue=Lingua-Jspell>.  I
will be notified, and then you'll automatically be notified of
progress on your bug as I make changes.

=head1 COPYRIGHT & LICENSE

Copyright 2007-2008 Projecto Natura

This program is free software; licensed undef GPL.

=cut

sub _meta_file {
  my $dic_file = shift;
  if ($dic_file =~ m!\.hash$!) {
    # we have a local dictionary
    $dic_file =~ s/\.hash/.meta/;
  } else {
    $dic_file = "$JSPELLLIB/$dic_file.meta"
  }
  return $dic_file;
}

sub _mode {
  my $m = shift;
  my $r="";
  if ($m->{nm}) {
    if ($m->{nm} eq "af")
      { $r .= "\$G\n\$P\n\$y\n" }
    elsif ($m->{nm} eq "full")
      { $r .= "\$G\n\$Y\n\$m\n" }
    elsif ($m->{nm} eq "cc")
      { $r .= "\$G\n\$P\n\$Y\n" }
    else {}
  }
  if ($m->{flags})          {$r .= "\$z\n"}
  else                      {$r .= "\$Z\n"}
  return $r;
}


sub _irr_file {
  my $irr_file = shift;
  if ($irr_file =~ m!\.hash$!) {
    # we have a local dictionary
    $irr_file =~ s/\.hash/.irr/;
  } else {
    $irr_file = "$JSPELLLIB/$irr_file.irr"
  }
  return $irr_file;
}



1; # End of Lingua::Jspell

__END__


# sub nlgrepold {
#   my $proc=shift;
#   my $file_list=join(' ',@_);
#   local $/="\n";

#   open(TMPp,"> $tmp/_jspell$$") || die(" can't open tmp ");
#   for (der($proc)) { print TMPp "$_\n" unless $STOP{$_}; }
#   close(TMPp);

#   my @res=();
#   for (`$agrep -h -i -w -f $tmp/_jspell$$ $file_list`) {
#     push(@res,$_);
#   }
#   unlink "$tmp/_jspell$$";
#   @res;
# }

# sub nlgrepold2 {
#   my $p=shift;
#   my %opt=();           # max=int, sep:str, radtxt:bool
#   if(ref($p) eq "HASH"){
#     %opt=%$p;
#     $p=shift}

#   my $file_list=join(' ',@_);
#   local $/=$opt{sep} || "\n";

#   my $max="";
#   $max = "|head -$opt{max}" if $opt{'max'};
#   my $sep="";
#   $sep = "-d '$opt{sep}' -t " if $opt{sep};

#   unless($opt{radtxt}){
#     open(TMPp,"> $tmp/_jspell$$") || die(" can't open tmp ");
#     for (der($p)) { print TMPp "$_\n" unless $STOP{$_}; }
#     close(TMPp);
#   }

#   my @res=();
#   if(defined $opt{radtxt}){
#     for (`$agrep -h -i -w '$p' $file_list  $max`) {
#       chomp;
#       s/$DELIM.*//g;
#       push(@res,$_);
#     } }
#   else{
#     for (`$agrep $sep -h -i -w -f $tmp/_jspell$$ $file_list $max`) {
#       chomp;
#       push(@res,$_);
#     } }
#   unlink "$tmp/_jspell$$" unless $opt{radtxt};
#   @res;
# }

sub nlgrep1{
  my $proc = shift;
  my $file_list = join(' ',@_);
  local $/="\n";

  my @res=();
  for (`$agrep -h -i -w '$proc' $file_list`) {
    if( /(.*?)$DELIM/){ push(@res,$1) };
  }
  @res;
}

sub nlgrep3 {
  my $proc=shift;
  my $qt=shift;
  my $file_list=join(' ',@_);
  local $/="\n";

  open(TMPp,"> $tmp/_jspell$$") || die(" can't open tmp ");
  for (der($proc)) { print TMPp "$_\n" unless $STOP{$_}; }
  close(TMPp);

  my @res=();
  for (`$agrep -h -i -w -f $tmp/_jspell$$ $file_list | head -$qt`) {
    push(@res,$_);
  }
  unlink "$tmp/_jspell$$";
  @res;
}

sub nlgrep2 {
  my $proc=shift;
  my $sep=shift;
  my $file_list=join(' ',@_);
  my $a;

  open(TMPp,"> $tmp/_jspell$$") || die(" can't open tmp\n ");
  for (der($proc)) { print TMPp "$_\n" unless $STOP{$_}; }
  close(TMPp);

  my @res=();
  local $/=$sep;
  open(TMPp,"$agrep -d '$sep' -h -i -w -f $tmp/_jspell$$ $file_list | ") or
    die "cant agrep :-((";

  while ($a=<TMPp>){
    chomp($a);
    push(@res,$a);
  }
  close(TMPp);
  unlink "$tmp/_jspell$$";
  @res;
}

# Esta funcao precisa de ser re-escrita para tirar partido dos
# ficheiros .meta
sub show_fea {
  my $struct = shift;
  for (keys %$struct) {

    if (/^N$/) {
      print "Number: ",(($struct->{$_} eq "p")?"plural":"singular"),"\n";
      next;
    }

    if (/^G$/) {
      print "Genre: ",(($struct->{$_} eq "m")?"masculine":"feminine"),"\n";
      next;
    }

    if (/^CAT$/) {
      my %significado = (
			 nc => 'common name',
			 adj => 'adjective',
			 a_nc => 'common_name / adjective',
			 adv => 'adverb',
			 prep => 'preposition',
			 in => '??',
			 v => 'verb',
			 pind => '??',
			 con => '??',
			 cp => '??',
			);
      print "Categorie: ",$significado{$struct->{$_}},"\n";
      next;
    }

    print "$_ => $struct->{$_}\n";
  }
}
