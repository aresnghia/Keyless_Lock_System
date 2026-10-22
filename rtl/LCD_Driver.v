`include "Common_Params.v"
 
// =============================================================================
// Module  : LCD_Driver
// Chức năng: Điều khiển LCD 16x2 (HD44780) trên KIT DE2 Altera
// Clock   : 50 MHz (clk)
// Reset   : Bất đồng bộ, tích cực mức thấp (rst_n)
//
// Ngõ vào : lcd_line1 [127:0]  -- 16 ký tự ASCII dòng 1 (MSB = ký tự trái nhất)
//           lcd_line2 [127:0]  -- 16 ký tự ASCII dòng 2
//           lcd_update         -- Pulse 1 cycle từ Main_FSM: yêu cầu refresh
// Ngõ ra  : LCD_DATA  [7:0]    -- Bus dữ liệu 8-bit
//           LCD_EN             -- Enable strobe
//           LCD_RS             -- 0=Instruction / 1=Data
//           LCD_RW             -- Cố định 0 (Write-only)
//           LCD_ON             -- Cố định 1 (Bật màn hình)
//
// Kiến trúc 2 tầng clock:
//   Tầng 1 (clk 50MHz) : Latch buffer + detect lcd_update
//   Tầng 2 (lcd_clk 1kHz): FSM ghi LCD, đủ timing HD44780
//
// Sơ đồ refresh:
//   INIT(×8) → HOME → WRDATA1(×16) → LINE2 → WRDATA2(×16) → DONE
//   DONE ──(update_pending=1)──► HOME   ← KHÔNG re-INIT, tránh nhấp nháy
// =============================================================================

module LCD_Driver (
    input  wire         clk,
    input  wire         rst_n,
    // Dữ liệu từ Main_FSM
    input  wire [127:0] lcd_line1,
    input  wire [127:0] lcd_line2,
    input  wire         lcd_update,     // Pulse 1 cycle: yêu cầu vẽ lại
    // Phần cứng LCD
    output reg  [7:0]   LCD_DATA,
    output reg          LCD_EN,
    output reg          LCD_RS,
    output wire         LCD_RW,
    output wire         LCD_ON,
	 output wire         LCD_BLON,
	 inout  wire         I2C_SDA, 
	 output wire         I2C_SCL
);

// -----------------------------------------------------------------------------
// HẰNG SỐ
// -----------------------------------------------------------------------------
 
    assign LCD_RW = 1'b0;
    assign LCD_ON = 1'b1;
 
    // Sequence khởi tạo HD44780 (datasheet trang 45)
    wire [7:0] INIT_SEQ [0:7];
    
    assign INIT_SEQ[0] = 8'h38; // Function Set ×4: 8-bit, 2 lines, 5x8 font
    assign INIT_SEQ[1] = 8'h38;
    assign INIT_SEQ[2] = 8'h38;
    assign INIT_SEQ[3] = 8'h38;
    assign INIT_SEQ[4] = 8'h08; // Display OFF
    assign INIT_SEQ[5] = 8'h01; // Clear Display
    assign INIT_SEQ[6] = 8'h06; // Entry Mode: increment, no shift
    assign INIT_SEQ[7] = 8'h0C; // Display ON, cursor OFF, blink OFF
	 
	 // -----------------------------------------------------------------------------
// TẦNG 1 — CLOCK DIVIDER & BUFFER (chạy trên clk 50MHz)
//
// lcd_clk toggle mỗi 25000 cycles → posedge lcd_clk cách nhau 1ms
// Buffer latch dữ liệu tại posedge clk để tránh glitch khi FSM đang ghi
// -----------------------------------------------------------------------------
 
    // Clock divider
    reg [14:0] clk_div;
    reg        lcd_clk;
 
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            clk_div <= 15'd0;
            lcd_clk <= 1'b0;
        end else if (clk_div == 15'd24999) begin
            clk_div <= 15'd0;
            lcd_clk <= ~lcd_clk;
        end else begin
            clk_div <= clk_div + 1'b1;
        end
    end
 
    // Buffer nội: latch khi có lcd_update
    reg [127:0] buf_line1, buf_line2;
 
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            buf_line1 <= {16{8'h20}};   // 16 spaces
            buf_line2 <= {16{8'h20}};
        end else if (lcd_update) begin
            buf_line1 <= lcd_line1;
            buf_line2 <= lcd_line2;
        end
    end
 
// -----------------------------------------------------------------------------
// TẦNG 2 — LCD FSM (chạy trên lcd_clk 1kHz)
//
// State encoding:
//   INIT / INIT_HOLD     : Gửi 8 lệnh init (chỉ chạy 1 lần sau reset)
//   HOME / HOME_HOLD     : Set DDRAM address = 0x00 (đầu dòng 1)
//   WRDATA1 / WR1_HOLD   : Ghi 16 ký tự buf_line1
//   LINE2 / LINE2_HOLD   : Set DDRAM address = 0x40 (đầu dòng 2)
//   WRDATA2 / WR2_HOLD   : Ghi 16 ký tự buf_line2
//   DONE                 : Chờ — refresh về HOME khi update_pending = 1
//
// Mỗi cặp WRITE/HOLD = 2ms. Tổng refresh 1 màn hình ≈ 84ms.
// -----------------------------------------------------------------------------
 
    localparam [3:0]
        S_INIT      = 4'd0,  S_INIT_HOLD  = 4'd1,
        S_HOME      = 4'd2,  S_HOME_HOLD  = 4'd3,
        S_WRDATA1   = 4'd4,  S_WR1_HOLD   = 4'd5,
        S_LINE2     = 4'd6,  S_LINE2_HOLD = 4'd7,
        S_WRDATA2   = 4'd8,  S_WR2_HOLD   = 4'd9,
        S_DONE      = 4'd10;
 
    reg [3:0] state;
    reg [4:0] count;            // Dùng chung: đếm bước init (0..7) hoặc ký tự (0..15)
    reg       update_pending;   // Cờ: có dữ liệu mới chờ vẽ lại
 
    // Hàm lấy byte thứ idx từ chuỗi 128-bit (idx=0 → ký tự trái nhất)
    function automatic [7:0] get_byte;
        input [127:0] str;
        input [3:0]   idx;
        get_byte = str[127 - idx*8 -: 8];
    endfunction
 
    always @(posedge lcd_clk or negedge rst_n) begin
        if (!rst_n) begin
            state          <= S_INIT;
            count          <= 5'd0;
            update_pending <= 1'b0;
            LCD_EN         <= 1'b0;
            LCD_RS         <= 1'b0;
            LCD_DATA       <= 8'h00;
        end else begin
 
            // Detect lcd_update (cross-domain đơn giản: chấp nhận 1 cycle latency)
            if (lcd_update)
                update_pending <= 1'b1;
 
            case (state)
 
                // ----- INIT -----
                S_INIT: begin
                    LCD_RS   <= 1'b0;
                    LCD_EN   <= 1'b1;
                    LCD_DATA <= INIT_SEQ[count[2:0]];
                    state    <= S_INIT_HOLD;
                end
                S_INIT_HOLD: begin
                    LCD_EN <= 1'b0;
                    if (count < 5'd7) begin
                        count <= count + 1'b1;
                        state <= S_INIT;
                    end else begin
                        count <= 5'd0;
                        state <= S_HOME;
                    end
                end
 
                // ----- HOME: Set DDRAM addr = 0x00 -----
                S_HOME: begin
                    LCD_RS   <= 1'b0;
                    LCD_EN   <= 1'b1;
                    LCD_DATA <= 8'h80;
                    state    <= S_HOME_HOLD;
                end
                S_HOME_HOLD: begin
                    LCD_EN <= 1'b0;
                    count  <= 5'd0;
                    state  <= S_WRDATA1;
                end
 
                // ----- WRDATA1: Ghi 16 ký tự dòng 1 -----
                S_WRDATA1: begin
                    LCD_RS   <= 1'b1;
                    LCD_EN   <= 1'b1;
                    LCD_DATA <= get_byte(buf_line1, count[3:0]);
                    state    <= S_WR1_HOLD;
                end
                S_WR1_HOLD: begin
                    LCD_EN <= 1'b0;
                    if (count < 5'd15) begin
                        count <= count + 1'b1;
                        state <= S_WRDATA1;
                    end else begin
                        count <= 5'd0;
                        state <= S_LINE2;
                    end
                end
 
                // ----- LINE2: Set DDRAM addr = 0x40 -----
                S_LINE2: begin
                    LCD_RS   <= 1'b0;
                    LCD_EN   <= 1'b1;
                    LCD_DATA <= 8'hC0;
                    state    <= S_LINE2_HOLD;
                end
                S_LINE2_HOLD: begin
                    LCD_EN <= 1'b0;
                    count  <= 5'd0;
                    state  <= S_WRDATA2;
                end
 
                // ----- WRDATA2: Ghi 16 ký tự dòng 2 -----
                S_WRDATA2: begin
                    LCD_RS   <= 1'b1;
                    LCD_EN   <= 1'b1;
                    LCD_DATA <= get_byte(buf_line2, count[3:0]);
                    state    <= S_WR2_HOLD;
                end
                S_WR2_HOLD: begin
                    LCD_EN <= 1'b0;
                    if (count < 5'd15) begin
                        count <= count + 1'b1;
                        state <= S_WRDATA2;
                    end else begin
                        count          <= 5'd0;
                        update_pending <= 1'b0; // Clear cờ sau khi vẽ xong
                        state          <= S_DONE;
                    end
                end
 
                // ----- DONE: Chờ yêu cầu refresh -----
                // Không re-INIT → không nhấp nháy
                S_DONE: begin
                    LCD_EN <= 1'b0;
                    if (update_pending)
                        state <= S_HOME;        // Refresh: chỉ ghi lại data
                end
 
                default: state <= S_INIT;
 
            endcase
        end
    end
	 
	 
	 
	 
endmodule	 
	 