module I2C_Master (
    input  wire       clk,       // 50MHz từ DE2
    input  wire       rst_n,
    input  wire       start_tx,
    input  wire [7:0] data_in,
    output reg        tx_done,
    inout  wire       SDA,
    output reg        SCL
);

    // Bộ chia tần số 50MHz -> 100kHz I2C
    reg [9:0] clk_cnt;
    reg       i2c_tick;
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            clk_cnt  <= 10'd0;
            i2c_tick <= 1'b0;
        end else if (clk_cnt == 10'd499) begin
            clk_cnt  <= 10'd0;
            i2c_tick <= 1'b1;
        end else begin
            clk_cnt  <= clk_cnt + 1'b1;
            i2c_tick <= 1'b0;
        end
    end

    reg [5:0] state;
    reg [7:0] addr_reg;
    reg [7:0] data_reg;
    reg       sda_out;
    
    // Mạch Open-Drain cho chân SDA
    assign SDA = (sda_out) ? 1'bz : 1'b0;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state    <= 6'd0;
            sda_out  <= 1'b1;
            SCL      <= 1'b1;
            tx_done  <= 1'b0;
            // NẾU MODULE I2C MUA LÀ CHIP PCF8574AT, SỬA 8'h4E THÀNH 8'h7E
            addr_reg <= 8'h4E; 
            data_reg <= 8'h00;
        end else begin
            tx_done <= 1'b0;
            if (state == 6'd0) begin
                sda_out <= 1'b1;
                SCL     <= 1'b1;
                if (start_tx) begin
                    data_reg <= data_in;
                    state    <= 6'd1;
                end
            end else if (i2c_tick) begin
                case (state)
                    // START Condition
                    6'd1:  begin sda_out <= 1'b0; SCL <= 1'b1; state <= 6'd2; end
                    6'd2:  begin sda_out <= 1'b0; SCL <= 1'b0; state <= 6'd3; end
                    
                    // Gửi 8-bit Address
                    6'd3:  begin sda_out <= addr_reg[7]; SCL <= 1'b0; state <= 6'd4; end
                    6'd4:  begin SCL <= 1'b1; state <= 6'd5; end 6'd5: begin SCL <= 1'b0; state <= 6'd6; end
                    6'd6:  begin sda_out <= addr_reg[6]; SCL <= 1'b0; state <= 6'd7; end
                    6'd7:  begin SCL <= 1'b1; state <= 6'd8; end 6'd8: begin SCL <= 1'b0; state <= 6'd9; end
                    6'd9:  begin sda_out <= addr_reg[5]; SCL <= 1'b0; state <= 6'd10; end
                    6'd10: begin SCL <= 1'b1; state <= 6'd11; end 6'd11: begin SCL <= 1'b0; state <= 6'd12; end
                    6'd12: begin sda_out <= addr_reg[4]; SCL <= 1'b0; state <= 6'd13; end
                    6'd13: begin SCL <= 1'b1; state <= 6'd14; end 6'd14: begin SCL <= 1'b0; state <= 6'd15; end
                    6'd15: begin sda_out <= addr_reg[3]; SCL <= 1'b0; state <= 6'd16; end
                    6'd16: begin SCL <= 1'b1; state <= 6'd17; end 6'd17: begin SCL <= 1'b0; state <= 6'd18; end
                    6'd18: begin sda_out <= addr_reg[2]; SCL <= 1'b0; state <= 6'd19; end
                    6'd19: begin SCL <= 1'b1; state <= 6'd20; end 6'd20: begin SCL <= 1'b0; state <= 6'd21; end
                    6'd21: begin sda_out <= addr_reg[1]; SCL <= 1'b0; state <= 6'd22; end
                    6'd22: begin SCL <= 1'b1; state <= 6'd23; end 6'd23: begin SCL <= 1'b0; state <= 6'd24; end
                    6'd24: begin sda_out <= addr_reg[0]; SCL <= 1'b0; state <= 6'd25; end
                    6'd25: begin SCL <= 1'b1; state <= 6'd26; end 6'd26: begin SCL <= 1'b0; state <= 6'd27; end
                    
                    // Chờ ACK Address
                    6'd27: begin sda_out <= 1'b1; SCL <= 1'b0; state <= 6'd28; end
                    6'd28: begin SCL <= 1'b1; state <= 6'd29; end 6'd29: begin SCL <= 1'b0; state <= 6'd30; end
                    
                    // Gửi 8-bit Data
                    6'd30: begin sda_out <= data_reg[7]; SCL <= 1'b0; state <= 6'd31; end
                    6'd31: begin SCL <= 1'b1; state <= 6'd32; end 6'd32: begin SCL <= 1'b0; state <= 6'd33; end
                    6'd33: begin sda_out <= data_reg[6]; SCL <= 1'b0; state <= 6'd34; end
                    6'd34: begin SCL <= 1'b1; state <= 6'd35; end 6'd35: begin SCL <= 1'b0; state <= 6'd36; end
                    6'd36: begin sda_out <= data_reg[5]; SCL <= 1'b0; state <= 6'd37; end
                    6'd37: begin SCL <= 1'b1; state <= 6'd38; end 6'd38: begin SCL <= 1'b0; state <= 6'd39; end
                    6'd39: begin sda_out <= data_reg[4]; SCL <= 1'b0; state <= 6'd40; end
                    6'd40: begin SCL <= 1'b1; state <= 6'd41; end 6'd41: begin SCL <= 1'b0; state <= 6'd42; end
                    6'd42: begin sda_out <= data_reg[3]; SCL <= 1'b0; state <= 6'd43; end
                    6'd43: begin SCL <= 1'b1; state <= 6'd44; end 6'd44: begin SCL <= 1'b0; state <= 6'd45; end
                    6'd45: begin sda_out <= data_reg[2]; SCL <= 1'b0; state <= 6'd46; end
                    6'd46: begin SCL <= 1'b1; state <= 6'd47; end 6'd47: begin SCL <= 1'b0; state <= 6'd48; end
                    6'd48: begin sda_out <= data_reg[1]; SCL <= 1'b0; state <= 6'd49; end
                    6'd49: begin SCL <= 1'b1; state <= 6'd50; end 6'd50: begin SCL <= 1'b0; state <= 6'd51; end
                    6'd51: begin sda_out <= data_reg[0]; SCL <= 1'b0; state <= 6'd52; end
                    6'd52: begin SCL <= 1'b1; state <= 6'd53; end 6'd53: begin SCL <= 1'b0; state <= 6'd54; end
                    
                    // Chờ ACK Data
                    6'd54: begin sda_out <= 1'b1; SCL <= 1'b0; state <= 6'd55; end
                    6'd55: begin SCL <= 1'b1; state <= 6'd56; end 6'd56: begin SCL <= 1'b0; state <= 6'd57; end
                    
                    // STOP Condition
                    6'd57: begin sda_out <= 1'b0; SCL <= 1'b0; state <= 6'd58; end
                    6'd58: begin SCL <= 1'b1; state <= 6'd59; end
                    6'd59: begin sda_out <= 1'b1; tx_done <= 1'b1; state <= 6'd0; end
                    default: state <= 6'd0;
                endcase
            end
        end
    end
endmodule