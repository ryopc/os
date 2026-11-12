# OS Development Makefile
# カーネルビルド、クリーン、QEMU 起動、ISO 作成タスク

# デフォルトタスク
.DEFAULT_GOAL := build
.PHONY: build all kernel kernel.elf check-tools clean run iso help

# ---------------------------------------------------------------------------
# ツールチェイン
# ---------------------------------------------------------------------------
# x86_64 クロスコンパイラがある環境では CROSS=x86_64-elf- を指定する。
# 未指定の場合はホストの C コンパイラ (cc) と、ELF を出力できるリンカを使う。
CROSS   ?=
NASM    ?= nasm
HOST_OS := $(shell uname -s 2>/dev/null)

KERNEL_CC := $(if $(strip $(CROSS)),$(CROSS)gcc,$(CC))

# ELF リンカの選択。macOS 標準の /usr/bin/ld は Mach-O 専用のため、
# Darwin では x86_64-elf-ld → ld.lld (LLVM) → ld の順に探す。
KERNEL_LD := $(if $(strip $(CROSS)),$(CROSS)ld,$(if $(filter Darwin,$(HOST_OS)),$(or $(shell command -v x86_64-elf-ld 2>/dev/null),$(shell command -v ld.lld 2>/dev/null),ld),ld))

# Mach-O 専用リンカを掴んでしまった場合の検出 (Darwin + 素の ld)
KERNEL_LD_IS_HOST_MACHO := $(if $(and $(filter Darwin,$(HOST_OS)),$(filter ld,$(notdir $(KERNEL_LD)))),1,0)

# ---------------------------------------------------------------------------
# ビルド構成
# ---------------------------------------------------------------------------
BUILD_DIR      := build
KERNEL_DIR     := $(BUILD_DIR)/kernel
KERNEL_OBJ_DIR := $(KERNEL_DIR)/obj
KERNEL_ELF     := $(KERNEL_DIR)/kernel.elf
LINKER_SCRIPT  := $(KERNEL_DIR)/linker.ld

BOOT_SRC   := src/boot/boot.asm
KERNEL_SRC := src/kernel/kernel.c

BOOT_OBJ   := $(KERNEL_OBJ_DIR)/boot.o
KERNEL_OBJ := $(KERNEL_OBJ_DIR)/kernel.o

# フリースタンディングな x86_64 カーネル向けコンパイルフラグ。
# -mno-red-zone : 割り込みハンドラがスタックの赤ゾーンを壊さないようにする
# -fno-pie      : 固定アドレスリンク (低メモリ 1MiB) を前提とするため
# -fno-builtin  : コンパイラによる libc 関数への置換を禁止する
#
# ターゲット指定: macOS の clang は既定で arm64 Mach-O を出力するため、
# ホストコンパイラを使う場合のみ x86_64 ELF のターゲットトリプルを明示する。
# クロスコンパイラ (CROSS=x86_64-elf-) はそれ自体が x86_64 を出力するので不要。
ifeq ($(strip $(CROSS)),)
  ifeq ($(filter Darwin,$(HOST_OS)),Darwin)
    KERNEL_TARGET_FLAGS := -target x86_64-unknown-none-elf
  else
    KERNEL_TARGET_FLAGS := -m64
  endif
else
  KERNEL_TARGET_FLAGS :=
endif

KERNEL_CFLAGS := $(KERNEL_TARGET_FLAGS) -std=gnu11 -O2 -Wall -Wextra \
                 -ffreestanding -nostdlib -fno-pie -fno-pic \
                 -fno-stack-protector -fno-asynchronous-unwind-tables \
                 -fno-builtin -mno-red-zone -c

# -fno-exceptions / -fno-rtti は C++ 専用フラグで、C コンパイル時に渡すと
# 警告になる。C++ ソースを追加する場合に備えて別変数に分離しておく。
KERNEL_CXXFLAGS := $(KERNEL_CFLAGS) -fno-exceptions -fno-rtti

# ---------------------------------------------------------------------------
# カーネルビルド
# ---------------------------------------------------------------------------
build: check-tools $(KERNEL_ELF)
	@echo "Kernel build complete: $(KERNEL_ELF)"

# make は build と同等
all: build

# README で案内している別名
kernel kernel.elf: $(KERNEL_ELF)
	@echo "Kernel ELF: $(KERNEL_ELF)"

$(KERNEL_ELF): $(BOOT_OBJ) $(KERNEL_OBJ) $(LINKER_SCRIPT)
	@mkdir -p $(dir $@)
	$(KERNEL_LD) -m elf_x86_64 -nostdlib \
		-z max-page-size=0x1000 -T $(LINKER_SCRIPT) -o $@ $(BOOT_OBJ) $(KERNEL_OBJ)
	@echo "Linked $@"

