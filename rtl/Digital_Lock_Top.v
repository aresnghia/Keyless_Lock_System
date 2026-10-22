`include "Common_Params.v"

module Digital_Lock_Top (
    input  wire        CLOCK_50,
    input  wire [3:0]  KEY,     
    input  wire [9:0]  SW,      
    
    // --- ĐÃ SỬA: Xóa các chân LCD song song cũ, thay bằng I2C ---
    inout  wire        I2C_SDA,
    inout  wire        I2C_SCL,
    
    // --- LED ---
    output wire        LEDG0,   
    output wire [4:0]  LEDR     
);

    wire        rst_n = KEY[0];
    wire        change_pass_btn = SW[7]; 

    // Tín hiệu nội bộ
    wire        key_valid;
    wire [3:0]  key_code;
    wire        is_function;

    wire [23:0] buffer_data;
    wire [2:0]  digit_count;
    wire        enter_pressed;
    wire        clear_req;

    wire        match_flag;
    wire        en_compare;
    wire [23:0] stored_password;
    wire        pwd_is_set;
    wire        write_en;

    wire [127:0] lcd_line1;
    wire [127:0] lcd_line2;
    wire         lcd_update;

    // 1. SWITCH INPUT
    Switch_Input u_input (
        .clk         (CLOCK_50),
        .rst_n       (rst_n),
        .KEY         (KEY[3:1]), 
        .SW          (SW),        
        .key_valid   (key_valid),
        .key_code    (key_code),
        .is_function (is_function)
    );

    // 2. INPUT BUFFER
    Input_Buffer u_buffer (
        .clk           (CLOCK_50),
        .rst_n         (rst_n),
        .key_code      (key_code),
        .key_valid     (key_valid),
        .is_function   (is_function),
        .clear_req     (clear_req),     
        .buffer_data   (buffer_data),   
        .digit_count   (digit_count),   
        .enter_pressed (enter_pressed)  
    );

    // 3. MAIN FSM
    Main_FSM u_fsm (
        .clk             (CLOCK_50),
        .rst_n           (rst_n),
        .key_valid       (key_valid),
        .key_code        (key_code),
        .buffer_data     (buffer_data),
        .digit_count     (digit_count),
        .enter_pressed   (enter_pressed),
        .clear_req       (clear_req),
        .match_flag      (match_flag),
        .en_compare      (en_compare),
        .pwd_is_set      (pwd_is_set),
        .write_en        (write_en),
        .lcd_line1       (lcd_line1),
        .lcd_line2       (lcd_line2),
        .lcd_update      (lcd_update),
        .change_pass_btn (change_pass_btn),
        .unlock_led      (LEDG0),
        .error_leds      (LEDR)
    );

    // 4. CODE CHECKER
    Code_Checker u_checker (
        .clk             (CLOCK_50),
        .rst_n           (rst_n),
        .input_buffer    (buffer_data),     
        .stored_password (stored_password),
        .en_compare      (en_compare),
        .match_flag      (match_flag)
    );

    // 5. PASSWORD MEMORY
    Password_Memory u_memory (
        .clk             (CLOCK_50),
        .rst_n           (rst_n),
        .write_en        (write_en),
        .pwd_in          (buffer_data),     
        .pwd_out         (stored_password),
        .pwd_is_set      (pwd_is_set)
    );

    // ==========================================================
    // 6. LCD DRIVER I2C (Áp dụng mạch Open-Drain cực an toàn)
    // ==========================================================
    wire sda_drive_low;
    wire scl_drive_low;

    assign I2C_SDA = sda_drive_low ? 1'b0 : 1'bz;
    assign I2C_SCL = scl_drive_low ? 1'b0 : 1'bz;

    LCD_Driver_I2C u_lcd (
        .clk           (CLOCK_50),
        .rst_n         (rst_n),
        .lcd_line1     (lcd_line1),
        .lcd_line2     (lcd_line2),
        .lcd_update    (lcd_update),
        
        .sda_in        (I2C_SDA),
        .sda_drive_low (sda_drive_low),
        .scl_drive_low (scl_drive_low)
    );

endmodule