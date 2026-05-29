`timescale 1ns / 1ps
// ============================================================
// Module : atm_top.v  (FIXED)
// FIX: account_ctrl.txn_confirm driven by fsm.txn_confirm_r
//      (registered) - eliminates timing race where raw txn_confirm
//      pulse went low before txn_en even rose.
// ============================================================

module atm_top (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        db_init,       // Pulse once at startup to load factory DB defaults
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
    output wire [7:0]  display_out,
    output wire [15:0] balance_out,
    output wire [1:0]  user_disp,
    output wire        locked,
    output wire        authenticated,
    output wire        session_active,
    output wire        txn_done,
    output wire        txn_success
);

    wire        fsm_pin_check_en;
    wire [15:0] fsm_pin_attempt;
    wire        fsm_pin_write_en;
    wire [15:0] fsm_new_pin;
    wire [1:0]  fsm_active_user;
    wire        db_pin_match, db_pin_fail, db_pin_written, db_bal_written;
    wire [15:0] db_balance_out;
    wire [15:0] acct_new_balance;
    wire        acct_bal_write_en;
    wire        acct_txn_done, acct_txn_success, acct_balance_ready;
    wire        fsm_txn_en;
    wire [1:0]  fsm_txn_type;
    wire        fsm_txn_confirm_r;   // FIX: registered txn_confirm
    wire        fsm_attempt_inc, fsm_attempt_rst;
    wire        lock_locked;
    wire [1:0]  lock_attempt_count;
    wire [3:0]  fsm_state_out;
    wire        fsm_authenticated, fsm_session_active, fsm_locked_out;
    wire [15:0] disp_balance;
    wire [1:0]  disp_user;

    assign locked        = fsm_locked_out;
    assign authenticated = fsm_authenticated;
    assign session_active= fsm_session_active;
    assign txn_done      = acct_txn_done;
    assign txn_success   = acct_txn_success;
    assign balance_out   = disp_balance;
    assign user_disp     = disp_user;

    user_db u_user_db (
        .clk(clk), .rst_n(rst_n), .db_init(db_init),
        .user_id(fsm_active_user),
        .pin_attempt(fsm_pin_attempt), .pin_check_en(fsm_pin_check_en),
        .pin_match(db_pin_match), .pin_fail(db_pin_fail),
        .new_pin(fsm_new_pin), .pin_write_en(fsm_pin_write_en),
        .pin_written(db_pin_written),
        .balance_out(db_balance_out),
        .new_balance(acct_new_balance), .bal_write_en(acct_bal_write_en),
        .bal_written(db_bal_written)
    );

    atm_fsm u_atm_fsm (
        .clk(clk), .rst_n(rst_n),
        .card_inserted(card_inserted), .card_id(card_id),
        .pin_in(pin_in), .pin_enter(pin_enter),
        .new_pin_in(new_pin_in), .new_pin_enter(new_pin_enter),
        .confirm_pin_in(confirm_pin_in), .confirm_enter(confirm_enter),
        .txn_select(txn_select), .txn_amount(txn_amount),
        .txn_confirm(txn_confirm), .cancel(cancel),
        .pin_match(db_pin_match), .pin_fail(db_pin_fail),
        .pin_written(db_pin_written), .bal_written(db_bal_written),
        .txn_done(acct_txn_done), .txn_success(acct_txn_success),
        .balance_ready(acct_balance_ready),
        .pin_check_en(fsm_pin_check_en), .pin_attempt(fsm_pin_attempt),
        .pin_write_en(fsm_pin_write_en), .new_pin_out(fsm_new_pin),
        .active_user(fsm_active_user),
        .attempt_inc(fsm_attempt_inc), .attempt_rst(fsm_attempt_rst),
        .txn_en(fsm_txn_en), .txn_type(fsm_txn_type),
        .txn_confirm_r(fsm_txn_confirm_r),       // FIX
        .session_active(fsm_session_active),
        .authenticated(fsm_authenticated),
        .locked_out(fsm_locked_out),
        .state_out(fsm_state_out)
    );

    // FIX: use fsm_txn_confirm_r (registered) not raw txn_confirm
    account_ctrl u_account_ctrl (
        .clk(clk), .rst_n(rst_n),
        .txn_en(fsm_txn_en), .txn_type(fsm_txn_type),
        .txn_confirm(fsm_txn_confirm_r),           // FIX
        .txn_amount(txn_amount),
        .balance_in(db_balance_out),
        .new_balance(acct_new_balance), .bal_write_en(acct_bal_write_en),
        .txn_done(acct_txn_done), .txn_success(acct_txn_success),
        .balance_ready(acct_balance_ready)
    );

    lockout_ctrl u_lockout_ctrl (
        .clk(clk), .rst_n(rst_n),
        .attempt_inc(fsm_attempt_inc), .attempt_rst(fsm_attempt_rst),
        .locked(lock_locked), .attempt_count(lock_attempt_count)
    );

    display_ctrl u_display_ctrl (
        .clk(clk), .rst_n(rst_n),
        .state_in(fsm_state_out),
        .active_user(fsm_active_user),
        .authenticated(fsm_authenticated),
        .balance_in(db_balance_out),
        .locked_in(fsm_locked_out),
        .display_out(display_out),
        .balance_disp(disp_balance),
        .user_disp(disp_user)
    );

endmodule