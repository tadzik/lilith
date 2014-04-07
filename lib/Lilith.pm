package Lilith;
use 5.010;
use strict;
use warnings;
use Lilith::KeyGuesser;
use File::Temp 'tempfile';
use Data::Dumper;

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

# in full notes
sub total_length {
    my $ret = 0;
    use Data::Dumper;
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

sub add_rests {
    my ($base, @notes) = @_;
    my @result = $notes[0];
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
            push @result, $rest;
        }
        push @result, $notes[$i];
    }
    return @result
}

sub glue_chords {
    my ($base, @notes) = @_;
    my $threshold = $base / 16; # XXX this could be smarter
    my @result = [shift @notes];
    while (@notes) {
        my $n = shift @notes;
        my @chord = @{pop @result};
        if (abs($n->{start} - $chord[0]->{start}) < $threshold) {
            push @chord, $n;
            push @result, \@chord;
        } else {
            push @result, \@chord;
            push @result, [$n];
        }
    }
    return @result
}

sub duration_to_type {
    my ($duration, $base) = @_;

    my $ratio = $duration / $base;

    if ($ratio < 0.75) {
        return '8'
    } elsif ($ratio < 1.5) {
        return '4'
    } elsif ($ratio < 2) {
        return '4.'
    } elsif ($ratio < 2.5) {
        return '2'
    } else {
        return '2.'
    }
}

sub divide_hands_simple {
    my (@upper, @lower);
    my $divisor = 63; # Ds5, a magical key betwen C3 and C5
    for (@_) {
        if ($_->{idx} < $divisor) {
            push @lower, $_;
        } else {
            push @upper, $_;
        }
    }
    return \@upper, \@lower
}

sub divide_hands_tracing {
    my (@upper, @lower);
    my $lastlower = 48; # C3
    my $lastupper = 74; # C5
    for (@_) {
        #print "lastlower: $lastlower, lastupper: $lastupper, current: ".$_->{idx}
        #      ." (".$MIDI::number2note{$_->{idx}}.")";
        if (abs($_->{idx} - $lastlower) < abs($_->{idx} - $lastupper)) {
            #say " ... goes lower";
            $lastlower = $_->{idx};
            push @lower, $_;
        } else {
            #say " ... goes upper";
            $lastupper = $_->{idx};
            push @upper, $_;
        }
    }
    return \@upper, \@lower
}

sub rate_hand_division {
    my ($upper, $lower) = @_;

    my $ulen = total_length($upper);
    my $llen = total_length($lower);
    if (!$ulen or !$llen) {
        # it's probably one-handed
        return -1
    }
    return abs($ulen - $llen);
}

sub divide_hands {
    # let's try both and see which is better
    my ($upper_s, $lower_s) = divide_hands_simple(@_);
    my ($upper_t, $lower_t) = divide_hands_tracing(@_);
    # lower is better
    my $score_s = rate_hand_division($upper_s, $lower_s);
    my $score_t = rate_hand_division($upper_t, $lower_t);
    #say "Score for simple  method: $score_s";
    #say "Score for tracing method: $score_t";

    if ($score_s < $score_t) {
        #say "Simple wins";
        return $upper_s, $lower_s
    } else {
        #say "Tracing wins";
        return $upper_t, $lower_t
    }
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
    unless (@notes) {
        die "File appears to be empty"
    }
    my $base = mean(map { $_->{duration} } @notes);

    for (@notes) {
        $_->{type} = duration_to_type($_->{duration}, $base);
        $_->{octave} = idx2octave($_->{idx});
        $_->{sound} = idx2sound($_->{idx});
    }
    my ($u, $l) = divide_hands(@notes);
    my @upper = @$u;
    my @lower = @$l;
    @upper = add_rests($base, @upper) if @upper;
    @lower = add_rests($base, @lower) if @lower;

    @upper = glue_chords($base, @upper) if @upper;
    @lower = glue_chords($base, @lower) if @lower;

    return (@upper ? \@upper : undef),
           (@lower ? \@lower : undef);
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

sub hand_to_lilypond {
    my ($tempo, @chords) = @_;
    my $output = "%{ measures 1 to 4 %}\n";
    my ($howmany, $what) = split(m{/}, $tempo);
    # how many 16ths in a measure
    my $measure = (16 / $what) * $howmany;
    my $measure_cnt = 1;
    my $fill = 0;
    for my $chord (@chords) {
        $output .= chord_to_lilypond($chord) . ' ';
        my $type = int($chord->[0]{type});
        $fill += 16 / $type;
        if ($chord->[0]{type} =~ /\.$/) {
            $fill *= 1.5;
        }
        if ($fill >= $measure) {
            $measure_cnt++;
            $fill = 0;
            $output .= '| ';
            if ($measure_cnt % 4 == 0) {
                $output .= "\n%{ measures $measure_cnt to " . ($measure_cnt + 3) . " %}\n";
            }
        }
    }
    return $output
}

sub to_lilypond_simple {
    my ($key, $time, $upper, $lower) = @_;
    my ($source, $clef);
    if ($upper) {
        $clef = '\clef "treble"';
        $source = $upper;
    } else {
        $clef = '\clef "bass"';
        $source = $lower;
    }
    sprintf q[\version "2.16.2" {
    %s
    %s
    \time %s
    %s
}], $key, $clef, $time, hand_to_lilypond($time, @$source);
}

sub to_lilypond {
    my ($key, $time, $upper, $lower) = @_;
    $key = key_signature($key);
    if (defined($upper) + defined($lower) < 2) {
        return to_lilypond_simple($key, $time, $upper, $lower);
    }
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
}], $key, hand_to_lilypond($time, @$upper),
    $key, hand_to_lilypond($time, @$lower), $time;
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
    my ($upper, $lower) = get_notes(@events);
    my $tempo = $opts->{tempo} // ($upper ? guess_tempo(@$upper) : guess_tempo(@$lower));
    $ENV{VERBOSE} and warn "Guessed tempo: $tempo\n";

    return to_lilypond($key, $tempo, $upper, $lower);
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
