`include "Common_Params.v"

module LCD_Driver_I2C #(
    parameter I2C_ADDR = 7'h27 // NẾU KHÔNG LÊN CHỮ, SỬA THÀNH 7'h3F Ở ĐÂY!
)(
    input  wire         clk,
    input  wire         rst_n,
    
    // Dữ liệu từ Main FSM
    input  wire [127:0] lcd_line1,
    input  wire [127:0] lcd_line2,
    input  wire         lcd_update,

    // Giao tiếp Open-Drain ra Top
    input  wire         sda_in,
    output wire         sda_drive_low,
    output wire         scl_drive_low
);

    // ==========================================
    // 1. LATCH DỮ LIỆU TỪ MAIN_FSM 
    // ==========================================
    reg [127:0] latched_line1;
    reg [127:0] latched_line2;
    reg         update_pending;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            latched_line1 <= {16{8'h20}};
            latched_line2 <= {16{8'h20}};
            update_pending <= 1'b0;
        end else begin
            if (lcd_update) begin
                latched_line1 <= lcd_line1;
                latched_line2 <= lcd_line2;
                update_pending <= 1'b1;
            end
            // Xóa cờ update_pending khi FSM bắt đầu vẽ (xem ở ST_DONE)
            else if (state == ST_DONE && update_pending) begin
                update_pending <= 1'b0;
            end
        end
    end

    // ==========================================
    // 2. ROM ĐỘNG (THAY THẾ CHỮ CỨNG BẰNG BUFFER)
    // ==========================================
    function [7:0] get_char;
        input [127:0] str;
        input [5:0]   i;
        get_char = str[127 - i*8 -: 8];
    endfunction

    reg [8:0] rom_data;
    always @(*) begin
        if      (idx == 6'd0) rom_data = {1'b0, 8'h28}; // 4-bit, 2 dòng
        else if (idx == 6'd1) rom_data = {1'b0, 8'h0C}; // Display ON
        else if (idx == 6'd2) rom_data = {1'b0, 8'h06}; // Entry mode
        else if (idx == 6'd3) rom_data = {1'b0, 8'h01}; // Clear display
        
        else if (idx == 6'd4) rom_data = {1'b0, 8'h80}; // Đầu dòng 1
        else if (idx >= 6'd5 && idx <= 6'd20) 
                              rom_data = {1'b1, get_char(latched_line1, idx - 6'd5)};
        
        else if (idx == 6'd21) rom_data = {1'b0, 8'hC0}; // Đầu dòng 2
        else if (idx >= 6'd22 && idx <= 6'd37) 
                               rom_data = {1'b1, get_char(latched_line2, idx - 6'd22)};
        else                   rom_data = {1'b1, 8'h20};
    end

    // ==========================================
    // 3. FSM I2C LCD (Giữ nguyên 100% Timing của bạn)
    // ==========================================
    localparam integer WAIT_POWER = 1000000;  // 20ms @ 50MHz
    localparam integer WAIT_5MS   = 250000;
    localparam integer WAIT_2MS   = 100000;
    localparam integer WAIT_50US  = 2500;
    localparam integer WAIT_200US = 10000;

    localparam [3:0]
        ST_POWER       = 4'd0,
        ST_INIT_LOAD   = 4'd1,
        ST_BYTE_LOAD   = 4'd2,
        ST_SEND_E1     = 4'd3,
        ST_WAIT_E1     = 4'd4,
        ST_SEND_E0     = 4'd5,
        ST_WAIT_E0     = 4'd6,
        ST_AFTER_NIB   = 4'd7,
        ST_DONE        = 4'd8;

    localparam [1:0]
        RET_INIT      = 2'd0,
        RET_BYTE_LOW  = 2'd1,
        RET_BYTE_DONE = 2'd2;

    localparam [5:0] TOTAL_BYTES = 6'd38;

    reg [3:0] state;
    reg [1:0] ret_state;
    reg [31:0] cnt;
    reg [31:0] post_delay;
    reg [2:0] init_step;
    reg [5:0] idx;
    reg [7:0] cur_byte;
    reg cur_rs;
    reg [3:0] cur_nibble;
    reg tx_start;
    reg [7:0] tx_data;
    wire tx_busy;
    wire tx_done;

    i2c_write_byte #(.DIVIDER(250)) u_i2c (
        .clk           (clk),
        .rst_n         (rst_n),
        .start         (tx_start),
        .addr          (I2C_ADDR),
        .data          (tx_data),
        .sda_in        (sda_in),
        .busy          (tx_busy),
        .done          (tx_done),
        .sda_drive_low (sda_drive_low),
        .scl_drive_low (scl_drive_low)
    );

    function [7:0] pcf_byte;
        input [3:0] nibble;
        input rs;
        input en;
        begin
            pcf_byte = {nibble, 1'b1, en, 1'b0, rs};
        end
    endfunction

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= ST_POWER;
            ret_state <= RET_INIT;
            cnt <= 32'd0;
            post_delay <= 32'd0;
            init_step <= 3'd0;
            idx <= 6'd0;
            cur_byte <= 8'd0;
            cur_rs <= 1'b0;
            cur_nibble <= 4'd0;
            tx_start <= 1'b0;
            tx_data <= 8'd0;
        end else begin
            tx_start <= 1'b0;

            case (state)
                ST_POWER: begin
                    if (cnt < WAIT_POWER) cnt <= cnt + 32'd1;
                    else begin
                        cnt <= 32'd0;
                        init_step <= 3'd0;
                        state <= ST_INIT_LOAD;
                    end
                end

                ST_INIT_LOAD: begin
                    cur_rs <= 1'b0;
                    ret_state <= RET_INIT;
                    case (init_step)
                        3'd0: begin cur_nibble <= 4'h3; post_delay <= WAIT_5MS; state <= ST_SEND_E1; end
                        3'd1: begin cur_nibble <= 4'h3; post_delay <= WAIT_200US; state <= ST_SEND_E1; end
                        3'd2: begin cur_nibble <= 4'h3; post_delay <= WAIT_200US; state <= ST_SEND_E1; end
                        3'd3: begin cur_nibble <= 4'h2; post_delay <= WAIT_200US; state <= ST_SEND_E1; end
                        default: begin idx <= 6'd0; state <= ST_BYTE_LOAD; end
                    endcase
                end

                ST_BYTE_LOAD: begin
                    if (idx < TOTAL_BYTES) begin
                        cur_rs <= rom_data[8];
                        cur_byte <= rom_data[7:0];
                        cur_nibble <= rom_data[7:4];
                        post_delay <= WAIT_50US;
                        ret_state <= RET_BYTE_LOW;
                        state <= ST_SEND_E1;
                    end else begin
                        state <= ST_DONE;
                    end
                end

                ST_SEND_E1: begin
                    if (!tx_busy) begin
                        tx_data <= pcf_byte(cur_nibble, cur_rs, 1'b1);
                        tx_start <= 1'b1;
                        state <= ST_WAIT_E1;
                    end
                end

                ST_WAIT_E1: begin
                    if (tx_done) state <= ST_SEND_E0;
                end

                ST_SEND_E0: begin
                    if (!tx_busy) begin
                        tx_data <= pcf_byte(cur_nibble, cur_rs, 1'b0);
                        tx_start <= 1'b1;
                        state <= ST_WAIT_E0;
                    end
                end

                ST_WAIT_E0: begin
                    if (tx_done) begin
                        cnt <= 32'd0;
                        state <= ST_AFTER_NIB;
                    end
                end

                ST_AFTER_NIB: begin
                    if (cnt < post_delay) cnt <= cnt + 32'd1;
                    else begin
                        cnt <= 32'd0;
                        case (ret_state)
                            RET_INIT: begin init_step <= init_step + 3'd1; state <= ST_INIT_LOAD; end
                            RET_BYTE_LOW: begin
                                cur_nibble <= cur_byte[3:0];
                                if (cur_byte == 8'h01 || cur_byte == 8'h02) post_delay <= WAIT_2MS;
                                else post_delay <= WAIT_50US;
                                ret_state <= RET_BYTE_DONE;
                                state <= ST_SEND_E1;
                            end
                            RET_BYTE_DONE: begin idx <= idx + 6'd1; state <= ST_BYTE_LOAD; end
                            default: state <= ST_DONE;
                        endcase
                    end
                end

                ST_DONE: begin
                    if (update_pending) begin
                        // Khi có chữ mới, bỏ qua lệnh init, bỏ qua lệnh Clear Screen
                        // Nhảy thẳng tới idx 4 (bắt đầu ghi từ 0x80 - Dòng 1)
                        idx <= 6'd4; 
                        state <= ST_BYTE_LOAD;
                    end else begin
                        state <= ST_DONE;
                    end
                end

                default: state <= ST_POWER;
            endcase
        end
    end
endmodule

// =========================================================
// MODULE TRUYỀN I2C (Giữ nguyên của bạn)
// =========================================================
module i2c_write_byte #(
    parameter integer DIVIDER = 250
)(
    input clk, input rst_n, input start, input [6:0] addr, input [7:0] data,
    input sda_in, output reg busy, output reg done,
    output reg sda_drive_low, output reg scl_drive_low
);
    localparam [3:0]
        S_IDLE = 4'd0, S_START1 = 4'd1, S_START2 = 4'd2, S_START3 = 4'd3,
        S_BIT_SETUP = 4'd4, S_BIT_HIGH = 4'd5, S_BIT_LOW = 4'd6,
        S_ACK_SETUP = 4'd7, S_ACK_HIGH = 4'd8, S_ACK_LOW = 4'd9,
        S_STOP1 = 4'd10, S_STOP2 = 4'd11, S_STOP3 = 4'd12, S_DONE = 4'd13;

    reg [3:0] state;
    reg [31:0] div_cnt;
    reg [15:0] shreg;
    reg [4:0] bit_pos;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= S_IDLE; div_cnt <= 32'd0; shreg <= 16'd0; bit_pos <= 5'd0;
            busy <= 1'b0; done <= 1'b0; sda_drive_low <= 1'b0; scl_drive_low <= 1'b0;
        end else begin
            done <= 1'b0;
            if (state == S_IDLE) begin
                div_cnt <= 32'd0; sda_drive_low <= 1'b0; scl_drive_low <= 1'b0; busy <= 1'b0;
                if (start) begin
                    shreg <= {addr, 1'b0, data}; bit_pos <= 5'd15;
                    busy <= 1'b1; state <= S_START1;
                end
            end else begin
                if (div_cnt < DIVIDER - 1) div_cnt <= div_cnt + 32'd1;
                else begin
                    div_cnt <= 32'd0;
                    case (state)
                        S_START1: begin sda_drive_low <= 1'b0; scl_drive_low <= 1'b0; state <= S_START2; end
                        S_START2: begin sda_drive_low <= 1'b1; scl_drive_low <= 1'b0; state <= S_START3; end
                        S_START3: begin sda_drive_low <= 1'b1; scl_drive_low <= 1'b1; state <= S_BIT_SETUP; end
                        S_BIT_SETUP: begin
                            scl_drive_low <= 1'b1;
                            sda_drive_low <= (shreg[bit_pos] == 1'b0) ? 1'b1 : 1'b0;
                            state <= S_BIT_HIGH;
                        end
                        S_BIT_HIGH: begin scl_drive_low <= 1'b0; state <= S_BIT_LOW; end
                        S_BIT_LOW: begin
                            scl_drive_low <= 1'b1;
                            if (bit_pos == 5'd8 || bit_pos == 5'd0) state <= S_ACK_SETUP;
                            else begin bit_pos <= bit_pos - 5'd1; state <= S_BIT_SETUP; end
                        end
                        S_ACK_SETUP: begin sda_drive_low <= 1'b0; scl_drive_low <= 1'b1; state <= S_ACK_HIGH; end
                        S_ACK_HIGH: begin scl_drive_low <= 1'b0; state <= S_ACK_LOW; end
                        S_ACK_LOW: begin
                            scl_drive_low <= 1'b1;
                            if (bit_pos == 5'd8) begin bit_pos <= 5'd7; state <= S_BIT_SETUP; end
                            else state <= S_STOP1;
                        end
                        S_STOP1: begin sda_drive_low <= 1'b1; scl_drive_low <= 1'b1; state <= S_STOP2; end
                        S_STOP2: begin sda_drive_low <= 1'b1; scl_drive_low <= 1'b0; state <= S_STOP3; end
                        S_STOP3: begin sda_drive_low <= 1'b0; scl_drive_low <= 1'b0; state <= S_DONE; end
                        S_DONE: begin busy <= 1'b0; done <= 1'b1; state <= S_IDLE; end
                        default: state <= S_IDLE;
                    endcase
                end
            end
        end
    end
endmodule