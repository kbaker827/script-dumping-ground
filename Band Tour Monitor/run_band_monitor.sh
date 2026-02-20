#!/bin/bash
# Band Tour Monitor - Wrapper Script
# Run this from cron or heartbeat to check for new shows

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PYTHON_SCRIPT="$SCRIPT_DIR/band_tour_monitor.py"

# Check if python3 is available
if ! command -v python3 &> /dev/null; then
    echo "Error: python3 is required but not installed"
    exit 1
fi

# Run the monitor
python3 "$PYTHON_SCRIPT" "$@"