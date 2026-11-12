#!/bin/bash

# QEMU boot wrapper script
# This script can be run directly or called from the Makefile

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Default QEMU options
QEMU_OPTS="-m 2G -serial stdio -vga std"

# Check if ISO exists
ISO="$PROJECT_ROOT/build/os.iso"
if [[ ! -f "$ISO" ]]; then
    echo "ISO not found. Running make iso first..."
    cd "$PROJECT_ROOT"
    make iso
    if [[ $? -ne 0 ]]; then
        echo "Failed to build ISO. Exiting."
        exit 1
    fi
fi

# Boot QEMU with ISO
echo "Starting QEMU..."
exec qemu-system-x86_64 $QEMU_OPTS -cdrom "$ISO"