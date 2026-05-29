`timescale 1ns / 1ps
// ============================================================
// Module : display_ctrl.v
// Description : Display Controller — Multi-User Real ATM
// Verilog-2001 | Synthesizable | Xilinx Vivado
// ============================================================

module display_ctrl (
    input  wire        clk,
    input  wire        rst_n,
    input  wire [3:0]  state_in,
    input  wire [1:0]  active_user,   // Show which user is logged in
    input  wire        authenticated,
    input  wire [15:0] balance_in,    // From user_db (live)
    input  wire        locked_in,
    output reg  [7:0]  display_out,
    output reg  [15:0] balance_disp,
    output reg  [1:0]  user_disp      // Displayed user ID
);

    // Display codes
    parameter DISP_IDLE         = 8'h00;
    parameter DISP_PIN_ENTRY    = 8'h01;
    parameter DISP_PIN_CHECK    = 8'h02;
    parameter DISP_PIN_FAIL     = 8'h03;
    parameter DISP_LOCKED       = 8'hFF;
    parameter DISP_MENU         = 8'h05;
    parameter DISP_WITHDRAW     = 8'h06;
    parameter DISP_DEPOSIT      = 8'h07;
    parameter DISP_BALANCE      = 8'h08;
    parameter DISP_NEW_PIN      = 8'h09;
    parameter DISP_CONFIRM_PIN  = 8'h0A;
    parameter DISP_PIN_CHANGE   = 8'h0B;
    parameter DISP_SUCCESS      = 8'h0C;
    parameter DISP_FAIL         = 8'h0D;
    parameter DISP_SESSION_END  = 8'h0E;

    parameter [3:0]
        S_IDLE        = 4'd0,
        S_PIN_ENTRY   = 4'd1,
        S_PIN_CHECK   = 4'd2,
        S_PIN_FAIL    = 4'd3,
        S_LOCKED      = 4'd4,
        S_MENU        = 4'd5,
        S_WITHDRAW    = 4'd6,
        S_DEPOSIT     = 4'd7,
        S_BALANCE_ENQ = 4'd8,
        S_NEW_PIN     = 4'd9,
        S_CONFIRM_PIN = 4'd10,
        S_PIN_CHANGE  = 4'd11,
        S_TXN_SUCCESS = 4'd12,
        S_TXN_FAIL    = 4'd13,
        S_SESSION_END = 4'd14;

    always @(posedge clk) begin
        if (!rst_n) begin
            display_out  <= DISP_IDLE;
            balance_disp <= 16'd0;
            user_disp    <= 2'd0;
        end
        else begin
            user_disp    <= active_user;
            balance_disp <= authenticated ? balance_in : 16'd0;

            case (state_in)
                S_IDLE:        display_out <= DISP_IDLE;
                S_PIN_ENTRY:   display_out <= DISP_PIN_ENTRY;
                S_PIN_CHECK:   display_out <= DISP_PIN_CHECK;
                S_PIN_FAIL:    display_out <= DISP_PIN_FAIL;
                S_LOCKED:      display_out <= DISP_LOCKED;
                S_MENU:        display_out <= DISP_MENU;
                S_WITHDRAW:    display_out <= DISP_WITHDRAW;
                S_DEPOSIT:     display_out <= DISP_DEPOSIT;
                S_BALANCE_ENQ: display_out <= DISP_BALANCE;
                S_NEW_PIN:     display_out <= DISP_NEW_PIN;
                S_CONFIRM_PIN: display_out <= DISP_CONFIRM_PIN;
                S_PIN_CHANGE:  display_out <= DISP_PIN_CHANGE;
                S_TXN_SUCCESS: display_out <= DISP_SUCCESS;
                S_TXN_FAIL:    display_out <= DISP_FAIL;
                S_SESSION_END: display_out <= DISP_SESSION_END;
                default:       display_out <= DISP_IDLE;
            endcase
        end
    end

endmodule
