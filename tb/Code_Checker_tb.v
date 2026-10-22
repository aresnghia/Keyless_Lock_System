`timescale 1ns/1ps

module Code_Checker_tb();

    // 1. Khai báo tín hiệu
    reg clk;
    reg rst_n;
    reg [23:0] input_buffer;
    reg [23:0] stored_password;
    reg en_compare;
    reg clear_flag;
    wire match_flag;

    // Các biến đếm để xuất báo cáo
    integer pass_cnt = 0;
    integer fail_cnt = 0;

    // 2. Khởi tạo DUT (Device Under Test)
    Code_Checker DUT (
        .clk(clk),
        .rst_n(rst_n),
        .input_buffer(input_buffer),
        .stored_password(stored_password),
        .en_compare(en_compare),
        .clear_flag(clear_flag),
        .match_flag(match_flag)
    );

    // 3. Tạo Clock (50MHz)
    initial clk = 0;
    always #10 clk = ~clk;

    // -------------------------------------------------------
    // TASK: Tự động hóa quá trình test và kiểm tra kết quả
    // -------------------------------------------------------
    task check_case(
        input [80*8:1] tc_name,     // Tên chuỗi test
        input [23:0] in_buf,        // Dữ liệu nhập
        input [23:0] pw_stored,     // Mật khẩu gốc
        input en,                   // Xung Enter
        input clr,                  // Xung Clear
        input exp_match             // Kết quả kỳ vọng
    );
    begin
        // Nạp đầu vào
        input_buffer = in_buf;
        stored_password = pw_stored;
        en_compare = en;
        clear_flag = clr;
        
        // Đợi 1 chu kỳ clock để mạch Sequential (Flip-Flop) chốt dữ liệu
        @(posedge clk);
        #2; // Đợi thêm một chút để tránh so sánh ngay đúng cạnh sườn

        // Kiểm tra tự động
        if (match_flag === exp_match) begin
            $display("[PASS] %s", tc_name);
            pass_cnt = pass_cnt + 1;
        end else begin
            $display("[FAIL] %s | Mong doi: %b, Thuc te: %b", tc_name, exp_match, match_flag);
            $display("       -> In: %h | PW: %h | EN: %b | CLR: %b", in_buf, pw_stored, en, clr);
            fail_cnt = fail_cnt + 1;
        end

        // Trả các xung điều khiển về 0 (nhả nút)
        en_compare = 0;
        clear_flag = 0;
        #20; // Nghỉ một chút trước nhịp test tiếp theo
    end
    endtask

    // -------------------------------------------------------
    // KỊCH BẢN TEST CHI TIẾT
    // -------------------------------------------------------
    initial begin
        // --- KHỞI TẠO ---
        $display("=== BAT DAU TESTBENCH PASSWORD CHECKER ===");
        rst_n = 0;
        input_buffer = 24'h0;
        stored_password = 24'h0;
        en_compare = 0;
        clear_flag = 0;
        #100 rst_n = 1; // Nhả reset

        // --- TC_01: MẬT KHẨU ĐÚNG (Nhiều trường hợp) ---
        $display("\n--- TC_01: Test Mat Khau Dung ---");
        // Giả sử mã 123456 (Hex)
        check_case("TC_01.1 - Ma 123456", 24'h123456, 24'h123456, 1'b1, 1'b0, 1'b1);
        // Cần Clear để đóng cửa lại trước khi test mã mới
        check_case("TC_01.x - Xoa trang thai", 24'h0, 24'h0, 1'b0, 1'b1, 1'b0);
        // Mã toàn số 0
        check_case("TC_01.2 - Ma 000000", 24'h000000, 24'h000000, 1'b1, 1'b0, 1'b1);
        check_case("TC_01.x - Xoa trang thai", 24'h0, 24'h0, 1'b0, 1'b1, 1'b0);

        // --- TC_02: MẬT KHẨU SAI (Nhiều trường hợp) ---
        $display("\n--- TC_02: Test Mat Khau Sai ---");
        // Lệch hoàn toàn
        check_case("TC_02.1 - Sai hoan toan", 24'h111111, 24'h987654, 1'b1, 1'b0, 1'b0);
        // Sai số cuối cùng (Dễ lỗi)
        check_case("TC_02.2 - Sai so cuoi", 24'h123457, 24'h123456, 1'b1, 1'b0, 1'b0);
        // Chỉ sai lệch 1 bit duy nhất (Cực kỳ dễ lỗi mạch tổ hợp)
        check_case("TC_02.3 - Sai 1 bit", 24'h123456, 24'h123454, 1'b1, 1'b0, 1'b0);

        // --- TC_03: LỖI "VỘI VÀNG" ---
        $display("\n--- TC_03: Quen Nhan Enter ---");
        // Nhập đúng 100% nhưng KHÔNG nhấn Enter (en_compare = 0)
        check_case("TC_03.1 - Dung Pass nhung khong Enter", 24'hABCDEF, 24'hABCDEF, 1'b0, 1'b0, 1'b0);

        // --- TC_04: XUNG ĐỘT TÍN HIỆU ---
        $display("\n--- TC_04: Xung Dot Tin Hieu ---");
        // Vừa Enter vừa Clear (Module thiết kế ưu tiên Clear)
        check_case("TC_04.1 - Enter + Clear cung luc", 24'h999999, 24'h999999, 1'b1, 1'b1, 1'b0);

        // --- TC_05: NHIỄU DỮ LIỆU SAU KHI MỞ CỬA ---
        $display("\n--- TC_05: Nhieu Du Lieu Sau Khi Mo ---");
        // 1. Mở cửa thành công
        check_case("TC_05.1 - Mo cua OK", 24'h654321, 24'h654321, 1'b1, 1'b0, 1'b1);
        // 2. Tín hiệu Enter mất, và Input bị nhiễu nhảy loạn xạ
        // Lúc này mạch phải "nhớ" trạng thái MỞ (match_flag = 1)
        check_case("TC_05.2 - Thay doi Input (Nhieu)", 24'h111111, 24'h654321, 1'b0, 1'b0, 1'b1);
        check_case("TC_05.3 - Thay doi Input tiep", 24'hFFFFFF, 24'h654321, 1'b0, 1'b0, 1'b1);
        
        // 3. Cho đến khi nhấn Clear
        check_case("TC_05.4 - Nhan Clear de Dong cua", 24'hFFFFFF, 24'h654321, 1'b0, 1'b1, 1'b0);

        // --- TỔNG KẾT ---
        $display("\n========================================");
        $display("          BAO CAO KIEM THU              ");
        $display("========================================");
        $display("Tong so Test Pass: %0d", pass_cnt);
        $display("Tong so Test Fail: %0d", fail_cnt);
        if (fail_cnt == 0) $display(">>> KET QUA: MODULE HOAT DONG XUAT SAC <<<");
        else $display(">>> KET QUA: CO LOI - CAN DEBUG <<<");
        $display("========================================\n");
        $stop;
    end

endmodule