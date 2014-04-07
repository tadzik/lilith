use Test::More;
use 5.010;
use strict;
use warnings;
use Lilith;
use MIDI;

my %outputs = (
    'samples/menuet-short.mid' => <<'EOF1'
\version "2.16.2" {
    \key g \major
    \clef "treble"
    \time 3/4
    %{ measures 1 to 4 %}
d''4 g'8 a'8 b'8 c''8 | d''4 g'4 g'4 | e''4 c''8 d''8 e''8 fis''8 |
%{ measures 4 to 7 %}
g''4 g'4 g'4 |
}
EOF1
,
    'samples/wlazkotek.mid' => <<'EOF2'
\version "2.16.2" {
    \key c \major
    \clef "treble"
    \time 3/4
    %{ measures 1 to 4 %}
g'4 e'4 e'4 | f'4 d'4 d'4 | c'8 e'8 g'4 r4 |
%{ measures 4 to 7 %}
g'4 e'4 e'4 | f'4 d'4 d'4 | c'8 e'8 c'4
}
EOF2
,
    'samples/pick_simple_division.mid' => <<'EOF3'
\version "2.16.2"
upper = {
    \key g \major
    \clef "treble"
    %{ measures 1 to 4 %}
d''4 g'8 a'8 b'8 c''8 | d''4 g'4 g'4 | e''4 c''8 d''8 e''8 fis''8 |
%{ measures 4 to 7 %}
g''4 g'4 g'4 |
}
lower = {
    \key g \major
    \clef "bass"
    %{ measures 1 to 4 %}
<< g2 d'2 b2 >> a4 | b2. | c'2. |
%{ measures 4 to 7 %}
b2. |
}
\score {
    \new PianoStaff <<
        \time 3/4
        \new Staff = "upper" \upper
        \new Staff = "lower" \lower
    >>
    \layout { }
}
EOF3
,
);

sub normalize {
    my $s = shift;
    $s =~ s/\s//g;
    $s
}

for my $file (sort keys %outputs) {
    my $o = MIDI::Opus->new({ from_file => $file });
    my $track = ($o->tracks)[0];
    my $lp = Lilith::generate({}, $track->events);
    is normalize($lp), normalize($outputs{$file}), "correct output from $file";
}

done_testing;
