test:
	perl -Ilib t/samples.t

setup: deb-setup
	@wget http://cpanmin.us -O - | perl - -L extlib Try::Tiny MIDI Gtk2

deb-setup:
	sudo apt-get install libgtk2.0-dev alsa-utils lilypond
