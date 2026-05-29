`timescale 1ns / 1ps
// ============================================================
// Module : account_ctrl.v  (FIXED)
// Description : Transaction Controller for Real ATM
//
// FIXES:
//  1. txn_confirm input now connected to FSM's txn_confirm_r
//     (registered version), so it arrives one cycle AFTER
//     txn_en goes high. Previously txn_confirm went low before
//     txn_en even rose - account_ctrl never triggered.
//
//  2. Removed local txn_processed flag dependency on txn_en
//     de-assertion timing; flag still clears correctly on
//     txn_en low but no longer causes double-fire.
//
// Verilog-2001 | Synthesizable | Xilinx Vivado
// ============================================================

module account_ctrl (
    input  wire        clk,
    input  wire        rst_n,

    input  wire        txn_en,
    input  wire [1:0]  txn_type,
    // FIX: this is now connected to fsm.txn_confirm_r (registered)
    input  wire        txn_confirm,

    input  wire [15:0] txn_amount,
    input  wire [15:0] balance_in,

    output reg  [15:0] new_balance,
    output reg         bal_write_en,

    output reg         txn_done,
    output reg         txn_success,
    output reg         balance_ready
);

    parameter TXN_WITHDRAW = 2'b01;
    parameter TXN_DEPOSIT  = 2'b10;
    parameter TXN_BALANCE  = 2'b11;

    reg txn_processed;

    always @(posedge clk) begin
        if (!rst_n) begin
            new_balance   <= 16'd0;
            bal_write_en  <= 1'b0;
            txn_done      <= 1'b0;
            txn_success   <= 1'b0;
            txn_processed <= 1'b0;
            balance_ready <= 1'b0;
        end
        else begin
            // Clear single-cycle pulses
            txn_done      <= 1'b0;
            bal_write_en  <= 1'b0;
            balance_ready <= 1'b0;

            // Reset processed flag when FSM de-asserts txn_en
            if (!txn_en)
                txn_processed <= 1'b0;

            if (txn_en && txn_confirm && !txn_processed) begin
                txn_processed <= 1'b1;

                case (txn_type)

                    TXN_WITHDRAW: begin
                        if (txn_amount == 16'd0) begin
                            txn_done    <= 1'b1;
                            txn_success <= 1'b0;
                        end
                        else if (txn_amount <= balance_in) begin
                            new_balance  <= balance_in - txn_amount;
                            bal_write_en <= 1'b1;
                            txn_done     <= 1'b1;
                            txn_success  <= 1'b1;
                        end
                        else begin
                            txn_done    <= 1'b1;
                            txn_success <= 1'b0;
                        end
                    end

                    TXN_DEPOSIT: begin
                        if (txn_amount == 16'd0) begin
                            txn_done    <= 1'b1;
                            txn_success <= 1'b0;
                        end
                        else if ((balance_in + txn_amount) <= 16'hFFFF) begin
                            new_balance  <= balance_in + txn_amount;
                            bal_write_en <= 1'b1;
                            txn_done     <= 1'b1;
                            txn_success  <= 1'b1;
                        end
                        else begin
                            txn_done    <= 1'b1;
                            txn_success <= 1'b0;
                        end
                    end

                    TXN_BALANCE: begin
                        balance_ready <= 1'b1;
                        txn_done      <= 1'b1;
                        txn_success   <= 1'b1;
                    end

                    default: begin
                        txn_done    <= 1'b1;
                        txn_success <= 1'b0;
                    end

                endcase
            end
        end
    end

endmodule