#!/usr/bin/perl

=encoding UTF-8

=head1 NAME

ff_pref.pl - low-level Firefox pref editor (user.js)

=head1 SYNOPSIS

  ./ff_pref.pl profile               # print active Firefox profile path
  ./ff_pref.pl list                  # list all prefs currently in user.js
  ./ff_pref.pl get <key>             # get pref value
  ./ff_pref.pl set <key> <value>     # set pref (auto-detect string/int/bool)
  ./ff_pref.pl unset <key>           # remove pref

=head1 DESCRIPTION

Edits C<~/.mozilla/firefox/E<lt>profileE<gt>/user.js> from the command line.
Firefox reads C<user.js> on every startup and the values override anything
in C<prefs.js>, including changes made via C<about:config> in the UI. So
C<user.js> survives Firefox restarts cleanly, while writes to C<prefs.js>
get clobbered when Firefox shuts down.

The script:

=over 4

=item * Auto-detects the active profile from C<profiles.ini>
(prefers C<Default=1>, falls back to first listed profile).

=item * Backs up C<user.js> to C<user.js.bak> before any modification.

=item * Auto-detects value type: integers (C<42>), booleans (C<true>/C<false>),
otherwise wraps as a quoted string. Pass C<'"already quoted"'> to keep
existing quotes.

=back

B<Firefox MUST be closed> when running C<set>/C<unset>, otherwise the
running instance may rewrite C<prefs.js> on shutdown and confuse the state.

=head1 EXAMPLES

=head2 Audio backend (cubeb)

  # Force ALSA backend (no pulse/sndio/jack guessing)
  ./ff_pref.pl set media.cubeb.backend alsa

  # Direct ALSA device override (if your Firefox version supports it)
  ./ff_pref.pl set media.cubeb.alsa.device dmg6

  # Verbose cubeb logs to Browser Console (Ctrl+Shift+J)
  ./ff_pref.pl set media.cubeb.log_level verbose

  # Verify
  ./ff_pref.pl get media.cubeb.backend
  ./ff_pref.pl list

  # Cleanup
  ./ff_pref.pl unset media.cubeb.log_level

=head2 Privacy hardening

  ./ff_pref.pl set privacy.donottrackheader.enabled true
  ./ff_pref.pl set network.cookie.cookieBehavior 1
  ./ff_pref.pl set media.peerconnection.enabled false   # disable WebRTC
  ./ff_pref.pl set geo.enabled false
  ./ff_pref.pl set dom.event.clipboardevents.enabled false

=head2 Browser behaviour

  ./ff_pref.pl set browser.startup.page 3               # restore session
  ./ff_pref.pl set browser.tabs.warnOnClose false
  ./ff_pref.pl set browser.cache.disk.enable false      # RAM only

=head1 VALUE TYPES

  ./ff_pref.pl set foo.int      42         # int
  ./ff_pref.pl set foo.bool     true       # bool
  ./ff_pref.pl set foo.bool     false      # bool
  ./ff_pref.pl set foo.string   alsa       # string -> auto quoted
  ./ff_pref.pl set foo.string   '"alsa"'   # string -> kept verbatim

=head1 FILES

=over 4

=item C<~/.mozilla/firefox/profiles.ini>

Read to find the active profile path.

=item C<~/.mozilla/firefox/E<lt>profileE<gt>/user.js>

The file modified by C<set> / C<unset>.

=item C<~/.mozilla/firefox/E<lt>profileE<gt>/user.js.bak>

Backup written before each modification.

=back

=head1 SEE ALSO

L<test_alsa.pl>, L<test_alsa_firefox.sh>, README.md

=cut

use strict;
use warnings;
use File::Copy qw(copy);

sub find_profile {
    my $ini = "$ENV{HOME}/.mozilla/firefox/profiles.ini";
    open(my $fh, '<', $ini) or die "Cannot read $ini: $!\n";
    my ($default_path, $default_relative);
    my %sections;
    my $cur;
    while (my $line = <$fh>) {
        chomp $line;
        if ($line =~ /^\[(.+)\]$/) { $cur = $1; next; }
        if (defined $cur && $line =~ /^(\w+)=(.*)$/) {
            $sections{$cur}{$1} = $2;
        }
    }
    close($fh);
    # Prefer Default=1 in any Profile section, or Profile0
    for my $sec (sort keys %sections) {
        next unless $sec =~ /^Profile/;
        my $h = $sections{$sec};
        if ($h->{Default} && $h->{Default} eq '1') {
            return profile_path($h);
        }
    }
    # Fallback: first profile
    for my $sec (sort keys %sections) {
        next unless $sec =~ /^Profile/;
        return profile_path($sections{$sec});
    }
    die "No profile found in $ini\n";
}

