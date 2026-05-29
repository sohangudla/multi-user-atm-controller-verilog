`timescale 1ns / 1ps
// ============================================================
// Module : tb_atm_top.v
// Description : Multi-User Real ATM Full Testbench
//
// Users tested:
//   Alice   (ID=00, PIN=1111, Balance=50000)
//   Bob     (ID=01, PIN=2222, Balance=30000)
//   Charlie (ID=10, PIN=3333, Balance=15000)
//   Diana   (ID=11, PIN=4444, Balance=20000)
//
// Test Cases:
//   TC1 : Alice   - correct PIN + withdraw 5000
//   TC2 : Bob     - correct PIN + deposit 10000
//   TC3 : Charlie - correct PIN + balance enquiry
//   TC4 : Diana   - correct PIN + change PIN + login with new PIN
//   TC5 : Alice   - 3 wrong PINs ? hard lock
//   TC6 : Bob     - insufficient funds withdrawal
//   TC7 : Alice withdraws, balance persists for next session
//   TC8 : Charlie + Diana sequential sessions (DB consistency)
// ============================================================

module tb_atm_top;

    reg         clk;
    reg         rst_n;
    reg         db_init;       // Pulse once at power-on to load factory DB defaults
    reg         card_inserted;
    reg  [1:0]  card_id;
    reg  [15:0] pin_in;
    reg         pin_enter;
    reg  [15:0] new_pin_in;
    reg         new_pin_enter;
    reg  [15:0] confirm_pin_in;
    reg         confirm_enter;
    reg  [1:0]  txn_select;
    reg  [15:0] txn_amount;
    reg         txn_confirm;
    reg         cancel;

    wire [7:0]  display_out;
    wire [15:0] balance_out;
    wire [1:0]  user_disp;
    wire        locked;
    wire        authenticated;
    wire        session_active;
    wire        txn_done;
    wire        txn_success;

    integer pass_count;
    integer fail_count;

    // DUT
    atm_top u_dut (
        .clk             (clk),
        .rst_n           (rst_n),
        .db_init         (db_init),
        .card_inserted   (card_inserted),
        .card_id         (card_id),
        .pin_in          (pin_in),
        .pin_enter       (pin_enter),
        .new_pin_in      (new_pin_in),
        .new_pin_enter   (new_pin_enter),
        .confirm_pin_in  (confirm_pin_in),
        .confirm_enter   (confirm_enter),
        .txn_select      (txn_select),
        .txn_amount      (txn_amount),
        .txn_confirm     (txn_confirm),
        .cancel          (cancel),
        .display_out     (display_out),
        .balance_out     (balance_out),
        .user_disp       (user_disp),
        .locked          (locked),
        .authenticated   (authenticated),
        .session_active  (session_active),
        .txn_done        (txn_done),
        .txn_success     (txn_success)
    );

    // 100 MHz clock
    initial clk = 0;
    always #5 clk = ~clk;

    // User IDs
    parameter ALICE   = 2'b00;
    parameter BOB     = 2'b01;
    parameter CHARLIE = 2'b10;
    parameter DIANA   = 2'b11;

    // PINs
    parameter ALICE_PIN   = 16'h1111;
    parameter BOB_PIN     = 16'h2222;
    parameter CHARLIE_PIN = 16'h3333;
    parameter DIANA_PIN   = 16'h4444;
    parameter WRONG_PIN   = 16'h0000;
    parameter NEW_PIN     = 16'h9999;

    // Initial balances
    parameter ALICE_BAL   = 16'd50000;
    parameter BOB_BAL     = 16'd30000;
    parameter CHARLIE_BAL = 16'd15000;
    parameter DIANA_BAL   = 16'd20000;

    // --------------------------------------------------------
    // Helper tasks
    // --------------------------------------------------------
    task wait_cycles;
        input integer n;
        integer i;
        begin
            for (i = 0; i < n; i = i + 1)
                @(posedge clk);
            #1;
        end
    endtask

    task apply_reset;
        begin
            rst_n          <= 1'b0;
            db_init        <= 1'b0;
            card_inserted  <= 1'b0;
            card_id        <= 2'b00;
            pin_in         <= 16'h0000;
            pin_enter      <= 1'b0;
            new_pin_in     <= 16'h0000;
            new_pin_enter  <= 1'b0;
            confirm_pin_in <= 16'h0000;
            confirm_enter  <= 1'b0;
            txn_select     <= 2'b00;
            txn_amount     <= 16'd0;
            txn_confirm    <= 1'b0;
            cancel         <= 1'b0;
            wait_cycles(5);
            rst_n   <= 1'b1;
            // Pulse db_init for ONE cycle to load factory DB defaults.
            // This only runs at simulation start - never called again.
            db_init <= 1'b1;
            wait_cycles(1);
            db_init <= 1'b0;
            wait_cycles(3);
            $display("[RESET] Power-on reset - factory DB values loaded (all 4 users)");
        end
    endtask

    // clear_lockout: resets FSM/lockout state WITHOUT touching the database.
    // Use this instead of apply_reset between test cases so that balance
    // and PIN changes from earlier TCs are preserved.
    task clear_lockout;
        begin
            rst_n         <= 1'b0;
            card_inserted <= 1'b0;
            cancel        <= 1'b0;
            // db_init stays LOW - DB is untouched
            wait_cycles(5);
            rst_n <= 1'b1;
            wait_cycles(3);
            $display("[RST]   Lockout cleared - DB state preserved (balances/PINs intact)");
        end
    endtask

    task insert_card_user;
        input [1:0]  uid;
        input [63:0] name; // 8-char string
        begin
            card_id       <= uid;
            card_inserted <= 1'b1;
            wait_cycles(2);
            $display("[CARD]  Card inserted - User %0d at %0t", uid, $time);
        end
    endtask

    task enter_pin;
        input [15:0] pin;
        begin
            pin_in    <= pin;
            wait_cycles(2);
            pin_enter <= 1'b1;
            wait_cycles(1);
            pin_enter <= 1'b0;
            wait_cycles(8);
            $display("[PIN]   Entered PIN=%h at %0t", pin, $time);
        end
    endtask

    task do_withdraw;
        input [15:0] amount;
        begin
            txn_select  <= 2'b01;
            txn_amount  <= amount;
            wait_cycles(2);
            txn_confirm <= 1'b1;
            wait_cycles(1);
            txn_confirm <= 1'b0;
            txn_select  <= 2'b00;
            wait_cycles(8);
            $display("[TXN]   Withdraw %0d | ok=%b | bal=%0d",
                     amount, txn_success, balance_out);
        end
    endtask

    task do_deposit;
        input [15:0] amount;
        begin
            txn_select  <= 2'b10;
            txn_amount  <= amount;
            wait_cycles(2);
            txn_confirm <= 1'b1;
            wait_cycles(1);
            txn_confirm <= 1'b0;
            txn_select  <= 2'b00;
            wait_cycles(8);
            $display("[TXN]   Deposit  %0d | ok=%b | bal=%0d",
                     amount, txn_success, balance_out);
        end
    endtask

    task do_balance;
        begin
            txn_select  <= 2'b11;
            wait_cycles(2);
            txn_confirm <= 1'b1;
            wait_cycles(1);
            txn_confirm <= 1'b0;
            txn_select  <= 2'b00;
            wait_cycles(8);
            $display("[BAL]   Balance = Rs.%0d at %0t", balance_out, $time);
        end
    endtask

    task do_change_pin;
        input [15:0] npin;
        input [15:0] cpin;
        begin
            txn_select  <= 2'b00;
            txn_confirm <= 1'b1;
            wait_cycles(1);
            txn_confirm    <= 1'b0;
            txn_select     <= 2'b00;
            wait_cycles(3);
            new_pin_in     <= npin;
            wait_cycles(2);
            new_pin_enter  <= 1'b1;
            wait_cycles(1);
            new_pin_enter  <= 1'b0;
            wait_cycles(3);
            confirm_pin_in <= cpin;
            wait_cycles(2);
            confirm_enter  <= 1'b1;
            wait_cycles(1);
            confirm_enter  <= 1'b0;
            wait_cycles(10);
            $display("[PIN]   Change PIN: new=%h confirm=%h | ok=%b",
                     npin, cpin, txn_success);
        end
    endtask

    task do_logout;
        begin
            cancel        <= 1'b1;
            wait_cycles(1);
            cancel        <= 1'b0;
            card_inserted <= 1'b0;
            wait_cycles(5);
            $display("[OUT]   Session ended - card returned");
        end
    endtask

    task check;
        input        cond;
        input [255:0] lbl;
        begin
            if (cond) begin
                $display("  [PASS] %s", lbl);
                pass_count = pass_count + 1;
            end else begin
                $display("  [FAIL] %s", lbl);
                fail_count = fail_count + 1;
            end
        end
    endtask

    task tc_header;
        input integer n;
        input [255:0] desc;
        begin
            $display("");
            $display("============================================================");
            $display("  TC%0d : %s", n, desc);
            $display("============================================================");
        end
    endtask

    // ========================================================
    // MAIN TEST SEQUENCE
    // ========================================================
    initial begin
        pass_count = 0;
        fail_count = 0;
        db_init    = 1'b0;
        $dumpfile("atm_multiuser.vcd");
        $dumpvars(0, tb_atm_top);

        $display("");
        $display("************************************************************");
        $display("  MULTI-USER REAL ATM SYSTEM - FULL TESTBENCH");
        $display("  Alice(00)=50000 | Bob(01)=30000 |");
        $display("  Charlie(10)=15000 | Diana(11)=20000");
        $display("************************************************************");

        apply_reset;

        // ====================================================
        // TC1: Alice - correct PIN + withdraw 5000
        // Expect: balance 50000 - 5000 = 45000
        // ====================================================
        tc_header(1, "Alice (ID=00) - Login + Withdraw Rs.5000");
        insert_card_user(ALICE, "Alice   ");
        enter_pin(ALICE_PIN);
        wait_cycles(3);
        check(authenticated == 1'b1, "Alice authenticated");
        check(user_disp     == ALICE, "Correct user selected");

        do_withdraw(16'd5000);
        wait_cycles(5);
        check(txn_success == 1'b1,   "Withdrawal accepted");
        check(balance_out == 16'd45000, "Alice balance = 45000");
        do_logout;

        // ====================================================
        // TC2: Bob - correct PIN + deposit 10000
        // Expect: balance 30000 + 10000 = 40000
        // ====================================================
        tc_header(2, "Bob (ID=01) - Login + Deposit Rs.10000");
        insert_card_user(BOB, "Bob     ");
        enter_pin(BOB_PIN);
        wait_cycles(3);
        check(authenticated == 1'b1, "Bob authenticated");

        do_deposit(16'd10000);
        wait_cycles(5);
        check(txn_success == 1'b1,   "Deposit accepted");
        check(balance_out == 16'd40000, "Bob balance = 40000");
        do_logout;

        // ====================================================
        // TC3: Charlie - correct PIN + balance enquiry
        // Expect: balance shows 15000
        // ====================================================
        tc_header(3, "Charlie (ID=10) - Login + Balance Enquiry");
        insert_card_user(CHARLIE, "Charlie ");
        enter_pin(CHARLIE_PIN);
        wait_cycles(3);
        check(authenticated == 1'b1, "Charlie authenticated");

        do_balance;
        wait_cycles(5);
        check(balance_out == 16'd15000, "Charlie balance = 15000");
        do_logout;

        // ====================================================
        // TC4: Diana - correct PIN + change PIN + re-login
        // Change 4444 ? 9999, then login with 9999
        // ====================================================
        tc_header(4, "Diana (ID=11) - Change PIN 4444->9999 + Re-login");
        insert_card_user(DIANA, "Diana   ");
        enter_pin(DIANA_PIN);
        wait_cycles(3);
        check(authenticated == 1'b1, "Diana authenticated");

        do_change_pin(NEW_PIN, NEW_PIN); // 9999 == 9999 ? accepted
        wait_cycles(5);
        check(txn_success == 1'b1, "PIN changed successfully");
        do_logout;

        // Re-login with new PIN 9999
        insert_card_user(DIANA, "Diana   ");
        enter_pin(NEW_PIN); // Should work now
        wait_cycles(3);
        check(authenticated == 1'b1, "Diana re-login with new PIN 9999");
        check(balance_out == DIANA_BAL, "Diana balance unchanged after PIN change");
        do_logout;

        // ====================================================
        // TC5: Alice - 3 wrong PINs ? hard lock
        // (Alice balance should be 45000 from TC1 - persists)
        // ====================================================
        tc_header(5, "Alice (ID=00) - 3 Wrong PINs ? Hard Lock");
        insert_card_user(ALICE, "Alice   ");

        enter_pin(WRONG_PIN); // Attempt 1
        wait_cycles(5);
        check(locked == 1'b0, "Not locked after attempt 1");

        enter_pin(WRONG_PIN); // Attempt 2
        wait_cycles(5);
        check(locked == 1'b0, "Not locked after attempt 2");

        enter_pin(WRONG_PIN); // Attempt 3 - triggers lock
        wait_cycles(30);
        $display("[TC5]   After 3rd wrong: locked=%b session=%b auth=%b",
                 locked, session_active, authenticated);
        check(locked         == 1'b1, "LOCKED after 3 wrong PINs");
        check(authenticated  == 1'b0, "Not authenticated");
        check(session_active == 1'b0, "Session inactive");

        // Card re-insert attempt - must stay locked
        card_inserted <= 1'b1;
        wait_cycles(5);
        check(locked == 1'b1, "Still locked after card re-insert");
        card_inserted <= 1'b0;

        clear_lockout; // Clears FSM/lock state - DB balances and PINs are preserved
        wait_cycles(3);
        check(locked == 1'b0, "Lock cleared after clear_lockout");

        // ====================================================
        // TC6: Bob - insufficient funds (try to withdraw 50000 from 40000)
        // Bob had 40000 after TC2 deposit - DB persists across reset.
        // ====================================================
        tc_header(6, "Bob (ID=01) - Insufficient Funds Withdrawal");
        insert_card_user(BOB, "Bob     ");
        enter_pin(BOB_PIN);
        wait_cycles(3);
        check(authenticated == 1'b1, "Bob authenticated");
        check(balance_out == 16'd40000, "Bob balance persists at 40000 from TC2");

        do_withdraw(16'd50000); // More than 40000
        wait_cycles(5);
        check(txn_success == 1'b0,     "Withdrawal rejected correctly");
        check(balance_out == 16'd40000, "Bob balance unchanged at 40000");
        do_logout;

        // ====================================================
        // TC7: Balance persistence within session
        // Alice starts at 45000 (persisted from TC1 withdrawal of 5000).
        // Withdraws twice - balance updates both times.
        // ====================================================
        tc_header(7, "Alice - Balance Persists Across Two Withdrawals");
        insert_card_user(ALICE, "Alice   ");
        enter_pin(ALICE_PIN);
        wait_cycles(3);
        check(balance_out == 16'd45000, "Alice starts at 45000 (persisted from TC1)");

        do_withdraw(16'd10000); // 45000 - 10000 = 35000
        wait_cycles(5);
        check(balance_out == 16'd35000, "Alice balance = 35000 after 1st withdraw");

        do_withdraw(16'd15000); // 35000 - 15000 = 20000
        wait_cycles(5);
        check(balance_out == 16'd20000, "Alice balance = 20000 after 2nd withdraw");

        do_balance; // Should still show 20000
        wait_cycles(5);
        check(balance_out == 16'd20000, "Balance enquiry shows 20000");
        do_logout;

        // ====================================================
        // TC8: Sequential sessions - Charlie then Diana
        // Verify DB is consistent and users don't see each other's data.
        // Diana's PIN is still 9999 (changed in TC4, DB persists across reset).
        // ====================================================
        tc_header(8, "DB Consistency - Charlie then Diana sequential");
        insert_card_user(CHARLIE, "Charlie ");
        enter_pin(CHARLIE_PIN);
        wait_cycles(3);
        check(authenticated == 1'b1,  "Charlie authenticated");
        check(balance_out == CHARLIE_BAL, "Charlie sees own balance 15000");
        check(user_disp == CHARLIE,    "user_disp = Charlie");
        do_deposit(16'd5000);
        wait_cycles(5);
        check(balance_out == 16'd20000, "Charlie balance = 20000 after deposit");
        do_logout;

        // Diana logs in - should see her own balance, not Charlie's.
        // PIN is 9999 (changed in TC4 - persisted because DB was not wiped).
        insert_card_user(DIANA, "Diana   ");
        enter_pin(NEW_PIN); // 9999 - persisted from TC4
        wait_cycles(3);
        check(authenticated == 1'b1,  "Diana authenticated with persisted PIN 9999");
        check(balance_out == DIANA_BAL, "Diana sees own balance 20000, not Charlie's");
        check(user_disp == DIANA,      "user_disp = Diana");
        do_logout;

        // Charlie logs in again - should still see his updated 20000
        insert_card_user(CHARLIE, "Charlie ");
        enter_pin(CHARLIE_PIN);
        wait_cycles(3);
        check(balance_out == 16'd20000, "Charlie balance persists at 20000");
        do_logout;

        // ====================================================
        // FINAL REPORT
        // ====================================================
        $display("");
        $display("************************************************************");
        $display("  SIMULATION COMPLETE");
        $display("  PASSED : %0d", pass_count);
        $display("  FAILED : %0d", fail_count);
        $display("  TOTAL  : %0d", pass_count + fail_count);
        $display("************************************************************");
        $display("");

        if (fail_count == 0)
            $display("  >> ALL TESTS PASSED - Multi-User ATM Verified <<");
        else
            $display("  >> %0d FAILED - Check waveforms <<", fail_count);

        $display("");
        $finish;
    end

    // Watchdog
    initial begin
        #1000000;
        $display("[WATCHDOG] Timeout");
        $finish;
    end

    // FSM state monitor
    reg [3:0] prev_state;
    always @(posedge clk) begin
        prev_state <= u_dut.u_atm_fsm.current_state;
        if (u_dut.u_atm_fsm.current_state !== prev_state) begin
            case (u_dut.u_atm_fsm.current_state)
                4'd0:  $display("[FSM] -> IDLE        at %0t", $time);
                4'd1:  $display("[FSM] -> PIN_ENTRY   at %0t", $time);
                4'd2:  $display("[FSM] -> PIN_CHECK   at %0t", $time);
                4'd3:  $display("[FSM] -> PIN_FAIL    at %0t", $time);
                4'd4:  $display("[FSM] -> LOCKED      at %0t", $time);
                4'd5:  $display("[FSM] -> MENU        at %0t", $time);
                4'd6:  $display("[FSM] -> WITHDRAW    at %0t", $time);
                4'd7:  $display("[FSM] -> DEPOSIT     at %0t", $time);
                4'd8:  $display("[FSM] -> BALANCE_ENQ at %0t", $time);
                4'd9:  $display("[FSM] -> NEW_PIN     at %0t", $time);
                4'd10: $display("[FSM] -> CONFIRM_PIN at %0t", $time);
                4'd11: $display("[FSM] -> PIN_CHANGE  at %0t", $time);
                4'd12: $display("[FSM] -> SUCCESS     at %0t", $time);
                4'd13: $display("[FSM] -> FAIL        at %0t", $time);
                4'd14: $display("[FSM] -> SESSION_END at %0t", $time);
            endcase
        end
    end

endmodule