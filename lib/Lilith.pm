package Lilith;
use 5.010;
use strict;
use warnings FATAL => 'all';
use Lilith::KeyGuesser;
use File::Temp 'tempfile';
use Data::Dumper;
use Carp::Always;

our $LILYPOND_VERSION = '\\version "2.16.2"';

# fun fact: it's not really a mean =)
# a real mean yields idiotic results, when it happens to compute average time of 1/8 and 1/4
sub mean {
    my @arr = @_;
    my $idx = int($#arr / 2);
    return $arr[$idx];
}

sub LOG {
    $ENV{VERBOSE} and print @_
}

sub LOGN {
    LOG @_, "\n"
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
    for (@_) {
        for (@$_) {
            next unless $_->{type};
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

sub divide_hands_simple_by_divisor {
    my (@upper, @lower);
    my ($upper_legit, $lower_legit);
    my $divisor = shift;
    for my $outer (@_) {
        my (@cands_l, @cands_u);
        for (@$outer) {
            if ($_->{idx} == -1) {
                push @cands_l, $_;
                push @cands_u, $_;
            } elsif ($_->{idx} < $divisor) {
                push @cands_l, $_;
                $lower_legit = 1;
            } else {
                push @cands_u, $_;
                $upper_legit = 1;
            }
        }
        push @upper, \@cands_u;
        push @lower, \@cands_l;
    }
    unless ($upper_legit) {
        @upper = ()
    }
    unless ($lower_legit) {
        @lower = ()
    }
    return \@upper, \@lower, { hand_division => 'simple', hand_divisor => $divisor }
}

sub divide_hands_simple {
    my $conf = shift;
    if ($conf->{hand_divisor}) {
        return divide_hands_simple_by_divisor($conf->{hand_divisor}, @_);
    }
    my ($best_score, @best_res) = 999;
    my $divisor = 55;
    while ($divisor <= 67) {
        my @res = divide_hands_simple_by_divisor($divisor, @_);
        my $score = rate_hand_division(@res);
        if ($score <= $best_score) {
            LOGN "$score ($MIDI::number2note{$divisor}) wins so far...";
            $best_score = $score;
            @best_res = @res;
        } else {
            LOGN "Score for $MIDI::number2note{$divisor} is $score";
        }
        $divisor++;
    }
    return @best_res;
}

sub divide_hands_tracing {
    # TODO (P3 or so): it could try to keep track of which finger pressed the last key,
    # to even better trace hand positioning
    my (@upper, @lower);
    my ($upper_legit, $lower_legit);
    my $lastlower = 48; # C4
    my $lastupper = 72; # C6
    for my $outer (@_) {
        my (@cands_l, @cands_u);
        for (@$outer) {
            LOG "lastlower: $lastlower, lastupper: $lastupper, current: ".$_->{idx}
                ." (".$MIDI::number2note{$_->{idx}}.")" unless $_->{idx} == -1;
            if ($_->{idx} == -1) {
                push @cands_l, $_;
                push @cands_u, $_;
            } elsif (abs($_->{idx} - $lastlower) < abs($_->{idx} - $lastupper)) {
                LOGN " ... goes lower";
                $lastlower = $_->{idx};
                push @cands_l, $_;
                $lower_legit = 1;
            } else {
                LOGN " ... goes upper";
                $lastupper = $_->{idx};
                push @cands_u, $_;
                $upper_legit = 1;
            }
        }
        push @upper, \@cands_u;
        push @lower, \@cands_l;
    }
    unless ($upper_legit) {
        @upper = ()
    }
    unless ($lower_legit) {
        @lower = ()
    }
    return \@upper, \@lower, { hand_division => 'tracing', hand_divisor => 60 }
}

sub rate_hand_division {
    my ($upper, $lower) = @_;
    my $score = 0;
    my $middle = $MIDI::note2number{'C5'};
    for (@$upper) {
        for (@$_) {
            next if $_->{idx} == -1;
            if ($_->{idx} < $middle) {
                printf "%s (in upper hand) punished for %d\n",
                       note_to_lilypond($_), abs($_->{idx} - $middle);
                $score += abs($_->{idx} - $middle);
            }
        }
    }
    for (@$lower) {
        for (@$_) {
            next if $_->{idx} == -1;
            if ($_->{idx} > $middle) {
                printf "%s (in lower hand) punished for %d\n",
                       note_to_lilypond($_), $_->{idx} - $middle;
                $score += $_->{idx} - $middle;
            }
        }
    }

    my $ulen = total_length(@$upper);
    my $llen = total_length(@$lower);
    if (!$ulen or !$llen) {
        # one-handed score
        return $score
    }
    return $score + abs($ulen - $llen);
}

sub divide_hands {
    my $conf = shift;
    {
        no warnings 'uninitialized';
        if ($conf->{hand_division} eq 'simple') {
            return divide_hands_simple($conf, @_)
        } elsif ($conf->{hand_division} eq 'tracing') {
            return divide_hands_tracing(@_)
        }
    }
    # let's try both and see which is better
    my @result_s = divide_hands_simple($conf, @_);
    my @result_t = divide_hands_tracing(@_);
    # lower is better
    my $score_s = rate_hand_division(@result_s);
    my $score_t = rate_hand_division(@result_t);
    LOGN "Score for simple  method: $score_s";
    LOGN "Score for tracing method: $score_t";

    if ($score_s < $score_t) {
        LOGN "Simple wins";
        return @result_s
    } else {
        LOGN "Tracing wins";
        return @result_t
    }
}

# for 1/32 resolution
sub length2type {
    my $diff = shift;
    my $t;
    if ($diff > 32) {
        $t = 1
    } elsif ($diff > 24) {
        $t = '2.'
    } elsif ($diff > 16) {
        $t = 2
    } elsif ($diff > 12) {
        $t = '4.'
    } elsif ($diff > 8) {
        $t = 4
    } elsif ($diff > 4) {
        $t = 8
    } elsif ($diff > 2) {
        $t = 16
    }
    return $t
}

sub get_notes_polling {
    my ($resolution, @stream) = @_;

    my $currenttime = 0;
    my (@events, @pending);

    for (@stream) {
        $currenttime += $_->[1];
        while ($currenttime > $resolution) {
            if (@pending) {
                my @copy = @pending;
                push @events, \@copy;
                @pending = ()
            } else {
                push @events, []
            }
            $currenttime -= $resolution;
        }
        if ($_->[0] eq 'note_on') {
            push @pending, $_->[3]
        } elsif ($_->[0] eq 'note_off') {
            push @pending, -$_->[3]
        }
    }
    # trim from both sides
    shift @events while @{$events[0]} == 0;
    pop @events while @{$events[$#events]} == 0;
    
    unless (@events) {
        die "File appears to be empty"
    }

    my @notes;
    my $i = 0;
    my $dirty = 0;
    while ($i < $#events) {
        my @ev = @{$events[$i]};

        my @current;
        if (@ev) {
            for my $e (@ev) {
                if ($e > 0) { # note_on
                    # look for the matching note_off
                    my $endidx = $i;
                    LOOP: while (1) {
                        my @cands = @{$events[$endidx]};
                        for (@cands) {
                            if ($_ == -$e) {
                                last LOOP;
                            }
                        }
                        $endidx++;
                        $dirty = $endidx;
                    }
                    my $diff = $endidx - $i;
                    my $n = {
                        type => length2type($diff),
                        octave => idx2octave($e),
                        sound => idx2sound($e),
                        idx => $e,
                    };
                    push @current, $n
                }
            }
            push @notes, \@current if @current;
            $i++;
        } elsif ($i > $dirty) {
            # a pause starts here, let's look for the end of it
            my $start = $i;
            while (1) {
                last if @{$events[$i]};
                $i++;
            }
            my $diff = $i - $start;
            my $n = {
                type => length2type($diff),
                sound => 'r',
                octave => '',
                idx => -1,
            };
            push @notes, [$n] if $n->{type}; # just skip it if it's too short
        } else {
            # it's not a pause, we're just between some note_on and note_off
            while (1) {
                last if @{$events[$i]};
                $i++;
            }
        }
    }

    #print Dumper \@notes;

    return @notes;
}

sub rate_notes {
    my $score = 0;

    my $last = $_[0][0]{type};

    for (@_) {
        $last //= '';
        if (not defined $_->[0]{type}) {
            $score += 5;
        } elsif ($_->[0]{type} ne $last) {
            $score += 2;
        }
        if (($_->[0]{type} // '') =~ /\./) {
            $score++;
        }
        $last = $_->[0]{type};
    }
    return $score;
}

sub get_notes {
    my ($conf, @events) = @_;
    my @notes;
    my $resolution = $conf->{resolution};

    if ($resolution) {
        @notes = get_notes_polling($conf->{resolution}, @events);
    } else {
        @notes = get_notes_polling(30, @events);
        my $bestscore = rate_notes(@notes);
        $resolution = 30;

        for (31..60) {
            my @new = get_notes_polling($_, @events);
            my $score = rate_notes(@new);
            LOGN "Polling for resolution($_) => $score";
            if ($score < $bestscore) {
                LOGN "Resolution $_ is now winning!";
                $resolution = $_;
                $bestscore = $score;
                @notes = @new;
            }
        }
    }

    my ($upper, $lower, $meta) = divide_hands($conf, @notes);

    return (@$upper ? $upper : undef),
           (@$lower ? $lower : undef),
           { %$meta, resolution => $resolution };
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
    unless (defined $n->{type}) { # XXX ozdobniki
        return ''
    }
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
        next unless $chord->[0]{type}; # XXX ozdobniki
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
    my ($key, $time, $upper, $lower, $conf) = @_;
    my ($source, $clef);
    if ($upper) {
        $clef = '\clef "treble"';
        $source = $upper;
    } else {
        $clef = '\clef "bass"';
        $source = $lower;
    }
    my $version = $conf->{omit_version} ? '' : $LILYPOND_VERSION;
    sprintf q[%s {
    %s
    %s
    \time %s
    %s
}], $version, $key, $clef, $time, hand_to_lilypond($time, @$source);
}

sub to_lilypond {
    my ($key, $time, $upper, $lower, $conf) = @_;
    $key = key_signature($key);
    if (defined($upper) + defined($lower) < 2) {
        return to_lilypond_simple($key, $time, $upper, $lower, $conf);
    }
    my $version = $conf->{omit_version} ? '' : $LILYPOND_VERSION;
    sprintf q[%s
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
}], $version,
    $key, hand_to_lilypond($time, @$upper),
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

sub parse_hand_divisor {
    my $div = shift;
    return $div unless $div;
    my $res;
    if ($div =~ /^\d+$/) {
        $res = $div;
    } elsif ($div =~ /^([a-zA-Z]+)(\'*|\,*)$/) {
        my ($note, $octave) = (ucfirst($1), $2);
        $note =~ s/is/s/;
        my $suffix = 4;
        if ($octave =~ /^\'+$/) {
            $suffix += length($octave);
        } elsif ($octave =~ /^\,+$/) {
            $suffix -= length($octave);
        }
        $res = $MIDI::note2number{$note . $suffix}
    } else {
        $res = $MIDI::note2number{$div}
    }
    LOGN "Hand divisor parsed as $res";
    return $res || die "Unable to parse hand divisor: $div";
}

sub format_hand_divisor {
    my $divisor = shift;
    my $foo = lc $MIDI::number2note{$divisor};
    $foo =~ s/s/is/;
    $foo =~ /^(\D+)(\d+)$/;
    if ($2 > 4) {
        return $1 . ("'" x ($2 - 4))
    }
    return $1 . ("," x (4 - $2))
}

sub generate {
    my ($opts, @events) = @_;
    my $key = $opts->{key} // Lilith::KeyGuesser::guess(@events)->[0];
    LOGN "Guessed key: $key";
    $opts->{hand_divisor} = parse_hand_divisor($opts->{hand_divisor});
    my ($upper, $lower, $meta) = get_notes($opts, @events);
    my $tempo = $opts->{tempo} // ($upper ? guess_tempo(@$upper) : guess_tempo(@$lower));
    LOGN "Guessed tempo: $tempo";

    my $lilypond = to_lilypond($key, $tempo, $upper, $lower, $opts);
    if (wantarray) {
        $meta->{hand_divisor} = format_hand_divisor($meta->{hand_divisor});
        return $lilypond, { %$meta, tempo => $tempo };
    }
    return $lilypond;
}

sub generate_pdf {
    my ($pdffile, $opts) = (shift, shift);
    my $contents = generate($opts, @_);
    my ($fh, $filename) = tempfile();
    say $fh $contents;
    close $fh;
    LOGN "Running lilypond";
    system("lilypond -s -o $pdffile $filename");
    if ($opts->{keep}) {
        LOGN "File saved as $filename";
    } else {
        unlink $filename
    }
}

1;
