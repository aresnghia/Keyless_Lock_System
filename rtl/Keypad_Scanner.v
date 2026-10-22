`include "Common_Params.v"

// =============================================================================
// Module  : Keypad_Scanner
// Chức năng: Quét ma trận phím 4x4, chống dội (debounce), giải mã mã phím
// Clock   : 50 MHz (clk)
// Reset   : Bất đồng bộ, tích cực mức thấp (rst_n)
//
// Ngõ vào : clk, rst_n        -- Clock hệ thống & Reset
//           cols [3:0]        -- Tín hiệu cột từ bàn phím (active-low, one-hot)
// Ngõ ra  : rows [3:0]        -- Tín hiệu hàng quét ra bàn phím (active-low)
//           key_code [3:0]    -- Mã phím được nhấn (xem Common_Params.v)
//           key_valid         -- Pulse 1 cycle: có phím hợp lệ vừa được nhận
//           is_function       -- 1 nếu key_code là phím chức năng (ENT/CLR/...)
// =============================================================================

module Keypad_Scanner(
    input  wire       clk,
    input  wire       rst_n,
    input  wire [3:0] cols,
    output reg  [3:0] rows,
    output reg  [3:0] key_code,
    output reg        key_valid,
    output reg        is_function
);

// -----------------------------------------------------------------------------
// 1. CLOCK DIVIDER — Tạo xung scan_en tần số 1 kHz từ clock 50 MHz
//    Chu kỳ đếm: 50_000 cycles → scan_en pulse mỗi 1 ms
// -----------------------------------------------------------------------------
    reg [15:0] clk_div;
    wire scan_en = (clk_div == 16'd50000);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)       clk_div <= 16'd0;
        else if (scan_en) clk_div <= 16'd0;
        else              clk_div <= clk_div + 1'b1;
    end

// -----------------------------------------------------------------------------
// 2. ROW SCANNER — Tuần tự kích hoạt từng hàng (active-low, one-hot)
//    Chỉ advance sang hàng tiếp theo khi:
//      - scan_en = 1 (mỗi 1 ms)
//      - cols == 4'b1111 (không có phím nào đang nhấn trên hàng hiện tại)
//    Mục đích: Giữ nguyên hàng khi đang nhấn để debounce đọc tọa độ ổn định
// -----------------------------------------------------------------------------
    reg [1:0] row_index;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            row_index <= 2'd0;
            rows      <= 4'b1110;       // Bắt đầu từ hàng 0
        end else if (scan_en && (cols == 4'b1111)) begin
            row_index <= row_index + 1'b1;
            case (row_index + 1'b1)
                2'd0: rows <= 4'b1110;  // Hàng 0
                2'd1: rows <= 4'b1101;  // Hàng 1
                2'd2: rows <= 4'b1011;  // Hàng 2
                2'd3: rows <= 4'b0111;  // Hàng 3
            endcase
        end
    end

// -----------------------------------------------------------------------------
// 3. DEBOUNCE & CAPTURE — Chống dội phím, capture tọa độ khi ổn định
//
//    Luồng xử lý (ưu tiên từ cao đến thấp):
//      [1] cols thay đổi so với cycle trước
//              → Reset bộ đếm + xóa key_valid
//              → GIỮ key_pressed_flag để chặn double-fire khi trượt phím
//      [2] cols ổn định, one-hot hợp lệ, không phải 4'b1111
//              → Đếm debounce đến 1_000_000 cycles (= 20 ms @ 50 MHz)
//              → Nếu đủ thời gian VÀ chưa fire lần nào: pulse key_valid 1 cycle
//      [3] Còn lại (nhả phím hoặc nhấn nhiều phím cùng lúc)
//              → Reset toàn bộ, sẵn sàng cho lần nhấn tiếp theo
// -----------------------------------------------------------------------------
    reg [19:0] debounce_cnt;
    reg  [3:0] cols_last;
    reg        key_pressed_flag;
    reg  [3:0] col_temp, row_temp;

    // Kiểm tra cols có phải one-hot hợp lệ không (đúng 1 bit = 0)
    wire valid_column = (cols == 4'b1110) || (cols == 4'b1101) ||
                        (cols == 4'b1011) || (cols == 4'b0111);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            debounce_cnt     <= 20'd0;
            key_valid        <= 1'b0;
            key_pressed_flag <= 1'b0;
            cols_last        <= 4'b1111;
            col_temp         <= 4'b1111;
            row_temp         <= 4'b1111;
        end else begin
            cols_last <= cols;          // Luôn cập nhật để phát hiện thay đổi

            // [1] Phím đang dịch chuyển → reset đếm, chờ ổn định
            if (cols != cols_last) begin
                debounce_cnt <= 20'd0;
                key_valid    <= 1'b0;
                // key_pressed_flag giữ nguyên:
                //   nếu đã fire rồi, chặn fire thêm khi trượt sang phím kề
                //   chỉ clear khi nhả hoàn toàn (cols == 4'b1111, nhánh [3])
            end

            // [2] Phím ổn định, tọa độ one-hot hợp lệ → chạy debounce
            else if (cols != 4'b1111 && valid_column) begin
                if (debounce_cnt < 20'd1_000_000) begin
                    debounce_cnt <= debounce_cnt + 1'b1;    // Đang đếm
                    key_valid    <= 1'b0;
                end else if (!key_pressed_flag) begin
                    // Đủ 20 ms + chưa fire → capture và phát pulse
                    key_valid        <= 1'b1;
                    key_pressed_flag <= 1'b1;
                    col_temp         <= cols;
                    row_temp         <= rows;
                end else begin
                    key_valid <= 1'b0;                      // Đã fire, giữ phím
                end
            end

            // [3] Nhả phím (cols == 4'b1111) hoặc đè nhiều phím → reset hết
            else begin
                debounce_cnt     <= 20'd0;
                key_pressed_flag <= 1'b0;
                key_valid        <= 1'b0;
            end
        end
    end

// -----------------------------------------------------------------------------
// 4. DECODER — Giải mã {row_temp, col_temp} → key_code + is_function
//
//    Bàn phím layout (active-low, nhìn từ phía người dùng):
//
//              COL3(0111) COL2(1011) COL1(1101) COL0(1110)
//    ROW0(1110)    *          3          2          1
//    ROW1(1101)    #(HIDE)    6          5          4
//    ROW2(1011)    D(ENT)     9          8          7
//    ROW3(0111)    C(CLR)     B(BACK)    0          ?(unused)
//
//    Chú ý: col_temp/row_temp chỉ thay đổi khi key_valid = 1
//           nên key_code ổn định cho đến lần nhấn tiếp theo
// -----------------------------------------------------------------------------
    always @(*) begin
        is_function = 1'b0;
        case ({row_temp, col_temp})
            // --- H�NG 1 (1 2 3 A) ---
            8'b1110_1110: key_code = `KEY_1;
            8'b1110_1101: key_code = `KEY_2;
            8'b1110_1011: key_code = `KEY_3;
            8'b1110_0111: begin key_code = `KEY_ENT;  is_function = 1'b1; end // Ph�m A -> Enter

            // --- H�NG 2 (4 5 6 B) ---
            8'b1101_1110: key_code = `KEY_4;
            8'b1101_1101: key_code = `KEY_5;
            8'b1101_1011: key_code = `KEY_6;
            8'b1101_0111: begin key_code = `KEY_BACK; is_function = 1'b1; end // Ph�m B -> X�a 1 k� t?

            // --- H�NG 3 (7 8 9 C) ---
            8'b1011_1110: key_code = `KEY_7;
            8'b1011_1101: key_code = `KEY_8;
            8'b1011_1011: key_code = `KEY_9;
            8'b1011_0111: begin key_code = `KEY_CLR;  is_function = 1'b1; end // Ph�m C -> X�a s?ch

            // --- H�NG 4 (* 0 # D) ---
            8'b0111_1110: begin key_code = `KEY_NONE; is_function = 1'b1; end // Ph�m * (Ch?a d�ng)
            8'b0111_1101: key_code = `KEY_0;
            8'b0111_1011: begin key_code = `KEY_NONE; is_function = 1'b1; end // Ph�m # (Ch?a d�ng)
            8'b0111_0111: begin key_code = `KEY_HIDE; is_function = 1'b1; end // Ph�m D -> ?n/Hi?n pass

            // --- T?a ?? kh�ng h?p l? ---
            default: begin
                key_code    = `KEY_NONE;
                is_function = 1'b1;
            end
        endcase
    end

endmodule

