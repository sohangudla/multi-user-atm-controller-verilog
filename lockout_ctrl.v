`timescale 1ns / 1ps
// ============================================================
// Module : lockout_ctrl.v
// Description : Per-user 3-Attempt Hard Lock
// Verilog-2001 | Synthesizable | Xilinx Vivado
// ============================================================

module lockout_ctrl (
    input  wire       clk,
    input  wire       rst_n,
    input  wire       attempt_inc,
    input  wire       attempt_rst,
    output reg        locked,
    output reg [1:0]  attempt_count
);

    parameter MAX_ATTEMPTS = 2'd3;

    always @(posedge clk) begin
        if (!rst_n) begin
            attempt_count <= 2'd0;
            locked        <= 1'b0;
        end
        else if (locked) begin
            locked <= 1'b1;
        end
        else if (attempt_inc) begin
            if (attempt_count >= MAX_ATTEMPTS - 1) begin
                attempt_count <= attempt_count + 2'd1;
                locked        <= 1'b1;
            end
            else begin
                attempt_count <= attempt_count + 2'd1;
            end
        end
        else if (attempt_rst) begin
            attempt_count <= 2'd0;
            locked        <= 1'b0;
        end
    end

endmodule
