`timescale 1ns/1ps

module tb_Digital_Lock_Top();

    // -----------------------------------------------------------
    // 1. KHAI BÁO TÍN HIỆU GIẢ LẬP
    // -----------------------------------------------------------
    reg        CLOCK_50;
    reg [3:0]  KEY;     // KEY[0]=Reset, KEY[1]=Enter/Chốt, KEY[2]=Back, KEY[3]=Clear
    reg [9:0]  SW;      // SW[3:0]=Số, SW[7]=Change, SW[8]=Mode, SW[9]=Hide

    wire [7:0] LCD_DATA;
    wire       LCD_EN, LCD_RS, LCD_RW, LCD_ON;
    wire       LEDG0;   // Đèn báo mở khóa
    wire [4:0] LEDR;    // Đèn báo lỗi

    // -----------------------------------------------------------
    // 2. KẾT NỐI VỚI TOP MODULE (Device Under Test - DUT)
    // -----------------------------------------------------------
    Digital_Lock_Top dut (
        .CLOCK_50 (CLOCK_50),
        .KEY      (KEY),
        .SW       (SW),
        .LCD_DATA (LCD_DATA),
        .LCD_EN   (LCD_EN),
        .LCD_RS   (LCD_RS),
        .LCD_RW   (LCD_RW),
        .LCD_ON   (LCD_ON),
        .LEDG0    (LEDG0),
        .LEDR     (LEDR)
    );

    // -----------------------------------------------------------
    // 3. TẠO XUNG CLOCK (50MHz -> Chu kỳ 20ns)
    // -----------------------------------------------------------
    initial begin
        CLOCK_50 = 0;
        forever #10 CLOCK_50 = ~CLOCK_50;
    end

    // -----------------------------------------------------------
    // 4. CÁC TASK GIẢ LẬP THAO TÁC CỦA NGƯỜI DÙNG
    // -----------------------------------------------------------
    
    // Task nhấn phím đa năng KEY[1] (Active-Low: Nhấn xuống 0 rồi nhả lên 1)
    task press_key1;
        begin
            KEY[1] = 1'b0; 
            #40; // Giữ nút trong 2 chu kỳ clock
            KEY[1] = 1'b1; 
            #40; // Nhả nút ra và chờ hệ thống xử lý
        end
    endtask

    // Task gạt Switch và chốt số
    task input_digit(input [3:0] digit);
        begin
            SW[8]   = 1'b0;    // Đảm bảo ở chế độ Nhập số
            SW[3:0] = digit;   // Gạt công tắc theo mã số
            #20;               // Đợi điện áp switch ổn định
            press_key1();      // Bấm KEY[1] để chốt số vào Buffer
        end
    endtask

    // Task gửi lệnh Enter (Xác nhận)
    task press_enter;
        begin
            SW[8] = 1'b1;      // Gạt công tắc SW[8] lên chế độ Lệnh
            #20;
            press_key1();      // Bấm KEY[1] để gửi lệnh ENT
        end
    endtask
	 
	 // Task nhấn phím KEY[2] (Xóa lùi - Backspace)
	 task press_backspace;
        begin
            KEY[2] = 1'b0; 
            #40; 
            KEY[2] = 1'b1; 
            #100; // Chờ LCD update
        end
    endtask

    // Task nhấn phím KEY[3] (Xóa sạch toàn bộ - Clear)
    task press_clear;
        begin
            KEY[3] = 1'b0; 
            #40; 
            KEY[3] = 1'b1; 
            #100; // Chờ LCD update
        end
	 endtask
    // -----------------------------------------------------------
    // 5. KỊCH BẢN TEST (TEST SEQUENCE)
    // -----------------------------------------------------------
    initial begin
        // Khởi tạo trạng thái rảnh tay (Chưa gạt, chưa bấm gì)
        KEY = 4'b1111; // Nút nhấn active-low nên mặc định là 1
        SW  = 10'd0;

        // --- BƯỚC 1: CẤP NGUỒN VÀ RESET ---
        $display("[%0t] BAT DAU KHOI DONG HE THONG", $time);
        KEY[0] = 1'b0; #50;  // Giữ nút Reset
        KEY[0] = 1'b1; #100; // Nhả nút Reset
        // Lúc này mạch đang ở S_SET_NEW chờ mật khẩu gốc
		  dut.u_fsm.hide_mode = 1'b0;
        // --- BƯỚC 2: CÀI ĐẶT MẬT KHẨU GỐC "070805" ---
        $display("[%0t] CAI DAT MAT KHAU GOC: 070805", $time);
        input_digit(4'h0);
        input_digit(4'h7);
        input_digit(4'h0);
        input_digit(4'h8);
        input_digit(4'h0);
        input_digit(4'h5);
		  #100;
        press_enter(); // Xác nhận lưu vào Password_Memory
        #200;
        // Lúc này mạch tự chuyển về S_IDLE

        // --- BƯỚC 3: TEST NHẬP MẬT KHẨU SAI "111111" ---
        $display("[%0t] TEST MO KHOA (PASS SAI: 111111)", $time);
        input_digit(4'h1);
        input_digit(4'h1);
        input_digit(4'h1);
        input_digit(4'h1);
        input_digit(4'h1);
        input_digit(4'h1);
		  #100;
        press_enter(); // Check pass
        #200;
        // Dự kiến: LEDR sẽ sáng báo lỗi 1 lần, quay về S_IDLE

        // --- BƯỚC 4: TEST NHẬP MẬT KHẨU ĐÚNG "070805" ---
        $display("[%0t] TEST MO KHOA (PASS DUNG: 070805)", $time);
        input_digit(4'h0);
        input_digit(4'h7);
        input_digit(4'h0);
        input_digit(4'h8);
        input_digit(4'h0);
        input_digit(4'h5);
		  #100;
        press_enter(); // Check pass
        #500;
        // Dự kiến: Đèn xanh LEDG0 sáng (Mở cửa thành công -> S_UNLOCKED)

        // --- BƯỚC 5: KHÓA CỬA LẠI ---
        $display("[%0t] KHOA CUA LAI", $time);
        press_enter(); // Đang mở cửa mà ấn ENT thì sẽ khóa lại
        #200;
        // Dự kiến: LEDG0 tắt, mạch về lại S_IDLE
		  $display("[%0t] TEST CHUC NANG DOI MAT KHAU", $time);
        
        // Nhấn nút đổi Pass (Gạt SW7 lên rồi hạ xuống tạo xung)
        SW[7] = 1'b1; #40; 
        SW[7] = 1'b0; #100;
        // Dự kiến LCD: |  MAT KHAU CU:  | / |    [______]    |

        // Nhập mật khẩu cũ (070805)
        input_digit(4'h0); input_digit(4'h7); input_digit(4'h0); 
        input_digit(4'h8); input_digit(4'h0); input_digit(4'h5);
        #100; press_enter(); #200;
        // Dự kiến LCD: |  MAT KHAU MOI: | / |    [______]    |

        // Nhập mật khẩu mới (999999)
        input_digit(4'h9); input_digit(4'h9); input_digit(4'h9); 
        input_digit(4'h9); input_digit(4'h9); input_digit(4'h9);
        #100; press_enter(); #200;
        // Dự kiến LCD: | ENTER PASSWORD:| / |    [______]    | (Lưu pass mới thành công)
		  $display("[%0t] TEST CHUC NANG XOA (BACK VA CLEAR)", $time);
        
        // 1. Nhập 0, 7, 0, 8
        $display("   -> Nhap 0, 7, 0, 8");
        input_digit(4'h0);
        input_digit(4'h7);
        input_digit(4'h0);
        input_digit(4'h8);
        #200; 
        // Dự kiến: Màn hình hiện [0708__]

        // 2. Xóa lùi 2 ký tự (số 8 và số 0)
        $display("   -> Bam BACKSPACE 2 lan (Xoa 8, roi xoa 0)");
        press_backspace();
        press_backspace();
        #200;
        // Dự kiến: Màn hình lùi về [07____]

        // 3. Nhập lại 0, 8
        $display("   -> Nhap lai 0, 8");
        input_digit(4'h0);
        input_digit(4'h8);
        #200;
        // Dự kiến: Màn hình lại hiện [0708__]

        // 4. Nhấn nút xóa sạch
        $display("   -> Bam CLEAR (Xoa sach)");
        press_clear();
        $display("[%0t] MO PHONG HOAN TAT", $time);
		  #200;	
        $stop; // Dừng ModelSim
    end
	 always @(posedge CLOCK_50) begin
        // Cứ mỗi khi FSM phát lệnh cập nhật màn hình (lcd_update = 1)
        if (dut.u_fsm.lcd_update) begin
            $display("\n==================================");
            $display("[%0t ns] MAN HINH LCD THAY DOI:", $time);
            $display("| %s |", dut.u_fsm.lcd_line1); // %s sẽ ép 128-bit thành chuỗi ASCII
            $display("| %s |", dut.u_fsm.lcd_line2);
            $display("==================================");
        end
    end
endmodule