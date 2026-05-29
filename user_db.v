`timescale 1ns / 1ps
// ============================================================
// Module : user_db.v
// Description : Central User Database - 4 Users
// Stores : User ID, PIN, Balance for each user
// All reads and writes go through this single module.
// Any balance or PIN change is immediately reflected.
// Verilog-2001 | Synthesizable | Xilinx Vivado
// ============================================================
//
// USER TABLE (initial values):
// +----+---------+--------+---------+
// | ID |  Name   |  PIN   | Balance |
// +----+---------+--------+---------+
// | 00 |  Alice  |  1111  |  50000  |
// | 01 |   Bob   |  2222  |  30000  |
// | 10 | Charlie |  3333  |  15000  |
// | 11 |  Diana  |  4444  |  20000  |
// +----+---------+--------+---------+
//
// Card insert provides user_id (2-bit) which selects the user.
// All subsequent operations (PIN check, balance update, PIN
// change) act on that user's record only.
// ============================================================

module user_db (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        db_init,      // Pulse HIGH once at power-on to load factory defaults
                                     // Keep LOW during all subsequent resets - DB persists

    // User selection - driven by card_insert signal
    input  wire [1:0]  user_id,      // 00=Alice 01=Bob 10=Charlie 11=Diana

    // PIN verification port
    input  wire [15:0] pin_attempt,  // PIN entered by user
    input  wire        pin_check_en, // FSM triggers check
    output reg         pin_match,    // 1-cycle: correct
    output reg         pin_fail,     // 1-cycle: wrong

    // PIN change port
    input  wire [15:0] new_pin,      // New PIN to store
    input  wire        pin_write_en, // FSM triggers PIN update
    output reg         pin_written,  // 1-cycle: PIN updated

    // Balance read port (combinational - always live)
    output wire [15:0] balance_out,  // Current balance of selected user

    // Balance write port
    input  wire [15:0] new_balance,  // New balance to store
    input  wire        bal_write_en, // FSM/account_ctrl triggers write
    output reg         bal_written   // 1-cycle: balance updated
);

    // ----------------------------------------------------------
    // User database - 4 rows, 3 columns (PIN, BALANCE, NAME-ID)
    // ----------------------------------------------------------

    // PINs stored as 16-bit BCD (4 digits x 4 bits)
    reg [15:0] db_pin     [0:3];
    reg [15:0] db_balance [0:3];

    // Default / initial values
    // Alice   PIN=1111  Balance=50000
    // Bob     PIN=2222  Balance=30000
    // Charlie PIN=3333  Balance=75000
    // Diana   PIN=4444  Balance=20000
    parameter [15:0] INIT_PIN_0     = 16'h1111;
    parameter [15:0] INIT_PIN_1     = 16'h2222;
    parameter [15:0] INIT_PIN_2     = 16'h3333;
    parameter [15:0] INIT_PIN_3     = 16'h4444;

    parameter [15:0] INIT_BAL_0     = 16'd50000; // Alice
    parameter [15:0] INIT_BAL_1     = 16'd30000; // Bob
    parameter [15:0] INIT_BAL_2     = 16'd15000; // Charlie (capped at 16-bit max 65535)
    parameter [15:0] INIT_BAL_3     = 16'd20000; // Diana

    // ----------------------------------------------------------
    // Combinational balance output - always reflects live value
    // of currently selected user
    // ----------------------------------------------------------
    assign balance_out = db_balance[user_id];

    // ----------------------------------------------------------
    // Initialise database on reset, handle all read/write ops
    // ----------------------------------------------------------
    always @(posedge clk) begin
        if (!rst_n) begin
            // System reset: clear output pulses ONLY.
            // db_pin and db_balance are NOT touched - all balance/PIN
            // changes from previous transactions are preserved across resets.
            pin_match  <= 1'b0;
            pin_fail   <= 1'b0;
            pin_written<= 1'b0;
            bal_written<= 1'b0;
        end
        else begin
            // db_init: load factory defaults - asserted ONCE at simulation
            // start (or a true power-cycle). Never assert mid-simulation.
            if (db_init) begin
                db_pin[0]     <= INIT_PIN_0;
                db_pin[1]     <= INIT_PIN_1;
                db_pin[2]     <= INIT_PIN_2;
                db_pin[3]     <= INIT_PIN_3;
                db_balance[0] <= INIT_BAL_0;
                db_balance[1] <= INIT_BAL_1;
                db_balance[2] <= INIT_BAL_2;
                db_balance[3] <= INIT_BAL_3;
            end
            // Default: clear single-cycle pulses
            pin_match  <= 1'b0;
            pin_fail   <= 1'b0;
            pin_written<= 1'b0;
            bal_written<= 1'b0;

            // --------------------------------------------------
            // PIN verification - check selected user's PIN
            // --------------------------------------------------
            if (pin_check_en) begin
                if (pin_attempt == db_pin[user_id]) begin
                    pin_match <= 1'b1;
                end
                else begin
                    pin_fail  <= 1'b1;
                end
            end

            // --------------------------------------------------
            // PIN change - update selected user's PIN
            // --------------------------------------------------
            if (pin_write_en) begin
                db_pin[user_id] <= new_pin;
                pin_written     <= 1'b1;
            end

            // --------------------------------------------------
            // Balance update - write new balance for selected user
            // Any transaction (withdraw/deposit) writes here
            // --------------------------------------------------
            if (bal_write_en) begin
                db_balance[user_id] <= new_balance;
                bal_written         <= 1'b1;
            end
        end
    end

endmodule