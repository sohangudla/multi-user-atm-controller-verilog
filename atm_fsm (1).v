`timescale 1ns / 1ps
// ============================================================
// Module : atm_fsm.v  (FIXED)
// Description : Multi-User Real ATM FSM
//
// FIXES:
//  1. active_user latched in S_IDLE when card_inserted (correct).
//     Added one-cycle settle: card_id sampled on the posedge after
//     card_inserted rises, before FSM leaves IDLE.
//
//  2. txn_confirm is registered (txn_confirm_r) so that
//     account_ctrl sees txn_en HIGH together with txn_confirm_r.
//     Original: txn_confirm pulse came BEFORE txn_en rose ?
//     account_ctrl never fired ? old balance used for next user.
//
//  3. S_WITHDRAW / S_DEPOSIT next-state: removed stale
//     "txn_confirm &&" guard from combinational check; only
//     txn_done is needed (account_ctrl fires autonomously).
//
//  4. S_PIN_CHANGE: stays in state until pin_written pulse arrives
//     (was immediately transitioning before user_db could respond).
//
//  5. txn_confirm_r exposed as output so account_ctrl can use it.
// ============================================================

module atm_fsm (
    input  wire        clk,
    input  wire        rst_n,

    input  wire        card_inserted,
    input  wire [1:0]  card_id,

    input  wire [15:0] pin_in,
    input  wire        pin_enter,
    input  wire [15:0] new_pin_in,
    input  wire        new_pin_enter,
    input  wire [15:0] confirm_pin_in,
    input  wire        confirm_enter,
    input  wire [1:0]  txn_select,
    input  wire [15:0] txn_amount,
    input  wire        txn_confirm,
    input  wire        cancel,

    input  wire        pin_match,
    input  wire        pin_fail,
    input  wire        pin_written,
    input  wire        bal_written,

    input  wire        txn_done,
    input  wire        txn_success,
    input  wire        balance_ready,

    output reg         pin_check_en,
    output reg  [15:0] pin_attempt,
    output reg         pin_write_en,
    output reg  [15:0] new_pin_out,
    output reg  [1:0]  active_user,

    output reg         attempt_inc,
    output reg         attempt_rst,

    output reg         txn_en,
    output reg  [1:0]  txn_type,
    // FIX 2: registered txn_confirm forwarded to account_ctrl
    output reg         txn_confirm_r,

    output reg         session_active,
    output reg         authenticated,
    output reg         locked_out,
    output reg  [3:0]  state_out
);

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

    parameter [1:0] MAX_ATTEMPTS = 2'd3;

    reg [3:0]  current_state, next_state;
    reg [1:0]  attempt_reg;
    reg        internal_locked;

    reg [15:0] latched_new_pin, latched_confirm;
    reg        new_pin_latched, confirm_latched;

    // ----------------------------------------------------------
    // Sequential: state, latches, attempt counter
    // ----------------------------------------------------------
    always @(posedge clk) begin
        if (!rst_n) begin
            current_state   <= S_IDLE;
            attempt_reg     <= 2'd0;
            internal_locked <= 1'b0;
            active_user     <= 2'd0;
            latched_new_pin <= 16'h0000;
            latched_confirm <= 16'h0000;
            new_pin_latched <= 1'b0;
            confirm_latched <= 1'b0;
            txn_confirm_r   <= 1'b0;
        end
        else begin
            current_state <= next_state;

            // FIX 1: Latch user ID while in IDLE (card_id is stable)
            if (current_state == S_IDLE && card_inserted && !internal_locked)
                active_user <= card_id;

            // FIX 2: Register txn_confirm - now aligned with txn_en
            txn_confirm_r <= txn_confirm;

            if (new_pin_enter) begin
                latched_new_pin <= new_pin_in;
                new_pin_latched <= 1'b1;
            end
            if (confirm_enter) begin
                latched_confirm <= confirm_pin_in;
                confirm_latched <= 1'b1;
            end
            if (current_state == S_PIN_CHANGE) begin
                new_pin_latched <= 1'b0;
                confirm_latched <= 1'b0;
            end

            // Attempt counter
            if (current_state == S_PIN_FAIL) begin
                if (attempt_reg >= MAX_ATTEMPTS - 1)
                    internal_locked <= 1'b1;
                else
                    attempt_reg <= attempt_reg + 2'd1;
            end
            else if (current_state == S_MENU) begin
                attempt_reg     <= 2'd0;
                internal_locked <= 1'b0;
            end
        end
    end

    // ----------------------------------------------------------
    // Combinational next-state
    // ----------------------------------------------------------
    always @(*) begin
        next_state = current_state;

        case (current_state)
            S_IDLE: begin
                if (card_inserted && !internal_locked)
                    next_state = S_PIN_ENTRY;
                else if (internal_locked)
                    next_state = S_LOCKED;
            end

            S_PIN_ENTRY: begin
                if (cancel)         next_state = S_SESSION_END;
                else if (pin_enter) next_state = S_PIN_CHECK;
            end

            S_PIN_CHECK: begin
                if (pin_match)     next_state = S_MENU;
                else if (pin_fail) next_state = S_PIN_FAIL;
            end

            S_PIN_FAIL: begin
                if (attempt_reg >= MAX_ATTEMPTS - 1)
                    next_state = S_LOCKED;
                else
                    next_state = S_PIN_ENTRY;
            end

            S_LOCKED: next_state = S_LOCKED;

            S_MENU: begin
                if (cancel)
                    next_state = S_SESSION_END;
                else if (txn_select == 2'b01)
                    next_state = S_WITHDRAW;
                else if (txn_select == 2'b10)
                    next_state = S_DEPOSIT;
                else if (txn_select == 2'b11)
                    next_state = S_BALANCE_ENQ;
                else if (txn_select == 2'b00 && txn_confirm)
                    next_state = S_NEW_PIN;
            end

            S_WITHDRAW: begin
                if (cancel)
                    next_state = S_MENU;
                // FIX 3: only check txn_done (no txn_confirm guard)
                else if (txn_done)
                    next_state = txn_success ? S_TXN_SUCCESS : S_TXN_FAIL;
            end

            S_DEPOSIT: begin
                if (cancel)
                    next_state = S_MENU;
                // FIX 3
                else if (txn_done)
                    next_state = txn_success ? S_TXN_SUCCESS : S_TXN_FAIL;
            end

            S_BALANCE_ENQ: begin
                if (balance_ready || txn_done || cancel)
                    next_state = S_MENU;
            end

            S_NEW_PIN: begin
                if (cancel)             next_state = S_MENU;
                else if (new_pin_enter) next_state = S_CONFIRM_PIN;
            end

            S_CONFIRM_PIN: begin
                if (cancel)             next_state = S_MENU;
                else if (confirm_enter) next_state = S_PIN_CHANGE;
            end

            // FIX 4: hold in PIN_CHANGE until user_db responds
            S_PIN_CHANGE: begin
                if (pin_written)  next_state = S_TXN_SUCCESS;
                // stay here if pins mismatch ? go to FAIL after 1 cycle
                else if (latched_new_pin != latched_confirm ||
                         latched_new_pin == 16'h0000)
                    next_state = S_TXN_FAIL;
                // else stay and wait for pin_written
            end

            S_TXN_SUCCESS: next_state = S_MENU;
            S_TXN_FAIL:    next_state = S_MENU;
            S_SESSION_END: next_state = S_IDLE;
            default:       next_state = S_IDLE;
        endcase
    end

    // ----------------------------------------------------------
    // Registered Moore outputs
    // ----------------------------------------------------------
    always @(posedge clk) begin
        if (!rst_n) begin
            pin_check_en  <= 1'b0;
            pin_attempt   <= 16'h0000;
            pin_write_en  <= 1'b0;
            new_pin_out   <= 16'h0000;
            attempt_inc   <= 1'b0;
            attempt_rst   <= 1'b0;
            txn_en        <= 1'b0;
            txn_type      <= 2'b00;
            session_active<= 1'b0;
            authenticated <= 1'b0;
            locked_out    <= 1'b0;
            state_out     <= 4'd0;
        end
        else begin
            pin_check_en  <= 1'b0;
            pin_write_en  <= 1'b0;
            attempt_inc   <= 1'b0;
            attempt_rst   <= 1'b0;
            txn_en        <= 1'b0;
            txn_type      <= 2'b00;
            session_active<= 1'b0;
            authenticated <= 1'b0;
            locked_out    <= 1'b0;
            state_out     <= current_state;

            case (current_state)
                S_IDLE:        locked_out    <= internal_locked;

                S_PIN_ENTRY: begin
                    session_active <= 1'b1;
                    pin_attempt    <= pin_in;
                end

                S_PIN_CHECK: begin
                    session_active <= 1'b1;
                    pin_check_en   <= 1'b1;
                    pin_attempt    <= pin_in;
                end

                S_PIN_FAIL: begin
                    session_active <= 1'b1;
                    attempt_inc    <= 1'b1;
                end

                S_LOCKED:      locked_out    <= 1'b1;

                S_MENU: begin
                    session_active <= 1'b1;
                    authenticated  <= 1'b1;
                    attempt_rst    <= 1'b1;
                end

                S_WITHDRAW: begin
                    session_active <= 1'b1;
                    authenticated  <= 1'b1;
                    txn_en         <= 1'b1;
                    txn_type       <= 2'b01;
                end

                S_DEPOSIT: begin
                    session_active <= 1'b1;
                    authenticated  <= 1'b1;
                    txn_en         <= 1'b1;
                    txn_type       <= 2'b10;
                end

                S_BALANCE_ENQ: begin
                    session_active <= 1'b1;
                    authenticated  <= 1'b1;
                    txn_en         <= 1'b1;
                    txn_type       <= 2'b11;
                end

                S_NEW_PIN: begin
                    session_active <= 1'b1;
                    authenticated  <= 1'b1;
                end

                S_CONFIRM_PIN: begin
                    session_active <= 1'b1;
                    authenticated  <= 1'b1;
                end

                S_PIN_CHANGE: begin
                    session_active <= 1'b1;
                    authenticated  <= 1'b1;
                    if (latched_new_pin == latched_confirm &&
                        latched_new_pin != 16'h0000) begin
                        pin_write_en <= 1'b1;
                        new_pin_out  <= latched_new_pin;
                    end
                end

                S_TXN_SUCCESS: begin
                    session_active <= 1'b1;
                    authenticated  <= 1'b1;
                end

                S_TXN_FAIL: begin
                    session_active <= 1'b1;
                    authenticated  <= 1'b1;
                end

                S_SESSION_END: begin
                    session_active <= 1'b0;
                    authenticated  <= 1'b0;
                end

                default: session_active <= 1'b0;
            endcase
        end
    end

endmodule