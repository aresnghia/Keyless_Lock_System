module Code_Checker(
    input wire clk,
    input wire rst_n,
    input wire [23:0] input_buffer,    
    input wire [23:0] stored_password, 
    input wire en_compare,             
    
    output wire match_flag 
);

    assign match_flag = (en_compare) ? (input_buffer == stored_password) : 1'b0;

endmodule