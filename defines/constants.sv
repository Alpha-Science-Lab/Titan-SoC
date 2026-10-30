/* Copyright (c) 2024 Tobias Scheipel, David Beikircher, Florian Riedl
 * Embedded Architectures & Systems Group, Graz University of Technology
 * SPDX-License-Identifier: MIT
 * ---------------------------------------------------------------------
 * File: constants.sv
 */

/*verilator lint_off UNUSED*/

package constants;
    // --------------------------------------------------------------------------------------------
    // |                                   Wishbone Constants                                     |
    // --------------------------------------------------------------------------------------------
    localparam bit [31:0] MEMORY_START = 32'h0005_0000;
    localparam bit [31:0] MEMORY_SIZE  = 32'h0000_0400;

    localparam bit [31:0] TCIM0_START  = 32'h0001_0000;
    localparam bit [31:0] TCIM1_START  = 32'h0002_0000;
    localparam bit [31:0] TCIM2_START  = 32'h0003_0000;
    localparam bit [31:0] TCIM3_START  = 32'h0004_0000;

    localparam bit [31:0] LEDS_START = 32'h0008_0000;
    localparam bit [31:0] LEDS_SIZE  = 32'h0000_0001;

    localparam bit [31:0] BUTTONS_START = 32'h0008_1000;
    localparam bit [31:0] BUTTONS_SIZE  = 32'h0000_0001;

    localparam bit [31:0] SWITCHES_START = 32'h0008_2000;
    localparam bit [31:0] SWITCHES_SIZE  = 32'h0000_0001;

    localparam bit [31:0] SEGMENTS_START = 32'h0008_3000;
    localparam bit [31:0] SEGMENTS_SIZE  = 32'h0000_0001;

    localparam bit [31:0] UART_START = 32'h0008_4000;
    localparam bit [31:0] UART_SIZE  = 32'h0000_0001;

    localparam bit [31:0] TIMER_START = 32'h0008_5000;
    localparam bit [31:0] TIMER_SIZE  = 32'h0000_000B;

    localparam bit [31:0] I2C_START = 32'h0008_5200;
    localparam bit [31:0] I2C_SIZE  = 32'h0000_0006;

    localparam bit [31:0] SPI0_START = 32'h0008_5400;
    localparam bit [31:0] SPI1_START = 32'h0008_5500;
    localparam bit [31:0] SPI_SIZE  = 32'h0000_0006;

    localparam bit [31:0] VGA_START = 32'h0009_0000;
    localparam bit [31:0] VGA_SIZE  = 32'h0000_9600; // 640 * 480 pixel with 4 bit color depth

    localparam bit [31:0] TEST_START = 32'h0012_0000;
    localparam bit [31:0] TEST_SIZE  = 32'h0000_0009;

    localparam bit [31:0] RST_CTRL_START = 32'h0012_0100;
    localparam bit [31:0] RST_CTRL_SIZE  = 32'h0000_0001;

    localparam bit [31:0] SPINLOCK_START = 32'h0012_0200;
    localparam bit [31:0] SPINLOCK_SIZE  = 32'h0000_0020;

    localparam bit [31:0] BIFROST_START = 32'h0012_0300;
    localparam bit [31:0] BIFROST_SIZE  = 32'h0000_0040;

    // --------------------------------------------------------------------------------------------
    // |                                    Address Constants                                     |
    // --------------------------------------------------------------------------------------------
    localparam bit [31:0] CPU0_RESET_VECTOR = TCIM0_START << 2;
    localparam bit [31:0] CPU1_RESET_VECTOR = TCIM1_START << 2;
    localparam bit [31:0] CPU2_RESET_VECTOR = TCIM2_START << 2;
    localparam bit [31:0] CPU3_RESET_VECTOR = TCIM3_START << 2;

    // --------------------------------------------------------------------------------------------
    // |                                  Instruction Constants                                   |
    // --------------------------------------------------------------------------------------------
    localparam bit [31:0] NOP = 32'h00000013;

endpackage

/*verilator lint_on UNUSED*/
