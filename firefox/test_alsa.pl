#!/usr/bin/perl

=encoding UTF-8

=head1 NAME

test_alsa.pl - diagnose where firefox is playing audio

=head1 SYNOPSIS

  ./test_alsa.pl                    # auto-find firefox PIDs
  ./test_alsa.pl <pid>              # only the given PID
  ./test_alsa.pl <pid1> <pid2> ...  # multiple PIDs

=head1 DESCRIPTION

Inspects running firefox processes and reports which ALSA device they
have open, what audio-related env vars they inherited, and a fuser
summary across all /dev/snd/pcm*p devices.

Useful for diagnosing why C<ALSA_OUT=dmg6 firefox> ended up on the
wrong card. Compare the C<Cx> in the open audio device with the cards
listed in /proc/asound/cards.

=head1 OUTPUT SECTIONS

=over 4

=item * ALSA cards (from /proc/asound/cards)

=item * Per-PID: cmdline, relevant env (ALSA_*, AUDIODEV, APULSE_*, PULSE_*, MOZ_*),
open audio devices from /proc/PID/fd

=item * fuser summary across /dev/snd/pcmC*p

=item * /proc/asound/pcm device map

=item * Interpretation hints (which Cx is which card on st)

=back

=head1 EXAMPLES

  # Default — find all firefox processes
  ./test_alsa.pl

  # Combine with start/restart helper
  killall firefox; ALSA_OUT=dmg6 firefox &
  sleep 5
  ./test_alsa.pl

  # Limit to one PID
  ./test_alsa.pl 12345

=head1 SEE ALSO

L<ff_pref.pl>, L<test_alsa_firefox.sh>, README.md

=cut

use strict;
use warnings;

sub run {
    my $cmd = shift;
    open(my $fh, '-|', $cmd) or return ();
    my @out = <$fh>;
    close($fh);
    chomp @out;
    return @out;
}

sub read_environ {
    my $pid = shift;
    my $f = "/proc/$pid/environ";
    return () unless -r $f;
    open(my $fh, '<', $f) or return ();
    local $/;
    my $data = <$fh>;
    close($fh);
    return split(/\0/, $data);
}

sub read_cmdline {
    my $pid = shift;
    open(my $fh, '<', "/proc/$pid/cmdline") or return '';
    local $/;
    my $c = <$fh>;
    close($fh);
    $c =~ tr/\0/ /;
    return $c;
}

# 1. Find firefox PIDs
my @pids;
if (@ARGV) {
    @pids = @ARGV;
} else {
    @pids = grep { /^\d+$/ } run("pgrep -f firefox");
}

unless (@pids) {
    print "No firefox processes found.\n";
    print "Start firefox first, e.g.: ALSA_OUT=dmg6 firefox &\n";
    exit 1;
}

# 2. Show ALSA cards (for reference)
print "=== ALSA cards ===\n";
print join("\n", run("cat /proc/asound/cards")), "\n\n";

# 3. For each firefox process: env, audio devices opened
for my $pid (@pids) {
    my $cmd = read_cmdline($pid);
    print "=== PID $pid ===\n";
    print "  cmdline: ", substr($cmd, 0, 100), "\n";

    # Env: only ALSA_*, AUDIODEV, APULSE_*, MOZ_*, PULSE_*
    my @env = read_environ($pid);
    my @relevant = grep { /^(ALSA_|AUDIODEV|APULSE|PULSE_|MOZ_DISABLE_RDD|MOZ_LOG)/ } @env;
    if (@relevant) {
        print "  env (relevant):\n";
        print "    $_\n" for @relevant;
    } else {
        print "  env: no relevant audio vars\n";
    }

    # Open audio devices via /proc/PID/fd
    my @fds = run("ls -l /proc/$pid/fd 2>/dev/null");
    my @audio_fds = grep { m{/dev/snd/} } @fds;
    if (@audio_fds) {
        print "  open audio devices:\n";
        for my $line (@audio_fds) {
            if ($line =~ m{(/dev/snd/\S+)}) {
                print "    $1\n";
            }
        }
    } else {
        print "  open audio devices: none\n";
    }
    print "\n";
}

# 4. fuser summary across all snd devices
print "=== fuser /dev/snd/pcm*p (which processes hold playback devices) ===\n";
my @fout = run("fuser -v /dev/snd/pcmC*p 2>&1");
print join("\n", @fout), "\n\n";

# 5. /proc/asound/pcm map (device → friendly name)
print "=== /proc/asound/pcm (device map) ===\n";
print join("\n", run("cat /proc/asound/pcm")), "\n\n";

# 6. Suggestion
print "=== INTERPRETATION ===\n";
print "Look for /dev/snd/pcmCxDyp in 'open audio devices' above.\n";
print "Match Cx to a card from /proc/asound/cards:\n";
print "  C0 = NVidia (HDMI)\n";
print "  C1 = PCH (onboard)\n";
print "  C2 = G6 (Sound BlasterX, USB)\n";
print "If firefox holds C1Dxxxp -> playing on PCH (wrong if you wanted G6)\n";
print "If firefox holds C2Dxxxp -> playing on G6 (correct)\n";
