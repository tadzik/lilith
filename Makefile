test:
	perl -Ilib t/samples.t

setup:
	@pkg-config gtk+-2.0 || (echo "GTK+ development headers not found\n\nPlease install them first (libgtk2.0-dev on Debian-ish systems)"; false)
	@wget http://cpanmin.us -O - | perl - -L extlib Try::Tiny MIDI Gtk2 Text::Format
