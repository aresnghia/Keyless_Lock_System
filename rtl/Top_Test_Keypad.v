`timescale 1ns/1ps
`include "Common_Params.v"

module Top_Test_Keypad(
    input  wire        CLOCK_50,    // Pin N2
    input  wire [0:0]  KEY,         // Pin G26 (Reset)
    
    // --- KHAI BÁO MẢNG GPIO_0 CHUẨN ---
    inout  wire [35:0] GPIO_0,

    // --- CÁC CHÂN HIỂN THỊ DEBUG ---
    output reg  [6:0]  HEX0,        
    output wire [3:0]  LEDR,        
    output wire        LEDR_17      
);

    wire rst_n = KEY[0];

    // --- MAPPING MẢNG GPIO VÀO ROWS/COLS ---
    wire [3:0] rows;
    
    // Rows là ngõ ra (Output từ FPGA tới Keypad)
    assign GPIO_0[13] = rows[0]; // Pin 1 của Keypad (Row 1)
    assign GPIO_0[15] = rows[1]; // Pin 2 của Keypad (Row 2)
    assign GPIO_0[17] = rows[2]; // Pin 3 của Keypad (Row 3)
    assign GPIO_0[19] = rows[3]; // Pin 4 của Keypad (Row 4)

    // Cols là ngõ vào (Input từ Keypad tới FPGA)
    // Lấy tín hiệu từ các index lẻ tương ứng
    wire [3:0] cols = {GPIO_0[27], GPIO_0[25], GPIO_0[23], GPIO_0[21]};

    // Tín hiệu nội bộ
    wire [3:0] key_code;
    wire       key_valid;
    wire       is_function;

    // 1. GỌI MODULE KEYPAD SCANNER
    Keypad_Scanner u_keypad (
        .clk(CLOCK_50),
        .rst_n(rst_n),
        .cols(cols),
        .rows(rows),
        .key_code(key_code),
        .key_valid(key_valid),
        .is_function(is_function)
    );

    // 2. LOGIC ĐẾM VÀ CHỐT DỮ LIỆU (Để test)
    reg [3:0] last_key;
    reg [3:0] press_count;
    reg       last_is_function;

    always @(posedge CLOCK_50 or negedge rst_n) begin
        if (!rst_n) begin
            last_key         <= 4'hF;
            press_count      <= 4'd0;
            last_is_function <= 1'b0;
        end else if (key_valid) begin
            last_key         <= key_code;
            press_count      <= press_count + 1'b1;
            last_is_function <= is_function;
        end
    end

    assign LEDR[3:0] = press_count;
    assign LEDR_17   = last_is_function;

    // 3. GIẢI MÃ HEX0 (Hiện phím bấm)
    always @(*) begin
        case(last_key)
            4'h0: HEX0 = 7'b1000000; 4'h1: HEX0 = 7'b1111001;
            4'h2: HEX0 = 7'b0100100; 4'h3: HEX0 = 7'b0110000;
            4'h4: HEX0 = 7'b0011001; 4'h5: HEX0 = 7'b0010010;
            4'h6: HEX0 = 7'b0000010; 4'h7: HEX0 = 7'b1111000;
            4'h8: HEX0 = 7'b0000000; 4'h9: HEX0 = 7'b0010000;
            4'hA: HEX0 = 7'b0001000; 4'hB: HEX0 = 7'b0000011;
            4'hC: HEX0 = 7'b1000110; 4'hD: HEX0 = 7'b0100001;
            default: HEX0 = 7'b0111111;
        endcase
    end
endmodule