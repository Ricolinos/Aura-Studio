use strict; use warnings; use utf8;
binmode(STDOUT, ':encoding(UTF-8)');

# Segunda opinión sobre lo que queda en español, sin la lista de palabras del
# trinquete.
#
# El trinquete decide con un léxico —"archivo", "canción", "álbum"…— y por eso
# no ve "Formatos distintos" ni "Misma duración". Esto usa otra señal: un
# literal con DOS O MÁS palabras separadas por espacio, que no parece una
# ruta, ni un identificador, ni una clave de recurso. Da más ruido y ese es el
# punto: el trinquete es un piso y esto es para leer.

my @roots = ('AuraStudio.App', 'AuraStudio.Core');
my @files;

sub collect {
    my ($dir) = @_;
    opendir(my $dh, $dir) or return;
    for my $entry (sort readdir $dh) {
        next if $entry =~ /^\.|^bin$|^obj$/;
        my $path = "$dir/$entry";
        if (-d $path) { collect($path) }
        elsif ($path =~ /\.cs$/) { push @files, $path }
    }
    closedir $dh;
}
collect($_) for @roots;

my $total = 0;
for my $path (@files) {
    open(my $fh, '<:encoding(UTF-8)', $path) or next;
    my @hits;
    while (my $line = <$fh>) {
        next if $line =~ m{^\s*//};
        next if $line =~ /Strings\.(Get|Format|Plural)\("/;

        while ($line =~ /"((?:[^"\\]|\\.)*)"/g) {
            my $value = $1;
            next unless $value =~ /\s/;                      # una sola palabra: no es una frase
            next if $value =~ m{^[a-z0-9.\-]+$};             # clave de recurso
            next if $value =~ m{[\\/]};                      # ruta
            next if $value =~ /^\s*$/;
            next if $value =~ /^[A-Z][A-Za-z]+ [A-Z][A-Za-z]+$/ && $value !~ /[áéíóúñ]/;  # "Aura Studio"
            next unless $value =~ /[a-záéíóúñ]{3,}\s+[a-záéíóúñ]{2,}/i;  # dos palabras de verdad
            push @hits, sprintf("%4d  %s", $., $value);
        }
    }
    close $fh;

    next unless @hits;
    $total += @hits;
    print "\n$path\n";
    print "$_\n" for @hits;
}

print "\n--- $total literales con pinta de frase ---\n";
