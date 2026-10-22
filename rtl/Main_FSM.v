`include "Common_Params.v"

module Main_FSM (
    input  wire        clk,
    input  wire        rst_n,

    // --- 1. Giao tiếp với Switch_Input ---
    input  wire        key_valid,
    input  wire [3:0]  key_code,

    // --- 2. Giao tiếp với Input_Buffer ---
    input  wire [23:0] buffer_data,   
    input  wire [2:0]  digit_count,   
    input  wire        enter_pressed, 
    output reg         clear_req,     

    // --- 3. Giao tiếp với Code_Checker ---
    input  wire        match_flag,
    output reg         en_compare,

    // --- 4. Giao tiếp với Password_Memory ---
    input  wire        pwd_is_set,
    output reg         write_en,

    // --- 5. Giao tiếp với LCD_Driver ---
    output reg [127:0] lcd_line1,
    output reg [127:0] lcd_line2,
    output reg         lcd_update,

    // --- 6. Phần cứng DE2 ---
    input  wire        change_pass_btn,
    output reg         unlock_led,
    output reg [4:0]   error_leds,

    output wire [2:0]  state_out
);

    // =============================================================================
    // KHAI BÁO TRẠNG THÁI
    // =============================================================================
    localparam [2:0]
        S_RESET    = 3'd0,
        S_SET_NEW  = 3'd1,
        S_IDLE     = 3'd2,
        S_CHANGE   = 3'd3,
        S_CHECK    = 3'd4,
        S_UNLOCKED = 3'd5,
        S_ERROR    = 3'd6;

    reg [2:0] state;
    assign state_out = state;

    reg [2:0]  error_count;
    reg        change_pass;
    reg        hide_mode;
    
    // --- THÊM: Biến đếm 60 giây (32-bit để đếm tới 3 tỷ) ---
    reg [31:0] lock_timer;
    // 50MHz * 60s = 3,000,000,000 cycles
    localparam [31:0] LOCK_DELAY = 32'd3_000_000_000; 
    
    // Xử lý nút cứng (Đổi pass)
    reg       btn_prev;
    wire btn_posedge = change_pass_btn && !btn_prev;

    localparam [2:0] MAX_ERRORS = 3'd5;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) btn_prev <= 1'b0;
        else        btn_prev <= change_pass_btn;
    end

    // =============================================================================
    // LOGIC CẬP NHẬT LCD TỰ ĐỘNG
    // =============================================================================
    reg [2:0]  prev_count;
    reg [23:0] prev_buf;
    reg        prev_hide;
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            prev_count <= 3'd0;
            prev_buf   <= 24'd0;
            prev_hide  <= 1'b1;
        end else begin
            prev_count <= digit_count;
            prev_buf   <= buffer_data;
            prev_hide  <= hide_mode;
        end
    end
    
    wire lcd_needs_update = (digit_count != prev_count) || 
                            (buffer_data != prev_buf) || 
                            (hide_mode != prev_hide);

    // =============================================================================
    // MÁY TRẠNG THÁI LÕI
    // =============================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state       <= S_RESET;
            error_count <= 3'd0;
            lock_timer  <= 32'd0; // Reset Timer
            change_pass <= 1'b0;
            hide_mode   <= 1'b1;
            
            clear_req   <= 1'b0;
            en_compare  <= 1'b0;
            write_en    <= 1'b0;
            
            unlock_led  <= 1'b0;
            error_leds  <= 5'd0;
            lcd_line1   <= `MSG_IDLE;
            lcd_line2   <= {16{8'h20}};
            lcd_update  <= 1'b0;
        end else begin

            clear_req  <= 1'b0;
            en_compare <= 1'b0;
            write_en   <= 1'b0;
            lcd_update <= 1'b0;

            if (key_valid && key_code == `KEY_HIDE) begin
                hide_mode <= ~hide_mode;
            end

            if (lcd_needs_update) begin
                lcd_update <= 1'b1;
                // Không tự động vẽ lại màn hình nếu đang bị khóa
                if (state == S_UNLOCKED) begin
                    lcd_line2 <= `MSG_UNLOCKED;
                end else if (state != S_ERROR || error_count < MAX_ERRORS - 1) begin
                    lcd_line2 <= rebuild_line2(digit_count, buffer_data, hide_mode);
                end
            end

            case (state)
                
                S_RESET: begin
                    error_count <= 3'd0;
                    lock_timer  <= 32'd0;
                    change_pass <= 1'b0;
                    unlock_led  <= 1'b0;
                    error_leds  <= 5'd0;
                    clear_req   <= 1'b1; 
                    
                    if (!pwd_is_set) begin
                        change_pass <= 1'b1;
                        lcd_line1   <= `MSG_SET_INIT;
                    end else begin
                        lcd_line1   <= `MSG_IDLE;
                    end
                    lcd_update <= 1'b1;
                    state      <= S_SET_NEW;
                end

                S_SET_NEW: begin
                    unlock_led <= 1'b0;
                    if (enter_pressed) begin
                        write_en    <= 1'b1;  
                        change_pass <= 1'b0;
                        clear_req   <= 1'b1;  
                        
                        lcd_line1   <= `MSG_IDLE;
                        lcd_update  <= 1'b1;
                        state       <= S_IDLE;
                    end
                end

                S_IDLE: begin
                    error_leds <= error_count;
                        
                    if (lcd_line1 == `MSG_WRONG) begin
                        lcd_line1 <= `MSG_IDLE;
                        lcd_update <= 1'b1;
                    end
                          
                    if (btn_posedge) begin
                        change_pass <= 1'b1;
                        clear_req   <= 1'b1;
                        lcd_line1   <= `MSG_CHG_OLD;
                        lcd_update  <= 1'b1;
                        state       <= S_CHANGE;
                    end 
                    else if (enter_pressed) begin
                        en_compare <= 1'b1;
                        state      <= S_CHECK; 
                    end
                end

                S_CHANGE: begin
                    if (enter_pressed) begin
                        en_compare <= 1'b1;
                        state      <= S_CHECK;
                    end
                end

                S_CHECK: begin
                    clear_req  <= 1'b1; 
                    
                    if (match_flag) begin
                        if (change_pass) begin
                            lcd_line1  <= `MSG_SET_NEW;
                            lcd_update <= 1'b1;
                            state      <= S_SET_NEW;
                        end else begin
                            unlock_led <= 1'b1;
                            lcd_line1  <= `MSG_CORRECT;
                            lcd_line2  <= `MSG_UNLOCKED;
                            lcd_update <= 1'b1;
                            state      <= S_UNLOCKED;
                        end
                    end else begin
                        state <= S_ERROR;
                    end
                end

                S_UNLOCKED: begin
                    unlock_led  <= 1'b1;
                    error_count <= 3'd0;
                    error_leds  <= 5'd0;

                    if (key_valid && key_code == `KEY_ENT) begin
                        unlock_led <= 1'b0;
                        clear_req  <= 1'b1;
                        lcd_line1  <= `MSG_IDLE;
                        lcd_update <= 1'b1;
                        state      <= S_IDLE;
                    end
                end

                S_ERROR: begin
                    if (error_count < MAX_ERRORS - 1) begin
                        error_count <= error_count + 1'b1;
                        error_leds  <= error_count + 1'b1;
                        lcd_line1   <= `MSG_WRONG;
                        lcd_update  <= 1'b1;
                        state       <= S_IDLE; 
                    end else begin
                        // ĐÃ SAI 5 LẦN -> BẮT ĐẦU ĐẾM 60 GIÂY
                        if (lock_timer < LOCK_DELAY) begin
                            lock_timer <= lock_timer + 1'b1;
                            error_leds <= 5'b11111; // Bật full 5 đèn đỏ cảnh báo
                            
                            // Chỉ vẽ LCD "LOCKED" ở đúng chu kỳ đầu tiên khi bắt đầu đếm
                            if (lock_timer == 32'd0) begin
                                lcd_line1  <= `MSG_LOCKED;
                                lcd_update <= 1'b1;
                            end
                            
                            state <= S_ERROR; // Tiếp tục ở lại trạng thái này
                        end else begin
                            // ĐÃ HẾT 60 GIÂY -> MỞ LẠI HỆ THỐNG
                            lock_timer  <= 32'd0;
                            error_count <= 3'd0;
                            error_leds  <= 5'd0;
                            clear_req   <= 1'b1; // Dọn dẹp lại buffer
                            
                            lcd_line1   <= `MSG_IDLE;
                            lcd_update  <= 1'b1;
                            state       <= S_IDLE; // Cho phép nhập lại
                        end
                    end
                end

                default: state <= S_RESET;
            endcase
        end
    end

    function automatic [127:0] rebuild_line2;
        input [2:0]  count;
        input [23:0] in_buf;        
        input        hide;
        
        reg [7:0] c1, c2, c3, c4, c5, c6;
        begin
            c1 = (count > 3'd0) ? (hide ? 8'h2A : 8'h30 + in_buf[(count*4)-1 -: 4]) : 8'h5F;
            c2 = (count > 3'd1) ? (hide ? 8'h2A : 8'h30 + in_buf[(count*4)-5 -: 4]) : 8'h5F;
            c3 = (count > 3'd2) ? (hide ? 8'h2A : 8'h30 + in_buf[(count*4)-9 -: 4]) : 8'h5F;
            c4 = (count > 3'd3) ? (hide ? 8'h2A : 8'h30 + in_buf[(count*4)-13 -: 4]) : 8'h5F;
            c5 = (count > 3'd4) ? (hide ? 8'h2A : 8'h30 + in_buf[(count*4)-17 -: 4]) : 8'h5F;
            c6 = (count > 3'd5) ? (hide ? 8'h2A : 8'h30 + in_buf[3:0]) : 8'h5F;

            rebuild_line2 = {
                32'h20202020, 8'h5B, 
                c1, c2, c3, c4, c5, c6, 
                8'h5D, 32'h20202020
            };
        end
    endfunction

endmodule