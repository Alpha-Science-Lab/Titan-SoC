/* Copyright (c) 2024 Tobias Scheipel, David Beikircher, Florian Riedl
 * Embedded Architectures & Systems Group, Graz University of Technology
 * SPDX-License-Identifier: MIT
 * ---------------------------------------------------------------------
 * File: wishbone_test.sv
 *
 * Modified (add scratchpad register, add +3 independent interrupt channels)
 * Md. Jannatul Nayem
 * Org: Alpha Science Lab, April '26, October '26
 */



 module wishbone_test #(
    parameter bit [31:0] ADDRESS,
    parameter bit [31:0] SIZE = 9
) (
    input logic clk,
    input logic rst,
    output logic [3:0] interrupt,
    wishbone_interface.slave wishbone
);
    /*
    Wishbone peripheral for CPU testing
    The following registers are provided:
    - 0x00: Test register: Write to send a message to the testbench
            0x00: Passed test case
            0x01: Failed test case
            0x02: Halt simulation
    - 0x01: Interrupt register0: Down counter, triggers an interrupt when counter reaches 0
    - 0x02: Counter register: Reads return an incrementing number, starting at 0
    - 0x03: Stall Acknowledge register: Reading and writing stall for 3 clock cycles before acknowledging
    - 0x04: Stall Error register: Reading and writing stall for 3 clock cycles before erroring
    - 0x05: Scratchpad register: General-purpose debug/error-cause register
    - 0x06: Interrupt register1: Down counter, triggers an interrupt when counter reaches 0
    - 0x07: Interrupt register2: Down counter, triggers an interrupt when counter reaches 0
    - 0x08: Interrupt register3: Down counter, triggers an interrupt when counter reaches 0
    */


    // --------------------------------------------------------------------------------------------
    // |                                        Registers                                         |
    // --------------------------------------------------------------------------------------------

    logic [31:0] offset;
    assign offset = wishbone.adr - ADDRESS;
    
    // Test register

    logic [31:0] test_reg;
    logic test_stb;

    logic test_sel, test_ack;
    assign test_sel = wishbone.cyc && wishbone.stb && offset == 0;
    assign test_ack = test_sel;
    
    always_ff @(posedge clk) begin
        if (rst) begin
            test_reg <= 0;
            test_stb <= 0;
        end
        else if (test_ack && wishbone.we) begin
            test_reg <= wishbone.dat_mosi;
            test_stb <= 1;
        end
        else begin
            test_reg <= 0;
            test_stb <= 0;
        end
    end

    // Scratchpad register
    // CPU can write extra debug/error-cause information here
    // Testbench can observe scratchpad_stb and scratchpad_reg through hierarchy

    logic [31:0] scratchpad_reg;
    logic scratchpad_stb;

    logic scratchpad_sel, scratchpad_ack;

    assign scratchpad_sel = wishbone.cyc && wishbone.stb && offset == 5;
    assign scratchpad_ack = scratchpad_sel;

    always_ff @(posedge clk) begin
        if (rst) begin
            scratchpad_reg <= 0;
            scratchpad_stb <= 0;
        end
        else if (scratchpad_ack && wishbone.we) begin
            scratchpad_reg <= wishbone.dat_mosi;
            scratchpad_stb <= 1;
        end
        else begin
            scratchpad_stb <= 0;
        end
    end    

    // Interrupt register
    // Keep the legacy register at offset 1 for backward compatibility
    // Additional independent interrupt channels are exposed at offsets 6, 7, 8,
    // while the legacy channel remains at interrupt[0]

    logic [3:0] interrupt_enable;
    logic [3:0] interrupt_sel;
    logic interrupt_ack;

    logic [3:0][31:0] interrupt_counter;

    assign interrupt_sel[0] = wishbone.cyc && wishbone.stb && offset == 1;
    assign interrupt_sel[1] = wishbone.cyc && wishbone.stb && offset == 6;
    assign interrupt_sel[2] = wishbone.cyc && wishbone.stb && offset == 7;
    assign interrupt_sel[3] = wishbone.cyc && wishbone.stb && offset == 8;
    assign interrupt_ack = |interrupt_sel;

    assign interrupt[0] = interrupt_enable[0] && (interrupt_counter[0] == 0);
    assign interrupt[1] = interrupt_enable[1] && (interrupt_counter[1] == 0);
    assign interrupt[2] = interrupt_enable[2] && (interrupt_counter[2] == 0);
    assign interrupt[3] = interrupt_enable[3] && (interrupt_counter[3] == 0);

    always_ff @(posedge clk) begin
        if (rst) begin
            interrupt_counter <= '0;
            interrupt_enable  <= '0;
        end else begin
            if (interrupt_sel[0] && wishbone.we) begin
                interrupt_counter[0] <= wishbone.dat_mosi;
                interrupt_enable[0]  <= (wishbone.dat_mosi > 0);
            end else if (interrupt_counter[0] > 0) begin
                interrupt_counter[0] <= interrupt_counter[0] - 1;
            end

            if (interrupt_sel[1] && wishbone.we) begin
                interrupt_counter[1] <= wishbone.dat_mosi;
                interrupt_enable[1]  <= (wishbone.dat_mosi > 0);
            end else if (interrupt_counter[1] > 0) begin
                interrupt_counter[1] <= interrupt_counter[1] - 1;
            end

            if (interrupt_sel[2] && wishbone.we) begin
                interrupt_counter[2] <= wishbone.dat_mosi;
                interrupt_enable[2]  <= (wishbone.dat_mosi > 0);
            end else if (interrupt_counter[2] > 0) begin
                interrupt_counter[2] <= interrupt_counter[2] - 1;
            end

            if (interrupt_sel[3] && wishbone.we) begin
                interrupt_counter[3] <= wishbone.dat_mosi;
                interrupt_enable[3]  <= (wishbone.dat_mosi > 0);
            end else if (interrupt_counter[3] > 0) begin
                interrupt_counter[3] <= interrupt_counter[3] - 1;
            end
        end
    end

    // Counter register

    logic [31:0] counter;
    logic counter_sel, counter_ack;
    assign counter_sel = wishbone.cyc && wishbone.stb && offset == 2;
    assign counter_ack = counter_sel;

    always_ff @(posedge clk) begin
        if (rst) begin
            counter <= 0;
        end
        else if (counter_ack && wishbone.we) begin
            counter <= wishbone.dat_mosi;
        end
        else if (counter_ack && !wishbone.we) begin
            counter <= counter + 1;
        end
    end

    // Stall register
    logic [31:0] stall_reg;
    logic [1:0] stall_count;
    logic stall_sel, stall_ack, error_sel, error_err;
    assign stall_sel = wishbone.cyc && wishbone.stb && offset == 3;
    assign error_sel = wishbone.cyc && wishbone.stb && offset == 4;
    assign stall_ack = stall_sel && stall_count == 0;
    assign error_err = error_sel && stall_count == 0;

    always_ff @(posedge clk) begin
        if (rst) begin
            stall_count <= 3;
        end
        else if (stall_sel || error_sel) begin
            if (stall_count > 0) begin
                stall_count <= stall_count - 1;
            end
        end
        else begin
            stall_count <= 3;
        end
    end

    always_ff @(posedge clk) begin
        if (rst) begin
            stall_reg <= 0;
        end
        else if (stall_ack && wishbone.we) begin
            stall_reg <= wishbone.dat_mosi;
        end
    end

    // --------------------------------------------------------------------------------------------
    // |                                         Wishbone                                         |
    // --------------------------------------------------------------------------------------------

    logic wishbone_sel;
    assign wishbone_sel = |{
        test_sel,
        interrupt_sel[0],
        interrupt_sel[1],
        interrupt_sel[2],
        interrupt_sel[3],
        counter_sel,
        stall_sel,
        error_sel,
        scratchpad_sel
    };

    assign wishbone.ack = |{
        test_ack,
        interrupt_ack,
        counter_ack,
        stall_ack,
        scratchpad_ack
    };

    assign wishbone.err = |{
        wishbone.adr >= ADDRESS && wishbone.adr < ADDRESS + SIZE && !wishbone_sel,
        error_err
    };

    assign wishbone.dat_miso =
        interrupt_sel[0] ? interrupt_counter[0] :
        interrupt_sel[1] ? interrupt_counter[1] :
        interrupt_sel[2] ? interrupt_counter[2] :
        interrupt_sel[3] ? interrupt_counter[3] :
        counter_ack ? counter :
        stall_ack ? stall_reg :
        scratchpad_ack ? scratchpad_reg : 32'b0;

endmodule
