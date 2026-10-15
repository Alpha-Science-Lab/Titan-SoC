/*
 File: Titan.sv
 Multicore Hadi-V SoC AlphaTitan
 Organization: Alpha Science Lab
 October 2026
 Author: Md. Mosharrof, Jubayer Fahad
*/

module Titan(
    parameter real CLK_FREQUENCY_MHZ,
    parameter int  UART_BAUD_RATE
) (
    // Main system clk
    input logic clk,
    
    // Buttons
    input  logic [4:0] buttons_async,

    // UART
    input  logic uart_rx_async,
    output logic uart_tx
);
    import constants::*;

    logic [4:0] buttons;
    logic uart_rx;
    logic [15:0] leds_state;

    logic rst = 1;
    always_ff @(posedge clk) begin
        rst <= buttons[0];
    end

    logic [15:0] rst_out;

    for (genvar i = 0; i < 5; i++) begin : button_conditioning
        synchronizer button_sync(
            .clk(clk),
            .async_in(buttons_async[i]),
            .sync_out(buttons[i])
        );
    end

    synchronizer uart_rx_sync(
        .clk(clk),
        .async_in(uart_rx_async),
        .sync_out(uart_rx)
    );

    logic [3:0] test_interrupt;
    logic uart_interrupt;
    logic [3:0] timer_interrupt;


    // Wishbone bus interfaces for CPU cores
    /* core0 (4,0) core1 (5,1) core2 (6,2) core3 (7,3) */
    wishbone_interface bus_masters[8]();

    // Wishbone slaves (memory mapped peripherals)
    wishbone_interface slaves[10]();

    // System bus connecting cores to memory-mapped peripherals
    /* AetherLink */
    aetherlink #(
        .NUM_MASTERS(4),
        .NUM_SLAVES(10),
        .SLAVE_ADDRESS
        ({
            TCIM0_START, TCIM1_START, TCIM2_START, TCIM3_START,
            MEMORY_START, BUTTONS_START, LEDS_START, UART_START,
            TIMER_START, TEST_START
        }),
        .SLAVE_SIZE
        ({
            MEMORY_SIZE, MEMORY_SIZE, MEMORY_SIZE, MEMORY_SIZE,
            MEMORY_SIZE, BUTTONS_SIZE, LEDS_SIZE, UART_SIZE,
            TIMER_SIZE, TEST_SIZE
        })
        /* Multimaster wishbone interconnect */
    ) aetherlink_interconnect (
        .clk(clk),
        .rst(rst),
        .masters(bus_masters[3:0]), 
        .slaves(slaves)
    );


    // CPU cores
    Hadi_V #(
        .RESET_VECTOR(CPU0_RESET_VECTOR),
        .HART_ID(32'h0)
    ) core0 (
        .clk(clk),
        .rst(rst),
        .memory_fetch_port(bus_masters[4].master),
        .memory_mem_port(bus_masters[0].master),
        .external_interrupt_in(uart_interrupt || test_interrupt[0]),
        .timer_interrupt_in(timer_interrupt[0])
    );

    Hadi_V #(
        .RESET_VECTOR(CPU1_RESET_VECTOR),
        .HART_ID(32'h1)
    ) core1 (
        .clk(clk),
        .rst(rst_out[1]),
        .memory_fetch_port(bus_masters[5].master),
        .memory_mem_port(bus_masters[1].master),
        .external_interrupt_in(test_interrupt[1]),
        .timer_interrupt_in(timer_interrupt[1])
    );

    Hadi_V #(
        .RESET_VECTOR(CPU2_RESET_VECTOR),
        .HART_ID(32'h2)
    ) core2 (
        .clk(clk),
        .rst(rst_out[2]),
        .memory_fetch_port(bus_masters[6].master),
        .memory_mem_port(bus_masters[2].master),
        .external_interrupt_in(test_interrupt[2]), 
        .timer_interrupt_in(timer_interrupt[2])
    );

    Hadi_V #(
        .RESET_VECTOR(CPU3_RESET_VECTOR),
        .HART_ID(32'h3)
    ) core3 (
        .clk(clk),
        .rst(rst_out[3]),
        .memory_fetch_port(bus_masters[7].master),
        .memory_mem_port(bus_masters[3].master),
        .external_interrupt_in(test_interrupt[3]), 
        .timer_interrupt_in(timer_interrupt[3])
    );


    // (TCIM 0-3)
    wishbone_ram #(
        .ADDRESS(TCIM0_START),
        .SIZE(MEMORY_SIZE)
    ) tcim0 (
        .clk(~clk),
        .rst(rst),
        .port_a(bus_masters[4].master),
        .port_b(slaves[0].slave)
    );

    wishbone_ram #(
        .ADDRESS(TCIM1_START),
        .SIZE(MEMORY_SIZE)
    ) tcim1 (
        .clk(~clk),
        .rst(rst),
        .port_a(bus_masters[5].master),
        .port_b(slaves[1].slave)
    );

    wishbone_ram #(
        .ADDRESS(TCIM2_START),
        .SIZE(MEMORY_SIZE)
    ) tcim2 (
        .clk(~clk),
        .rst(rst),
        .port_a(bus_masters[6].master),
        .port_b(slaves[2].slave)
    );

    wishbone_ram #(
        .ADDRESS(TCIM3_START),
        .SIZE(MEMORY_SIZE)
    ) tcim3 (
        .clk(~clk),
        .rst(rst),
        .port_a(bus_masters[7].master),
        .port_b(slaves[3].slave)
    );

    // Shared SRAM
    wishbone_ram #(
        .ADDRESS(MEMORY_START),
        .SIZE(MEMORY_SIZE)
    ) sram (
        .clk(~clk),
        .rst(rst),
        .port_a(slaves[4].slave)
        // port_b is unused
    );

    // Wishbone peripherals
    wishbone_buttons #(
        .ADDRESS(BUTTONS_START),
        .SIZE(BUTTONS_SIZE)
    ) buttons_periph (
        .clk(clk),
        .rst(rst),
        .buttons(buttons),
        .wishbone(slaves[5].slave)
    );

    wishbone_leds #(
        .ADDRESS(LEDS_START),
        .SIZE(LEDS_SIZE)
    ) leds_periph (
        .clk(clk),
        .rst(rst),
        .leds(leds_state),
        .wishbone(slaves[6].slave)
    );

    wishbone_uart #(
        .ADDRESS(UART_START),
        .SIZE(UART_SIZE),
        .BAUD_RATE(UART_BAUD_RATE),
        .CLK_FREQUENCY_MHZ(CLK_FREQUENCY_MHZ)
    ) uart_periph (
        .clk(clk),
        .rst(rst),
        .rx_serial_in(uart_rx),
        .tx_serial_out(uart_tx),
        .interrupt(uart_interrupt),
        .wishbone(slaves[7].slave)
    );

    wishbone_timer #(
        .ADDRESS(TIMER_START),
        .SIZE(TIMER_SIZE),
        .CLK_FREQUENCY_MHZ(CLK_FREQUENCY_MHZ)
    ) timer_periph (
        .clk(clk),
        .rst(rst),
        .interrupt(timer_interrupt),
        .wishbone(slaves[8].slave)
    );

    wishbone_test #(
        .ADDRESS(TEST_START),
        .SIZE(TEST_SIZE)
    ) test_periph (
        .clk(clk),
        .rst(rst),
        .interrupt(test_interrupt),
        .wishbone(slaves[9].slave)
    );

    proloy_wb_rst #(
        .ADDRESS(RST_CTRL_START),
        .SIZE(RST_CTRL_SIZE)
    ) rst_ctrl (
        .clk(clk),
        .rst(rst),
        .wishbone(slaves[10].slave),
        .rst_out(rst_out)
    );

endmodule

