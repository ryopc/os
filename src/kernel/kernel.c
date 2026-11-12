/*
 * kernel.c - 早期コンソール (シリアル COM1 + VGA テキスト)
 *
 * 動作モードの前提:
 *   Limine はファームウェアの 16 ビットモードから 32 ビットプロテクトモードを
 *   経て 64 ビット long mode へ遷移し、ページングを有効にした状態で
 *   boot.asm の boot_entry へ制御を渡す。モード移行とその検証はブート側の
 *   責務であり、このカーネルは「long mode で動作している」ことを前提に動く。
 *   そのためここでは 16/32 ビット用の分岐を持たず、以下だけを提供する:
 *     1. COM1 (0x3F8) へのポーリング出力
 *     2. VGA テキストバッファ (0xB8000) への出力
 *     3. 両方へバナーを出して停止する kernel_main
 *
 * ライブラリ依存なし (freestanding)。標準ヘッダはコンパイラ組み込みの
 * 型定義のみを利用する。
 *
 * VGA テキスト出力は 0xB8000 がそのまま見えている前提に立つ。そのため
 * limine.cfg でグラフィックスモードを無効化し、テキストモードを維持する。
 * シリアル出力はこの前提に依存しないため、画面が出ない環境でも
 * 早期ログは必ず取得できる。
 */

#include <stddef.h>
#include <stdint.h>

/* ---------------------------------------------------------------------------
 * ポート I/O
 * ------------------------------------------------------------------------- */

static inline void outb(uint16_t port, uint8_t value) {
    __asm__ volatile("outb %0, %1" : : "a"(value), "Nd"(port));
}

static inline uint8_t inb(uint16_t port) {
    uint8_t value;
    __asm__ volatile("inb %1, %0" : "=a"(value) : "Nd"(port));
    return value;
}

/* ---------------------------------------------------------------------------
 * シリアルコンソール (16550 互換 UART, COM1)
 * ------------------------------------------------------------------------- */

#define COM1_PORT 0x3F8
#define UART_REG_DATA 0 /* 送受信データ (DLAB=1 のときは分周比下位) */
#define UART_REG_IER 1  /* 割り込み許可 (DLAB=1 のときは分周比上位) */
#define UART_REG_FCR 2  /* FIFO 制御 */
#define UART_REG_LCR 3  /* 回線制御 */
#define UART_REG_MCR 4  /* モデム制御 */
#define UART_REG_LSR 5  /* 回線状態 */

#define UART_LSR_THRE 0x20 /* 送信保持レジスタが空 */
#define UART_LCR_DLAB 0x80 /* 分周比レジスタアクセス許可 */
#define UART_LCR_8N1 0x03  /* 8 ビット / パリティなし / ストップビット 1 */
#define UART_DIVISOR_115200 0x0001

void serial_init(void) {
    outb(COM1_PORT + UART_REG_IER, 0x00);  /* 割り込みは使わずポーリングする */
    outb(COM1_PORT + UART_REG_LCR, UART_LCR_DLAB);
    outb(COM1_PORT + UART_REG_DATA, UART_DIVISOR_115200 & 0xFF);
    outb(COM1_PORT + UART_REG_IER, (UART_DIVISOR_115200 >> 8) & 0xFF);
    outb(COM1_PORT + UART_REG_LCR, UART_LCR_8N1);
    outb(COM1_PORT + UART_REG_FCR, 0xC7); /* FIFO 有効・閾値 14 バイト・全クリア */
    outb(COM1_PORT + UART_REG_MCR, 0x03); /* DTR / RTS をアサート */
}

static void serial_wait_for_transmit(void) {
    while ((inb(COM1_PORT + UART_REG_LSR) & UART_LSR_THRE) == 0) {
        __asm__ volatile("pause");
    }
}

void serial_write(char c) {
    serial_wait_for_transmit();
    outb(COM1_PORT + UART_REG_DATA, (uint8_t)c);
}

void serial_puts(const char *text) {
    if (text == NULL) {
        return; /* 早期ブートでは不正入力でも停止せず、出力だけ諦める */
    }
    for (size_t i = 0; text[i] != '\0'; i++) {
        if (text[i] == '\n') {
            serial_write('\r'); /* 端末側の改行位置を揃える */
        }
        serial_write(text[i]);
    }
}

/* ---------------------------------------------------------------------------
 * VGA テキストコンソール (80x25, 0xB8000)
 * ------------------------------------------------------------------------- */

#define VGA_WIDTH 80
#define VGA_HEIGHT 25
#define VGA_ATTR_LIGHT_GRAY_ON_BLACK 0x07

static volatile uint16_t *const vga_buffer = (volatile uint16_t *)0xB8000;
static size_t vga_row = 0;
static size_t vga_column = 0;

static uint16_t vga_cell(char c, uint8_t attribute) {
    return (uint16_t)(((uint16_t)attribute << 8) | (uint8_t)c);
}

static void vga_clear_row(size_t row) {
    for (size_t column = 0; column < VGA_WIDTH; column++) {
        vga_buffer[row * VGA_WIDTH + column] =
            vga_cell(' ', VGA_ATTR_LIGHT_GRAY_ON_BLACK);
    }
}

void vga_clear(void) {
    for (size_t row = 0; row < VGA_HEIGHT; row++) {
        vga_clear_row(row);
    }
    vga_row = 0;
    vga_column = 0;
}

static void vga_scroll_up(void) {
    for (size_t row = 1; row < VGA_HEIGHT; row++) {
        for (size_t column = 0; column < VGA_WIDTH; column++) {
            size_t to = (row - 1) * VGA_WIDTH + column;
            size_t from = row * VGA_WIDTH + column;
            vga_buffer[to] = vga_buffer[from];
        }
    }
    vga_clear_row(VGA_HEIGHT - 1);
    vga_row = VGA_HEIGHT - 1;
}

static void vga_newline(void) {
    vga_column = 0;
    vga_row++;
    if (vga_row >= VGA_HEIGHT) {
        vga_scroll_up();
    }
}

void vga_putc(char c) {
    if (c == '\n') {
        vga_newline();
        return;
    }
    if (c == '\r') {
        vga_column = 0;
        return;
    }

    vga_buffer[vga_row * VGA_WIDTH + vga_column] =
        vga_cell(c, VGA_ATTR_LIGHT_GRAY_ON_BLACK);

    vga_column++;
    if (vga_column >= VGA_WIDTH) {
        vga_newline();
    }
}

void vga_puts(const char *text) {
    if (text == NULL) {
        return;
    }
    for (size_t i = 0; text[i] != '\0'; i++) {
        vga_putc(text[i]);
    }
}

/* ---------------------------------------------------------------------------
 * カーネル本体
 * ------------------------------------------------------------------------- */

static void console_puts(const char *text) {
    serial_puts(text);
    vga_puts(text);
}

__attribute__((noreturn)) void kernel_main(void) {
    serial_init();
    vga_clear();

    console_puts("Hello OS\n");
    console_puts("early console: serial COM1 (115200 8N1) + vga text 0xB8000\n");
    console_puts("boot complete, halting.\n");

    for (;;) {
        __asm__ volatile("cli; hlt");
    }
}

/*
 * boot.asm から呼ばれる C 側エントリポイント。
 * ここから先は戻らないため、戻り先を用意する必要はない。
 */
__attribute__((noreturn)) void _start(void) {
    kernel_main();
}
