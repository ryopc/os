# Bare Bones OS Development

## Overview
This repository contains the foundational infrastructure for developing an operating system from scratch using QEMU for testing and validation.

## Build Instructions

### Prerequisites
- Linux/macOS or WSL2 (for QEMU)
- NASM assembler
- GCC compiler
- GNU make
- QEMU emulator

### Building the Kernel
```bash
make all         # Build everything (kernel.elf, iso, etc.)
make kernel.elf  # Build only the kernel
```

### Running in QEMU
```bash
make run         # Run the OS in QEMU (uses ISO by default)
```

### Running the Bootloader
```bash
make run-kernel  # Run the kernel directly (bypasses bootloader)
```

### Cleaning Build Artifacts
```bash
make clean      # Remove all generated files
```

## QEMU Configuration
By default, `make run` boots the OS using the ISO image.

Key QEMU options:
- `-m 2G` : Memory size (2GB)
- `-serial stdio` : Serial console output
- `-vga std` : Standard VGA graphics

## File Structure
```
os/
├── .gitignore        # Git ignore rules for OS development
├── .gitattributes    # Git LFS configuration
├── Makefile          # Build system
├── scripts/          # Helper scripts
│   └── run-qemu.sh   # QEMU boot wrapper
├── src/              # Source code
│   ├── kernel/       # Kernel source
│   │   └── kernel.c  # Kernel entry point
│   └── boot/         # Bootloader
│       └── boot.asm  # Boot assembly code
├── .github/          # GitHub Actions workflows
│   └── workflows/    # CI/CD pipelines
└── build/            # Build outputs (generated)
    ├── kernel/
    └── limine/
```

## Contributing
1. Create a new branch from `main`
2. Make your changes
3. Commit and push
4. Create a pull request

## License
This project is open source. Contributions are welcome!

## Notes
- This repository contains minimal placeholder code to get started
- The kernel is currently empty (just an infinite loop)
- The bootloader is a minimal NASM implementation
- Future improvements will include actual OS functionality