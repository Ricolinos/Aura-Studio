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

            # Las secuencias de escape se quitan ANTES de decidir si esto parece
            # una ruta. Un "\n" ES una barra invertida, así que la versión
            # anterior de este bloque descartaba por «ruta» toda frase con un
            # salto de línea adentro — o sea todos los textos de varios
            # renglones, que son justamente los de los diálogos.
            #
            # Así se le escapó el aviso de «algo salió mal» del reportador de
            # caídas: un ContentDialog, en pantalla, en español, con el título y
            # el botón de al lado ya sacados a recurso. Lo encontró una lectura
            # a mano, no esta herramienta, y por eso el agujero se tapa acá
            # antes de que la barrida sirva de trinquete.
            (my $bare = $value) =~ s/\\[nrt0"'\\]//g;

            next unless $bare =~ /\s/;                       # una sola palabra: no es una frase
            next if $bare =~ m{^[a-z0-9.\-]+$};              # clave de recurso
            next if $bare =~ m{[\\/]};                       # ruta
            next if $bare =~ /^\s*$/;
            next if $bare =~ /^[A-Z][A-Za-z]+ [A-Z][A-Za-z]+$/ && $bare !~ /[áéíóúñ]/;  # "Aura Studio"
            next unless $bare =~ /[a-záéíóúñ]{3,}\s+[a-záéíóúñ]{2,}/i;  # dos palabras de verdad
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
