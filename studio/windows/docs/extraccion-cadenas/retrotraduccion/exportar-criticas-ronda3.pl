use strict; use warnings; use utf8;
binmode(STDOUT, ':encoding(UTF-8)');

# Segunda ronda de retrotraducción a ciegas (ST-247, B7d).
#
#   perl exportar-criticas-ronda3.pl <cultura> [<cultura>...]
#
# Exporta las claves CRÍTICAS QUE NO ESTUVIERON EN LA PRIMERA RONDA. No se
# reexporta lo ya revisado: el mecánico compara contra su propio trabajo de B7c
# y volver a mandárselo solo serviría para que lo lea dos veces.
#
# Los ids empiezan en e001 — la 'e' de esta ronda. Ya hubo c001… en B7c y
# d001… en la ronda 2; una fila e012 no se puede confundir con ninguna de las
# dos.
#
# Esta ronda existe porque la segunda barrida (barrida-frases.pl) encontró
# familias críticas que el trinquete no contaba: las razones por las que NO se
# escribe en el disco, el conmutador de firmware y la escritura del árbol.
#
# Los ids se derivan de la lista ESPAÑOLA ordenada y no cambian entre idiomas.
# Un idioma con más formas de plural que el español abre la fila de `.other` en
# las suyas (`<id>.few`, `<id>.many`); uno con menos —el japonés no tiene
# equivalente para `.one`— sencillamente no emite esa fila. No es un error: en
# japonés esa frase es una sola.

my $source = 'AuraStudio.Core/Resources/CriticalStrings.cs';
open(my $sh, '<:encoding(UTF-8)', $source) or die "$source: $!";
my $code = do { local $/; <$sh> }; close $sh;

my @prefixes;
while ($code =~ m{^\s*\("([^"]+)",\s*"[^"]*"\),\s*$}gm) { push @prefixes, $1 }
die "no se encontró ningún prefijo en $source\n" unless @prefixes;

sub values_of {
    my ($path) = @_;
    open(my $fh, '<:raw', $path) or die "$path: $!";
    my $xml = do { local $/; <$fh> }; close $fh;
    utf8::decode($xml);
    my %values;
    while ($xml =~ m{<data name="([^"]+)"[^>]*>\s*<value>(.*?)</value>}gs) {
        my ($name, $value) = ($1, $2);
        for ($value) { s/&lt;/</g; s/&gt;/>/g; s/&amp;/&/g; }
        $values{$name} = $value;
    }
    return \%values;
}

sub quoted {
    my ($value) = @_;
    return $value unless $value =~ /[",\n]/;
    (my $escaped = $value) =~ s/"/""/g;
    return qq{"$escaped"};
}

# Lo que ya se revisó en B7c.
my %already;
for my $map ('mapa-criticas.csv', 'mapa2-criticas.csv') {
    my $file = "docs/extraccion-cadenas/retrotraduccion/$map";
    open(my $mh, '<:encoding(UTF-8)', $file) or die "$file: $!";
    <$mh>;
    while (my $line = <$mh>) {
        chomp $line;
        my (undef, $key) = split(/,/, $line, 2);
        $already{$key} = 1 if $key;
    }
    close $mh;
}
die "los mapas de las rondas anteriores están vacíos\n" unless %already;

my $spanish = values_of('AuraStudio.Core/Strings/Resources.resx');
my @critical = sort grep {
    my $key = $_;
    !$already{$key} && grep { index($key, $_) == 0 } @prefixes;
} keys %$spanish;

die "no hay claves críticas nuevas que exportar\n" unless @critical;

my %id;
$id{$critical[$_]} = sprintf("e%03d", $_ + 1) for 0 .. $#critical;

my $dir = 'docs/extraccion-cadenas/retrotraduccion';
open(my $map, '>:encoding(UTF-8)', "$dir/mapa3-criticas.csv") or die $!;
print $map "id,clave\n";
print $map "$id{$_},$_\n" for @critical;
close $map;
print "escrito: $dir/mapa3-criticas.csv (" . scalar(@critical) . " claves)\n";

for my $culture (@ARGV) {
    my $translated = values_of("AuraStudio.Core/Strings/Resources.$culture.resx");
    my $path = "$dir/criticas3-$culture.csv";

    open(my $out, '>:encoding(UTF-8)', $path) or die "$path: $!";
    print $out "id,$culture\n";

    my $rows = 0;
    for my $key (@critical) {
        if (exists $translated->{$key}) {
            print $out "$id{$key}," . quoted($translated->{$key}) . "\n";
            $rows++;
            next;
        }

        die "falta $key en $culture y no es una forma de plural\n"
            unless $key =~ /^(.*)\.(one|other)$/;

        my ($basis, $spanishForm) = ($1, $2);

        my @forms = $spanishForm eq 'one'
            ? grep { exists $translated->{"$basis.$_"} } ('one')
            : grep { exists $translated->{"$basis.$_"} } ('few', 'many', 'other');

        my $found = 0;
        for my $form (@forms) {
            print $out "$id{$key}.$form," . quoted($translated->{"$basis.$form"}) . "\n";
            $rows++;
            $found++;
        }
        die "falta $key en $culture y el idioma no tiene ninguna forma de plural\n"
            unless $found || $spanishForm eq 'one';
    }
    close $out;
    print "escrito: $path ($rows filas)\n";
}