$(BOOT_OBJ): $(BOOT_SRC) | $(KERNEL_OBJ_DIR)
	$(NASM) -f elf64 -g -F dwarf $< -o $@

$(KERNEL_OBJ): $(KERNEL_SRC) | $(KERNEL_OBJ_DIR)
	$(KERNEL_CC) $(KERNEL_CFLAGS) $< -o $@

$(KERNEL_OBJ_DIR):
	@mkdir -p $@

# ---------------------------------------------------------------------------
# リンカスクリプト
#   カーネルは低メモリ 1MiB に配置する。Limine は ELF のプログラムヘッダに
#   従ってロードするため、boot.asm の boot_entry をエントリポイントとして
#   明示し、Limine のリクエストセクションを破棄されないよう KEEP する。
# ---------------------------------------------------------------------------
$(LINKER_SCRIPT): Makefile | $(KERNEL_DIR)
	@printf '%s\n' \
		'OUTPUT_FORMAT(elf64-x86-64)' \
		'ENTRY(boot_entry)' \
		'' \
		'SECTIONS' \
		'{' \
		'    . = 0x100000;' \
		'' \
		'    /* Limine はリクエストを .limine_requests から探すため独立セクションとして先頭に置く */' \
		'    .limine_requests : ALIGN(0x1000)' \
		'    {' \
		'        KEEP(*(.limine_requests_start))' \
		'        KEEP(*(.limine_requests))' \
		'        KEEP(*(.limine_requests_end))' \
		'    }' \
		'' \
		'    .text : ALIGN(0x1000)' \
		'    {' \
		'        *(.text .text.*)' \
		'    }' \
		'' \
		'    .rodata : ALIGN(0x1000)' \
		'    {' \
		'        *(.rodata .rodata.*)' \
		'    }' \
		'' \
		'    .data : ALIGN(0x1000)' \
		'    {' \
		'        *(.data .data.*)' \
		'    }' \
		'' \
		'    .bss : ALIGN(0x1000)' \
		'    {' \
		'        *(COMMON)' \
		'        *(.bss .bss.*)' \
		'    }' \
		'' \
		'    /DISCARD/ :' \
		'    {' \
		'        *(.comment)' \
		'        *(.note .note.*)' \
		'    }' \
		'}' > $@
	@echo "Generated $@"

$(KERNEL_DIR):
	@mkdir -p $@

# ---------------------------------------------------------------------------
# ツールチェイン検査
# ---------------------------------------------------------------------------
check-tools:
	@command -v "$(NASM)" >/dev/null 2>&1 || { \
		echo "error: NASM ($(NASM)) が見つかりません。'brew install nasm' などで導入してください。"; \
		exit 1; }
	@command -v "$(KERNEL_CC)" >/dev/null 2>&1 || { \
		echo "error: C コンパイラ ($(KERNEL_CC)) が見つかりません。"; \
		exit 1; }
	@command -v "$(KERNEL_LD)" >/dev/null 2>&1 || { \
		echo "error: ELF リンカ ($(KERNEL_LD)) が見つかりません。"; \
		exit 1; }
	@test "$(KERNEL_LD_IS_HOST_MACHO)" = "0" || { \
		echo "error: macOS 標準の ld は Mach-O 専用で ELF を出力できません。"; \
		echo "       llvm (ld.lld) を入れるか、CROSS=x86_64-elf- を指定してください。"; \
		exit 1; }

# ビルド成果物削除
clean:
	@echo "Cleaning build artifacts..."
	rm -rf build/
	@echo "Clean complete"

# QEMU で起動
run:
	@echo "Starting QEMU..."
	@if command -v qemu-system-x86_64 >/dev/null 2>&1; then \
		qemu-system-x86_64 -cdrom os.iso -m 2G -serial stdio -vga std; \
	else \
		echo "qemu-system-x86_64 not found. Install QEMU to run."; \
		exit 1; \
	fi

# ISO イメージ作成（プレースホルダ）
iso:
	@echo "Creating ISO image (placeholder)..."
	@echo "ISO build will be implemented in a later lane."

help:
	@echo "Available targets:"
	@echo "  build   - Build kernel ELF (build/kernel/kernel.elf)"
	@echo "  clean   - Remove build artifacts"
	@echo "  run     - Run OS in QEMU"
	@echo "  iso     - Create ISO image (placeholder)"
	@echo "  help    - Show this help message"
