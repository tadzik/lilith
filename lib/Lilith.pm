package Lilith;
use 5.010;
use strict;
use warnings;
use Lilith::KeyGuesser;
use File::Temp 'tempfile';

# fun fact: it's not really a mean =)
# a real mean yields idiotic results, when it happens to compute average time of 1/8 and 1/4
sub mean {
    my @arr = @_;
    my $idx = int($#arr / 2);
    return $arr[$idx];
}

my @sounds = (
    'c',   # 0
    'cis', # 1
    'd',   # 2
    'dis', # 3
    'e',   # 4
    'f',   # 5
    'fis', # 6
    'g',   # 7
    'gis', # 8
    'a',   # 9
    'ais', # 10
    'b',   # 11
);

my @octaves = (
   ",,,,", # 0
   ",,,",  # 1
   ",,",   # 2
   ",",    # 3
   "",     # 4
   "'",    # 5
   "''",   # 6
   "'''",  # 7
   "''''", # 8
);

sub idx2sound {
    return $sounds[shift() % 12]
}

sub idx2octave {
    return $octaves[int(shift() / 12)]
}

sub get_notes {
    my @pressed;
    my @notes;
    my $currenttime = 0;
    for (@_) {
        $currenttime += $_->[1];
        if ($_->[0] eq 'note_on') {
            my $note = { idx => $_->[3], start => $currenttime };
            $pressed[$_->[3]] = $note;
            push @notes, $note;
        } elsif ($_->[0] eq 'note_off') {
            my $note = $pressed[$_->[3]];
            $note->{duration} = $currenttime - $note->{start};
            $note->{end} = $note->{start} + $note->{duration};
        }
    }
    my $base = mean(map { $_->{duration} } @notes);
    for (@notes) {
        my $ratio = $_->{duration} / $base;
        if ($ratio < 0.75) { # more 1/2 than 1
            $_->{type} = 8;
        } elsif ($ratio < 1.5) {
            $_->{type} = 4;
        } elsif ($ratio < 2.5) {
            $_->{type} = 2;
        } else {
            $_->{type} = '2.';
        }
        $_->{octave} = idx2octave($_->{idx});
        $_->{sound} = idx2sound($_->{idx});
    }
    my @withrests = $notes[0];
    for my $i (1..@notes-1) {
        my $rtime = $notes[$i]->{start} - $notes[$i - 1]->{end};
        my $ratio = $rtime / $base;
        if ($ratio > 0.25) {
            my $rest = { idx => -1, start => $notes[$i - 1]->{end},
                         end => $notes[$i]->{start}, duration => $rtime,
                         sound => 'r', octave => '',
                       };
            if ($ratio < 0.75) { # more 1/2 than 1
                $rest->{type} = 8;
            } else {
                $rest->{type} = 4;
            }
            push @withrests, $rest;
        }
        push @withrests, $notes[$i];
    }
    # let's glue chords together
    my $threshold = $base / 16; # XXX this could be smarter
    my @endresult = [shift @withrests];
    while (@withrests) {
        my $n = shift @withrests;
        my @chord = @{pop @endresult};
        if (abs($n->{start} - $chord[0]->{start}) < $threshold) {
            push @chord, $n;
            push @endresult, \@chord;
        } else {
            push @endresult, \@chord;
            push @endresult, [$n];
        }
    }
    return @endresult;
}

sub key_signature {
    my @parts = split //, shift;
    my $mod = '\minor';
    my $key = shift @parts;
    if ($key =~ /[A-Z]/) {
        $mod = '\major';
        $key = lc $key;
    }
    my $acc = shift @parts;
    if ($acc) {
        if ($acc eq '#') {
            $key .= "is";
        } else {
            $key .= "es";
        }
    }

    return "\\key $key $mod";
}

sub note_to_lilypond {
    my $n = shift;
    sprintf "%s%s%s", $n->{sound}, $n->{octave}, $n->{type};
}

sub chord_to_lilypond {
    my $n = shift;
    my @notes = @$n;
    if (@notes > 1) { # chord
        sprintf "<< %s >>", join(" ", map({ note_to_lilypond($_) } @notes))
    } else {
        note_to_lilypond $notes[0];
    }
}

sub to_lilypond {
    my ($key, $time, $upper, $lower) = @_;
    $key = key_signature($key);
    sprintf q[\\version "2.16.2"
upper = {
    %s
    \clef "treble"
    %s
}
lower = {
    %s
    \clef "bass"
    %s
}
\score {
    \new PianoStaff <<
        \time %s
        \new Staff = "upper" \upper
        \new Staff = "lower" \lower
    >>
    \layout { }
    \midi { }
}], $key, join(" ", map { chord_to_lilypond($_) } @$upper),
    $key, join(" ", map { chord_to_lilypond($_) } @$lower),
    $time;
}

# in full notes
sub total_length {
    my $ret = 0;
    for (@_) {
        for (@$_) {
            my $part += 1 / int($_->{type});
            if ($_->{type} =~ /\.$/) {
                $part *= 1.5;
            }
            $ret += $part;
        }
    }
    return $ret
}

sub guess_tempo {
    my $quarters = total_length(@_) * 4;
    # if both it's both divisable by 3 and 4, we need a better way. TODO
    if ($quarters % 3 == 0) {
        return '3/4'
    }
    if ($quarters % 4 == 0) {
        return '4/4'
    }
    # some notes are missing at the end
    if ($quarters % 4 < $quarters % 3) {
        return '3/4';
    } else {
        return '4/4';
    }
}

sub generate {
    my ($opts, @events) = @_;
    my $key = $opts->{key} // Lilith::KeyGuesser::guess(@events)->[0];
    $ENV{VERBOSE} and warn "Guessed key: $key\n";
    my @notes = get_notes(@events);
    my $tempo = $opts->{tempo} // guess_tempo(@notes);
    $ENV{VERBOSE} and warn "Guessed tempo: $tempo\n";

    my @lower;
    for (@notes) {
        push @lower, [{
            sound => 'r',
            type => $_->[0]{type},
            octave => ''
        }]
    }

    return to_lilypond($key, $tempo, \@notes, \@lower);
}

sub generate_pdf {
    my ($pdffile, $opts) = (shift, shift);
    my $contents = generate($opts, @_);
    my ($fh, $filename) = tempfile();
    say $fh $contents;
    close $fh;
    warn "Running lilypond\n";
    system("lilypond -s -o $pdffile $filename");
    if ($opts->{keep}) {
        warn "File saved as $filename\n";
    } else {
        unlink $filename
    }
}

1;
