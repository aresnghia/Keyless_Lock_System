module Password_Memory (
    input wire clk,
    input wire rst_n,
    input wire write_en,        
    input  wire [23:0] pwd_in,
    output reg  [23:0] pwd_out,
    output reg         pwd_is_set
);

    reg [23:0] password_storage;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            password_storage <= 24'h000000;
            pwd_is_set       <= 1'b0;
        end else if (write_en) begin
            password_storage <= pwd_in;
            pwd_is_set       <= 1'b1; 
        end
    end

    always @(*) begin
        pwd_out = password_storage;
    end

endmodule