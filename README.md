This project presents a secure and simulation-verified Multi-User ATM Controller designed using Verilog HDL in Xilinx Vivado. The system is implemented using a modular FSM-based architecture supporting card authentication, PIN verification, balance enquiry, cash withdrawal, cash deposit, PIN change, transaction validation, and hard lockout security after multiple invalid attempts.

The design includes dedicated modules such as:
- ATM Finite State Machine (FSM)
- User Database
- Account Controller
- Lockout Controller
- Display Controller
- Top-Level Integration Module

The project was functionally verified using a comprehensive Verilog testbench covering multiple real-time ATM transaction scenarios including successful authentication, invalid PIN attempts, balance persistence, insufficient funds handling, PIN updates, and multi-user database consistency.

Tools Used:
- Verilog HDL
- Xilinx Vivado
- FSM-Based Digital Design
- Simulation & Functional Verification

Features:
- Multi-user account handling
- Secure PIN authentication
- Deposit & withdrawal operations
- Balance enquiry
- PIN change support
- Hard lockout after 3 invalid attempts
- Persistent session-based database updates
- Fully verified using waveform simulation and automated test cases
