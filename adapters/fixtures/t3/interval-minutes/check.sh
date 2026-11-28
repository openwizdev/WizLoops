#!/bin/sh
if [ -n "$WIZLOOP_PARAM_REPO" ] && [ -n "$WIZLOOP_PARAM_TITLE" ] && [ -f due.txt ]; then cat due.txt; fi
exit 0
