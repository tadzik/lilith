#!/usr/bin/env perl
use 5.010;
use strict;
use warnings;
use Gtk2 '-init';
use Try::Tiny;
use MIDI;
use lib 'lib';
use Lilith;
use File::Temp 'tmpnam';
use IPC::Open3;

my $win = Gtk2::Window->new('toplevel');
$win->signal_connect(delete_event => sub { Gtk2->main_quit });
$win->show_all;

my $editor;
my $cli_log;
my $statusbar;
my $current_image;
my $preview;

my $vbox = Gtk2::VBox->new;
{
    my $hbox = Gtk2::HBox->new;
    my $entry = Gtk2::Entry->new;
    $entry->set_editable(0);
    my $button = Gtk2::Button->new_from_stock('gtk-open');
    $button->signal_connect(clicked => sub {
        my $dialog = Gtk2::FileChooserDialog->new(
            'Pick a MIDI file', $win, 'open', 'gtk-cancel' => 'cancel', 'gtk-ok' => 'ok');

        if ('ok' eq $dialog->run) {
            my $filename = $dialog->get_filename;
            $entry->set_text($filename);

            try {
                $cli_log->get_buffer->set_text('');
                my $o = MIDI::Opus->new({ from_file => $filename });
                my $track = ($o->tracks)[0];
                $editor->get_buffer->set_text(Lilith::generate({}, $track->events));
                $statusbar->push(0, "$filename opened");
            } catch {
                $cli_log->get_buffer->set_text("Failed to generate lilypond from $filename:\n\t$_");
                $statusbar->push(0, 'Something went wrong!');
            };

        }
        $dialog->destroy;
    });
    $hbox->add($entry);
    $hbox->pack_start($button, 0, 0, 0);

    $vbox->pack_start($hbox, 0, 0, 0);
}
{
    my $button = Gtk2::Button->new;
    my $align = Gtk2::Alignment->new(0.5, 0, 0, 0);
    my $hbox = Gtk2::HBox->new;
    $hbox->pack_start(Gtk2::Label->new('Generate music sheet'), 0, 0, 0);
    $hbox->pack_start(Gtk2::Image->new_from_stock('gtk-apply', 'menu'), 0, 0, 0);
    $align->add($hbox);
    $button->add($align);
    $button->signal_connect(clicked => sub {
        my $tmpfile = tmpnam;
        my ($wtr, $rdr, $err);
        my $pid = open3($wtr, $rdr, $err, "lilypond --png -s -o $tmpfile -");
        my $buf = $editor->get_buffer;
        $statusbar->push(0, 'Generating preview');
        print $wtr $buf->get_text($buf->get_start_iter, $buf->get_end_iter, 1);
        close $wtr;
        waitpid($pid, 0);
        my $output = '';
        if (defined $rdr) {
            while (<$rdr>) {
                $output .= $_
            }
            close $rdr;
        }
        if (defined $err) {
            while (<$err>) {
                $output .= $_
            }
            close $err;
        }
        if ($output) {
            $cli_log->get_buffer->set_text($output);
            $statusbar->push(0, 'Something went wrong!');
        } else {
            $cli_log->get_buffer->set_text($output);

            $current_image->set_from_file("$tmpfile.png");

            $statusbar->push(0, 'Preview generated successfully');
        }
    });

    $vbox->pack_start($button, 0, 0, 0);
}
{
    my $vpaned = Gtk2::VPaned->new;
    my $hpaned = Gtk2::HPaned->new;
    my $editor_frame = Gtk2::Frame->new('Lilypond editor');
    $editor = Gtk2::TextView->new;
    $editor_frame->add($editor);
    $hpaned->add1($editor_frame);
    my $image_frame = Gtk2::Frame->new('Here be preview');
    my $preview = Gtk2::ScrolledWindow->new;
    $image_frame->add($preview);
    $current_image = Gtk2::Image->new;
    $preview->add_with_viewport($current_image);
    $hpaned->add2($image_frame);
    $vpaned->pack1($hpaned, 1, 1);

    my $cli_frame = Gtk2::Frame->new('CLI output');
    $cli_log = Gtk2::TextView->new;
    $cli_log->set_editable(0);
    $cli_frame->add($cli_log);
    $vpaned->pack2($cli_frame, 1, 1);

    $vbox->add($vpaned);
}

$statusbar = Gtk2::Statusbar->new;
$statusbar->push(0, 'Welcome to Lilith GUI');
$vbox->pack_start($statusbar, 0, 0, 0);
$win->add($vbox);

$win->show_all;

Gtk2->main;

