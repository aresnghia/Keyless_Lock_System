`include "Common_Params.v"

// =============================================================================
// Module  : Switch_Input
// Chức năng: Thay thế Keypad_Scanner khi không có bàn phím vật lý
//            Dùng SW và KEY trên DE2 để nhập liệu
//
// Mapping phần cứng:
//   SW[3:0]  → Chữ số nhập (binary 4-bit, hợp lệ: 0000..1001 = 0..9)
//   SW[9]    → KEY_HIDE (gạt lên = bật, gạt xuống = tắt, edge-trigger)
//   KEY[1]   → KEY_ENT   (nhấn = xác nhận, active-low)
//   KEY[2]   → KEY_BACK  (nhấn = xóa 1 số,  active-low)
//   KEY[3]   → KEY_CLR   (nhấn = xóa hết,   active-low)
//
// Giao tiếp với Main_FSM: giống hệt Keypad_Scanner
//   key_valid   : pulse 1 cycle khi có phím hợp lệ
//   key_code    : mã phím (KEY_0..KEY_9, KEY_ENT, KEY_BACK, KEY_CLR, KEY_HIDE)
//   is_function : 1 nếu là phím chức năng
//
// Cơ chế hoạt động:
//   - KEY[3:1] (active-low): dùng edge detector posedge (sau khi đảo)
//     → Nhấn nút = tín hiệu đảo lên cao 1 cycle → key_valid pulse
//   - SW[3:0] (chữ số): giá trị trên switch được latch khi nhấn KEY[1] (ENT)
//     hoặc KEY[2] (BACK) — nhưng để nhập số riêng lẻ, cần thêm 1 nút ENTER_DIGIT
//     → Dùng KEY[1] làm "nhập chữ số hiện tại" KHI sw_mode = 0 (xem bên dưới)
//
// Luồng nhập 1 chữ số:
//   1. Gạt SW[3:0] về giá trị muốn nhập (VD: 0101 = 5)
//   2. Nhấn KEY[1] → key_valid=1, key_code=KEY_5
//   3. Gạt SW[3:0] về giá trị tiếp theo
//   4. Nhấn KEY[1] → key_valid=1, key_code=...
//   (Sau khi nhập đủ 6 số, nhấn KEY[1] lần nữa với SW = 0000 sẽ bị ignore)
//   *** Xem mục "Lưu ý thiết kế" bên dưới ***
//
// Lưu ý thiết kế — chế độ 2 giai đoạn:
//   Main_FSM cần phân biệt "nhập chữ số" vs "xác nhận ENT".
//   Vì chỉ có 3 KEY, giải pháp: dùng SW[8] làm cờ chế độ:
//     SW[8] = 0: KEY[1] = nhập chữ số từ SW[3:0]
//     SW[8] = 1: KEY[1] = ENT (xác nhận toàn bộ, chuyển state)
//   Như vậy:
//     - Nhập số: SW[8]=0, gạt SW[3:0], nhấn KEY[1] → key_code = digit
//     - Xác nhận: SW[8]=1, nhấn KEY[1] → key_code = KEY_ENT
// =============================================================================

module Switch_Input (
    input  wire        clk,
    input  wire        rst_n,

    // --- Phần cứng DE2 ---
    input  wire [9:0]  SW,          // SW[3:0]=digit, SW[8]=mode, SW[9]=HIDE
    input  wire [3:1]  KEY,         // Active-low: KEY[1]=confirm, KEY[2]=BACK, KEY[3]=CLR

    // --- Giao tiếp với Main_FSM (giống Keypad_Scanner) ---
    output reg  [3:0]  key_code,
    output reg         key_valid,
    output reg         is_function
);

// =============================================================================
// EDGE DETECTOR cho 3 KEY (active-low → đảo thành active-high trước)
// =============================================================================

    wire key1_h = ~KEY[1];   // KEY[1] active-high sau khi đảo
    wire key2_h = ~KEY[2];
    wire key3_h = ~KEY[3];

    reg  key1_prev, key2_prev, key3_prev;

    // Cạnh lên = vừa nhấn nút (active-low → posedge sau đảo)
    wire key1_edge = key1_h && !key1_prev;   // KEY[1]: digit/ENT
    wire key2_edge = key2_h && !key2_prev;   // KEY[2]: BACK
    wire key3_edge = key3_h && !key3_prev;   // KEY[3]: CLR

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            key1_prev <= 1'b0;
            key2_prev <= 1'b0;
            key3_prev <= 1'b0;
        end else begin
            key1_prev <= key1_h;
            key2_prev <= key2_h;
            key3_prev <= key3_h;
        end
    end

// =============================================================================
// EDGE DETECTOR cho SW[9] (HIDE toggle)
// SW[9] là toggle switch → chỉ trigger khi GẠT (thay đổi trạng thái)
// =============================================================================

    reg sw9_prev;
    wire sw9_edge = SW[9] ^ sw9_prev;   // Trigger cả 2 chiều gạt

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) sw9_prev <= 1'b0;
        else        sw9_prev <= SW[9];
    end

// =============================================================================
// LOGIC CHÍNH — Tạo key_valid, key_code, is_function
// =============================================================================

    // Kiểm tra SW[3:0] có phải chữ số hợp lệ (0..9)
    wire digit_valid = (SW[3:0] <= 4'd9);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            key_valid   <= 1'b0;
            key_code    <= `KEY_NONE;
            is_function <= 1'b0;
        end else begin
            // Mặc định: không có phím
            key_valid   <= 1'b0;
            key_code    <= `KEY_NONE;
            is_function <= 1'b0;

            // ── Ưu tiên 1: KEY[3] → CLR ──────────────────────────────
            if (key3_edge) begin
                key_valid   <= 1'b1;
                key_code    <= `KEY_CLR;
                is_function <= 1'b1;

            // ── Ưu tiên 2: KEY[2] → BACK ─────────────────────────────
            end else if (key2_edge) begin
                key_valid   <= 1'b1;
                key_code    <= `KEY_BACK;
                is_function <= 1'b1;

            // ── Ưu tiên 3: SW[9] gạt → HIDE ─────────────────────────
            end else if (sw9_edge) begin
                key_valid   <= 1'b1;
                key_code    <= `KEY_HIDE;
                is_function <= 1'b1;

            // ── Ưu tiên 4: KEY[1] ────────────────────────────────────
            //   SW[8]=0 → nhập chữ số từ SW[3:0]
            //   SW[8]=1 → gửi ENT
            end else if (key1_edge) begin
                if (SW[8]) begin
                    // Chế độ ENT
                    key_valid   <= 1'b1;
                    key_code    <= `KEY_ENT;
                    is_function <= 1'b1;
                end else begin
                    // Chế độ nhập số — chỉ chấp nhận 0..9
                    if (digit_valid) begin
                        key_valid   <= 1'b1;
                        key_code    <= SW[3:0];   // 0x0..0x9 khớp KEY_0..KEY_9
                        is_function <= 1'b0;
                    end
                    // Nếu SW[3:0] > 9 (VD: 1010..1111): bỏ qua, không fire
                end
            end
        end
    end

endmodule
