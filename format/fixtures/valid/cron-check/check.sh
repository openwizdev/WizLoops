#!/bin/sh
# Prints one line per due item in {{repo}}; nothing when none is due.
if [ -f due.txt ]; then cat due.txt; fi
exit 0
