`timescale 1ns/1ps
`include "Common_Params.v"

module Keypad_Scanner_tb();

    // --- 1. Khai báo tín hiệu ---
    reg clk;
    reg rst_n;
    wire [3:0] cols;
    wire [3:0] rows;
    wire [3:0] key_code;
    wire key_valid;
    wire is_function;

    // Các biến phục vụ kiểm tra tự động
    reg [3:0] exp_key;   // Kết quả mong đợi
    reg exp_is_func;     // Loại phím mong đợi
    integer pass_count = 0;
    integer fail_count = 0;

    // --- 2. Khởi tạo Module DUT (Device Under Test) ---
    Keypad_Scanner DUT (
        .clk(clk), .rst_n(rst_n), .cols(cols), .rows(rows),
        .key_code(key_code), .key_valid(key_valid), .is_function(is_function)
    );

    // --- 3. Tạo xung nhịp 50MHz ---
    initial clk = 0;
    always #10 clk = ~clk; 

    // --- 4. Mô hình hóa bàn phím vật lý (Physical Model) ---
    reg [1:0] p_row, p_col; 
    reg key_down;
    assign cols = (key_down && (rows[p_row] == 1'b0)) ? ~(4'b1 << p_col) : 4'b1111;

    // --- 5. Nhiệm vụ (Task) nhấn phím để code gọn hơn ---
    task press_key(input [1:0] r, input [1:0] c, input [3:0] e_key, input e_func, input integer duration_ms);
    begin
        exp_key = e_key; exp_is_func = e_func;
        p_row = r; p_col = c; key_down = 1;
        #(duration_ms * 1_000_000); // Đổi ms sang ns
        key_down = 0;
        #5_000_000; // Nghỉ 5ms giữa các lần nhấn
    end
    endtask

    // --- 6. Khối giám sát tự động (Monitor) ---
    always @(posedge clk) begin
        if (key_valid) begin
            $display("\n[CHECK] Thoi diem xac nhan: %0t ns", $time);
            // Soi thang vao row_temp va col_temp ben trong module
            $display("[INFO] Toa do chot trong module: R=%b, C=%b", DUT.row_temp, DUT.col_temp);
            
            if (key_code === exp_key && is_function === exp_is_func) begin
                $display("[PASS] Ma: %h | Loai: %s", key_code, (is_function ? "FUNC" : "NUM"));
                pass_count = pass_count + 1;
            end else begin
                $display("[FAIL] SAI MA! Mong doi: %h, Thuc te: %h", exp_key, key_code);
                fail_count = fail_count + 1;
            end
        end
    end

    // --- 7. Kịch bản kiểm thử chi tiết ---
    initial begin
        // Khởi tạo
        rst_n = 0; key_down = 0;
        #100 rst_n = 1;
        #1_000_000;

        // TC_01: Nhấn phím số 5 (Hàng 1, Cột 1) - Thành công
        $display("\nTC_01: Testing phím số 5...");
        press_key(2'd1, 2'd1, 4'h5, 1'b0, 30); // Nhấn 30ms

        // TC_02: Nhấn phím Enter (Hàng 3, Cột 2) - Thành công
        $display("\nTC_02: Testing phím Enter (#)...");
        press_key(2'd3, 2'd2, `KEY_ENT, 1'b1, 30);

        // TC_03: Nhiễu Glitch (Nhấn phím 8 nhưng chỉ 5ms) - Phải FAIL nhận diện (tức là Pass logic)
        $display("\nTC_03: Testing nhiễu (nhấn phím 8 chỉ 5ms)...");
        press_key(2'd2, 2'd1, 4'h8, 1'b0, 5); // Không được có output

        // TC_04: Ghosting
        $display("\nTC_04: Testing Ghosting (De 2 phim cung hang)...");
        exp_key = `KEY_NONE; exp_is_func = 1'b1;
        p_row = 2'd0; key_down = 1;
        force cols = 4'b1100; // Ép lỗi
        #30_000_000; 
        release cols;         // PHẢI GIẢI PHÓNG Ở ĐÂY
        key_down = 0;
        #5_000_000;

        // TC_05: Phím bị kẹt (Giữ phím số 1 trong 200ms)
        $display("\nTC_05: Testing phím bị kẹt (Giữ phím 1 trong 200ms)...");
        exp_key = `KEY_1; exp_is_func = 1'b0;
        p_row = 2'd0; p_col = 2'd0; key_down = 1; // Nhấn phím 1 thật sự
        #200_000_000; 
        key_down = 0;
        #10_000_000;
        #30_000_000; // Đợi 30ms
        release cols;
        key_down = 0;
			
        // Tổng kết
        #10_000_000;
        $display("\n========================================");
        $display("Tong so Test Pass: %0d", pass_count);
        $display("Tong so Test Fail: %0d", fail_count);
        if (fail_count == 0) $display(">>> KET QUA: MODULE HOAN HAO <<<");
        else $display(">>> KET QUA: CAN KIEM TRA LAI LOGIC <<<");
        $display("========================================\n");
        $stop;
    end
endmodule