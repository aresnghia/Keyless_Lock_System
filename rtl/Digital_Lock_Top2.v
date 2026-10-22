`include "Common_Params.v"

// =============================================================================
// Module  : Digital_Lock_Top2
// Chức năng: Top-level module khóa số — phương án thay thế dùng SW + KEY
//            (khi không có bàn phím ma trận 4×4)
//
// So sánh với Digital_Lock_Top (bản gốc):
//   THAY:  Keypad_Scanner (cols/rows, GPIO_0)
//   BẰNG:  Switch_Input   (SW[9:0], KEY[3:1])
//   GIỮ:   Main_FSM, Password_Memory, Code_Checker, LCD_Driver (KHÔNG đổi)
//
// Pin mapping DE2:
//   CLOCK_50        → clk
//   KEY[0]          → rst_n         (active-low, giữ để reset)
//   KEY[1]          → digit/ENT     (tùy SW[8])
//   KEY[2]          → BACK          (xóa 1 số)
//   KEY[3]          → CLR           (xóa hết)
//   SW[3:0]         → Chữ số nhập (0000=0 .. 1001=9)
//   SW[8]           → Chế độ: 0=nhập số, 1=gửi ENT
//   SW[9]           → Toggle HIDE (ẩn/hiện mật khẩu)
//   KEY[1] (dùng SW[7]) → Nút đổi mật khẩu (xem bên dưới)
//
// Nút đổi mật khẩu:
//   Vì KEY[1..3] đã dùng hết, dùng SW[7] làm "nút" đổi mật khẩu:
//   Gạt SW[7] lên (0→1) = tương đương nhấn change_pass_btn
//   Main_FSM dùng edge detector nên chỉ trigger 1 lần khi gạt
//
// Hướng dẫn nhập 1 lần (ví dụ nhập mật khẩu 123456):
//   1. SW[8]=0 (chế độ nhập số)
//   2. Gạt SW[3:0]=0001, nhấn KEY[1] → nhập "1"
//   3. Gạt SW[3:0]=0010, nhấn KEY[1] → nhập "2"
//   4. ... tiếp tục đến "6"
//   5. Gạt SW[8]=1 (chế độ ENT), nhấn KEY[1] → xác nhận
// =============================================================================

module Digital_Lock_Top2 (
    // --- Clock & Reset ---
    input  wire        CLOCK_50,
    input  wire [3:0]  KEY,             // KEY[0]=rst_n, KEY[1..3]=chức năng

    // --- Switch input ---
    input  wire [9:0]  SW,              // SW[3:0]=digit, SW[7]=change_btn,
                                        // SW[8]=mode, SW[9]=HIDE

    // --- LCD HD44780 ---
    output wire [7:0]  LCD_DATA,
    output wire        LCD_EN,
    output wire        LCD_RS,
    output wire        LCD_RW,
    output wire        LCD_ON,

    // --- LED ngõ ra ---
    output wire        LEDG,            // LEDG[0]: mở khóa
    output wire [4:0]  LEDR,            // LEDR[4:0]: đếm lỗi

    // --- LED trạng thái input (debug trực quan) ---
    output wire [3:0]  LEDG_SW,         // LEDG[4:1]: hiển thị SW[3:0] đang gạt
    output wire        LEDG_MODE,       // LEDG[5]: SW[8] mode (0=digit, 1=ENT)
    output wire        LEDG_HIDE,       // LEDG[6]: SW[9] HIDE đang bật

    // --- Debug ---
    output wire [2:0]  state_dbg
);

// =============================================================================
// TÍN HIỆU NỘI BỘ
// =============================================================================

    wire clk   = CLOCK_50;
    wire rst_n = KEY[0];

    // SW[7] làm change_pass_btn (edge detector trong Main_FSM xử lý)
    wire change_pass_btn = SW[7];

    // ── Switch_Input → Main_FSM ──
    wire        key_valid;
    wire [3:0]  key_code;
    wire        is_function;

    // ── Main_FSM → Code_Checker ──
    wire        en_compare;
    wire        clear_flag;
    wire [23:0] input_buffer;

    // ── Main_FSM → Password_Memory ──
    wire        write_en;
    wire [23:0] new_password;

    // ── Password_Memory → Main_FSM & Code_Checker ──
    wire [23:0] stored_password;
    wire        pwd_is_set;

    // ── Code_Checker → Main_FSM ──
    wire        match_flag;

    // ── Main_FSM → LCD_Driver ──
    wire [127:0] lcd_line1;
    wire [127:0] lcd_line2;
    wire         lcd_update;

    // ── Main_FSM → LED ──
    wire        unlock_led;
    wire [4:0]  error_leds;

// =============================================================================
// INSTANTIATION
// =============================================================================

    // ------------------------------------------------------------------
    // 1. Switch_Input (thay thế Keypad_Scanner)
    // ------------------------------------------------------------------
    Switch_Input u_switch (
        .clk        (clk),
        .rst_n      (rst_n),
        .SW         (SW),
        .KEY        (KEY[3:1]),
        .key_code   (key_code),
        .key_valid  (key_valid),
        .is_function(is_function)
    );

    // ------------------------------------------------------------------
    // 2. Password_Memory (không đổi)
    // ------------------------------------------------------------------
    Password_Memory u_pwd_mem (
        .clk          (clk),
        .rst_n        (rst_n),
        .write_en     (write_en),
        .new_password (new_password),
        .pwd_out      (stored_password),
        .pwd_is_set   (pwd_is_set)
    );

    // ------------------------------------------------------------------
    // 3. Code_Checker (không đổi)
    // ------------------------------------------------------------------
    Code_Checker u_checker (
        .clk             (clk),
        .rst_n           (rst_n),
        .input_buffer    (input_buffer),
        .stored_password (stored_password),
        .en_compare      (en_compare),
        .clear_flag      (clear_flag),
        .match_flag      (match_flag)
    );

    // ------------------------------------------------------------------
    // 4. Main_FSM (không đổi, chỉ thay nguồn key_valid/key_code)
    // ------------------------------------------------------------------
    Main_FSM u_fsm (
        .clk             (clk),
        .rst_n           (rst_n),
        .key_valid       (key_valid),
        .key_code        (key_code),
        .is_function     (is_function),
        .match_flag      (match_flag),
        .en_compare      (en_compare),
        .clear_flag      (clear_flag),
        .input_buffer    (input_buffer),
        .pwd_is_set      (pwd_is_set),
        .write_en        (write_en),
        .new_password    (new_password),
        .lcd_line1       (lcd_line1),
        .lcd_line2       (lcd_line2),
        .lcd_update      (lcd_update),
        .change_pass_btn (change_pass_btn),
        .unlock_led      (unlock_led),
        .error_leds      (error_leds),
        .state_out       (state_dbg)
    );

    // ------------------------------------------------------------------
    // 5. LCD_Driver (không đổi)
    // ------------------------------------------------------------------
    LCD_Driver u_lcd (
        .clk        (clk),
        .rst_n      (rst_n),
        .lcd_line1  (lcd_line1),
        .lcd_line2  (lcd_line2),
        .lcd_update (lcd_update),
        .LCD_DATA   (LCD_DATA),
        .LCD_EN     (LCD_EN),
        .LCD_RS     (LCD_RS),
        .LCD_RW     (LCD_RW),
        .LCD_ON     (LCD_ON)
    );

// =============================================================================
// KẾT NỐI LED
// =============================================================================

    assign LEDG      = unlock_led;
    assign LEDR      = error_leds;

    // LED debug trực quan — giúp kiểm tra input không cần LCD
    assign LEDG_SW   = SW[3:0];        // LEDG[4:1]: hiện giá trị SW đang gạt
    assign LEDG_MODE = SW[8];          // LEDG[5]: 0=nhập số, 1=ENT mode
    assign LEDG_HIDE = SW[9];          // LEDG[6]: HIDE đang bật/tắt

endmodule
