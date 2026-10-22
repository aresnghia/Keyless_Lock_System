`include "Common_Params.v"

module Input_Buffer (
    input  wire        clk,
    input  wire        rst_n,
    
    // Tín hiệu từ Keypad_Scanner / Switch_Input
    input  wire [3:0]  key_code,
    input  wire        key_valid,
    input  wire        is_function,
    
    // Tín hiệu từ Main_FSM (Điều khiển)
    input  wire        clear_req,      // Lệnh xóa buffer từ FSM (chuyển state, báo lỗi...)
    
    // Ngõ ra
    output reg  [23:0] buffer_data,  // Dữ liệu 6 số đã nhập
    output reg  [2:0]  digit_count,  // Số lượng phím đã nhập (0 đến 6)
    output reg         enter_pressed // Cờ báo người dùng đã bấm Enter (Xung 1 clock)
);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            buffer_data   <= 24'h000000;
            digit_count   <= 3'd0;
            enter_pressed <= 1'b0;
        end else begin
            
            // =========================================================
            // 1. ƯU TIÊN CAO NHẤT: Lệnh xóa khẩn cấp từ Giám đốc FSM
            // =========================================================
            if (clear_req) begin
                buffer_data   <= 24'h000000;
                digit_count   <= 3'd0;
                enter_pressed <= 1'b0;
            end 
            
            // =========================================================
            // 2. KHI CÓ PHÍM MỚI ĐƯỢC BẤM
            // =========================================================
            else if (key_valid) begin
                
                // Mặc định hạ cờ enter xuống (chỉ bật lên ở đúng case KEY_ENT)
                enter_pressed <= 1'b0; 

                // ------------------------------------------
                // Trường hợp A: Phím CHỨC NĂNG
                // ------------------------------------------
                if (is_function) begin
                    case (key_code)
                        `KEY_CLR: begin // Xóa trắng
                            buffer_data <= 24'h000000;
                            digit_count <= 3'd0;
                        end
                        
                        `KEY_BACK: begin // Xóa lùi 1 số (Backspace)
                            if (digit_count > 3'd0) begin
                                // Dịch phải 4 bit, điền 0 vào bên trái
                                buffer_data <= {4'h0, buffer_data[23:4]};
                                digit_count <= digit_count - 1'b1;
                            end
                        end
                        
                        `KEY_ENT: begin // Xác nhận
                            if (digit_count == 3'd6) begin
                                enter_pressed <= 1'b1; // Phát xung cờ cho FSM
                            end
                        end
                        
                        // Nếu là KEY_HIDE (SW9), Input_Buffer không cần xử lý dữ liệu.
                        // Main_FSM sẽ tự bắt xung KEY_HIDE để vẽ lại LCD.
                        default: ; 
                    endcase
                end 
                
                // ------------------------------------------
                // Trường hợp B: Phím SỐ (0-9)
                // ------------------------------------------
                else begin
                    if (digit_count < 3'd6) begin
                        // Dịch trái 4 bit, nhét số mới vào đuôi bên phải
                        buffer_data <= {buffer_data[19:0], key_code};
                        digit_count <= digit_count + 1'b1;
                    end
                end
            end 
            
            // =========================================================
            // 3. KHI KHÔNG CÓ PHÍM BẤM
            // =========================================================
            else begin
                // Đảm bảo cờ Enter bị dập tắt ở chu kỳ tiếp theo (tạo pulse)
                enter_pressed <= 1'b0; 
            end
        end
    end

endmodule