sub profile_path {
    my $h = shift;
    my $p = $h->{Path} or die "Profile section missing Path\n";
    if ($h->{IsRelative} && $h->{IsRelative} eq '1') {
        return "$ENV{HOME}/.mozilla/firefox/$p";
    }
    return $p;
}

sub user_js_path {
    my $profile = find_profile();
    return "$profile/user.js";
}

sub read_user_js {
    my $f = user_js_path();
    return [] unless -e $f;
    open(my $fh, '<', $f) or die "Cannot read $f: $!\n";
    my @lines = <$fh>;
    close($fh);
    chomp @lines;
    return \@lines;
}

sub write_user_js {
    my $lines = shift;
    my $f = user_js_path();
    if (-e $f) {
        copy($f, "$f.bak") or warn "Backup failed: $!\n";
    }
    open(my $fh, '>', $f) or die "Cannot write $f: $!\n";
    print $fh "$_\n" for @$lines;
    close($fh);
    print "Wrote $f\n";
}

sub format_value {
    my $v = shift;
    return $v if $v =~ /^-?\d+$/;        # int
    return $v if $v =~ /^(true|false)$/; # bool
    return $v if $v =~ /^".*"$/;         # already quoted
    return qq("$v");                      # default: string, add quotes
}

sub parse_pref_line {
    my $line = shift;
    return undef unless $line =~ /^user_pref\(\s*"([^"]+)"\s*,\s*(.+?)\s*\)\s*;/;
    return ($1, $2);
}

my $cmd = shift @ARGV // 'help';

if ($cmd eq 'profile') {
    print find_profile(), "\n";
}
elsif ($cmd eq 'list') {
    my $lines = read_user_js();
    for my $l (@$lines) {
        my ($k, $v) = parse_pref_line($l);
        printf("  %-50s = %s\n", $k, $v) if defined $k;
    }
}
elsif ($cmd eq 'get') {
    my $key = shift @ARGV or die "Usage: ff_pref.pl get <key>\n";
    my $lines = read_user_js();
    for my $l (@$lines) {
        my ($k, $v) = parse_pref_line($l);
        if (defined $k && $k eq $key) {
            print "$v\n";
            exit 0;
        }
    }
    print STDERR "Not set in user.js\n";
    exit 1;
}
elsif ($cmd eq 'set') {
    my $key = shift @ARGV or die "Usage: ff_pref.pl set <key> <value>\n";
    my $val = shift @ARGV;
    die "Missing value\n" unless defined $val;
    $val = format_value($val);
    my $lines = read_user_js();
    my $found = 0;
    for my $i (0..$#$lines) {
        my ($k, undef) = parse_pref_line($lines->[$i]);
        if (defined $k && $k eq $key) {
            $lines->[$i] = qq(user_pref("$key", $val););
            $found = 1;
            last;
        }
    }
    push @$lines, qq(user_pref("$key", $val);) unless $found;
    write_user_js($lines);
    print "Set $key = $val\n";
    print "Restart firefox for changes to take effect.\n";
}
elsif ($cmd eq 'unset') {
    my $key = shift @ARGV or die "Usage: ff_pref.pl unset <key>\n";
    my $lines = read_user_js();
    my @new = grep {
        my ($k, undef) = parse_pref_line($_);
        !(defined $k && $k eq $key);
    } @$lines;
    write_user_js(\@new);
    print "Unset $key\n";
}
else {
    print <<'USAGE';
ff_pref.pl - Firefox pref editor (user.js)

Commands:
  profile             Print active profile path
  list                List all prefs in user.js
  get <key>           Get pref value
  set <key> <value>   Set pref (auto-detect string/int/bool)
  unset <key>         Remove pref

Examples:
  ./ff_pref.pl set media.cubeb.backend alsa
  ./ff_pref.pl set media.cubeb.alsa.device dmg6
  ./ff_pref.pl set media.cubeb.log_level verbose
  ./ff_pref.pl set browser.startup.page 3
  ./ff_pref.pl set privacy.donottrackheader.enabled true
  ./ff_pref.pl get media.cubeb.backend
  ./ff_pref.pl unset media.cubeb.log_level
  ./ff_pref.pl list

NOTE: Firefox MUST be closed before/after editing user.js, otherwise
prefs.js may overwrite your changes on next clean shutdown. user.js
itself is read on every startup and overrides prefs.js.
USAGE
}
