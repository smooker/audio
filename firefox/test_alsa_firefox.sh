#!/bin/bash
# test_alsa_firefox.sh - end-to-end test: which ALSA device firefox is using
#
# Runs test_alsa.pl on existing firefox process(es), or starts a fresh
# firefox with ALSA_OUT preset and tests after a few seconds.
#
# Usage:
#   ./test_alsa_firefox.sh                  # test current firefox
#   ./test_alsa_firefox.sh start dmg6       # start firefox + test
#   ./test_alsa_firefox.sh start dmpch
#   ./test_alsa_firefox.sh kill             # killall firefox

set -u
DIR="$(cd "$(dirname "$0")" && pwd)"

case "${1:-test}" in
    start)
        DEV="${2:-dmg6}"
        echo "Killing existing firefox..."
        killall firefox 2>/dev/null
        sleep 2
        echo "Starting firefox with ALSA_OUT=$DEV..."
        ALSA_OUT="$DEV" firefox &
        sleep 5
        echo
        echo "=== Testing ==="
        perl "$DIR/test_alsa.pl"
        ;;
    kill)
        killall firefox
        echo "killed"
        ;;
    test|*)
        perl "$DIR/test_alsa.pl"
        ;;
esac
