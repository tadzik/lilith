package Lilith::KeyGuesser;
use 5.010;
use strict;
use Carp;
use constant {
    FIS => 1,
    CIS => 2, DES => 2,
    GIS => 4, AS => 4,
    DIS => 8, ES => 8,
    B  => 16,
};

my @keys;
$keys[0]                     = ['C', 'a'];

$keys[FIS]                   = ['G', 'e'];
$keys[FIS | CIS]             = ['D', 'h'];
$keys[FIS | CIS | GIS]       = ['A', 'f#'];
$keys[FIS | CIS | GIS | DIS] = ['E', 'c#'];

$keys[B]                     = ['F', 'd'];
$keys[B | ES]                = ['B', 'g'];
$keys[B | ES | AS]           = ['Eb', 'c'];
$keys[B | ES | AS | DES]     = ['G#', 'f'];

# given the list of MIDI::Events try to guess the tuning used (defaults to C/a is not known)
sub guess {
    sub wins {
        my ($first, $second) = @_;
        return $first > $second;
    }

    my @note_freq;
    for (grep { $_->[0] eq 'note_on' } @_) {
        $note_freq[$_->[3] % 12]++
    }

    my $tuning;
    if (wins($note_freq[6], $note_freq[5])) {
        $tuning |= FIS;
    }
    if (wins($note_freq[1], $note_freq[0])) {
        $tuning |= CIS;
    }
    if (wins($note_freq[8], $note_freq[7])) {
        $tuning |= GIS;
    }
    if (wins($note_freq[3], $note_freq[2])) {
        $tuning |= DIS;
    }
    
    if (wins($note_freq[10], $note_freq[11])) {
        $tuning |= B;
    }
    if (wins($note_freq[1], $note_freq[2])) {
        $tuning |= DES;
    }
    if (wins($note_freq[3], $note_freq[4])) {
        $tuning |= ES;
    }
    if (wins($note_freq[8], $note_freq[9])) {
        $tuning |= AS;
    }
    # TODO: Moar of these
    
    return $keys[$tuning] // ['C', 'a']
}

1;
