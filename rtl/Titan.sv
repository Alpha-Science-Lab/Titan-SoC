/*
 File: Titan.sv
 Multicore Hadi-V SoC AlphaTitan
 Organization: Alpha Science Lab
 October 2026
 Author: Md. Mosharrof, Jubayer Fahad
*/

module Titan #(
    parameter real CLK_FREQUENCY_MHZ,
    parameter int  UART_BAUD_RATE
) (
    // Main system clk
    input logic clk,
    
    // LEDs
    output logic [15:0] leds,

    // Buttons
    input  logic [4:0] buttons_async,

    // UART
    input  logic uart_rx_async,
    output logic uart_tx,

    input  logic i2c_scl_i,
    output logic i2c_scl_o,
    output logic i2c_scl_oe,
    input  logic i2c_sda_i,
    output logic i2c_sda_o,
    output logic i2c_sda_oe,

    output logic spi0_sclk,
    output logic spi0_mosi,
    input  logic spi0_miso,
    output logic spi0_cs_n,

    output logic spi1_sclk,
    output logic spi1_mosi,
    input  logic spi1_miso,
    output logic [7:0] spi1_cs_n
);
    import constants::*;

    logic [4:0] buttons;
    logic uart_rx;
    logic [15:0] leds_out;

    logic [15:0] rst_out;
    logic rst = 1;

    assign leds = leds_out;
    
    always_ff @(posedge clk) begin
        rst <= buttons[0];
    end

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

    logic uart_interrupt, dma_interrupt, i2c_intr, spi0_intr, spi1_intr;
    logic [3:0] test_interrupt;
    logic [3:0] timer_interrupt;


    // Wishbone bus interfaces for CPU cores
    // Bus masters 0-3 are for CPU memory ports
    // Bus master 4 for DMA
    // Bus masters 8-11 for CPU fetch ports
    wishbone_interface bus_masters[12]();

    // Wishbone slaves (memory mapped peripherals)
    wishbone_interface slaves[16]();
    wishbone_interface dummy_sram_port();

    // System bus connecting cores to MMIO peripherals
    /* aetherlink */
    aetherlink #(
        .NUM_MASTERS(8),
        .NUM_SLAVES(16),
        .SLAVE_ADDRESS
        ({
            TCIM0_START, TCIM1_START, TCIM2_START, TCIM3_START,
            MEMORY_START, BUTTONS_START, LEDS_START, UART_START,
            TIMER_START, I2C_START, SPI0_START, SPI1_START, TEST_START,
            RST_CTRL_START, SPINLOCK_START, BIFROST_START
        }),
        .SLAVE_SIZE
        ({
            MEMORY_SIZE, MEMORY_SIZE, MEMORY_SIZE, MEMORY_SIZE,
            MEMORY_SIZE * 2, BUTTONS_SIZE, LEDS_SIZE, UART_SIZE,
            TIMER_SIZE, I2C_SIZE, SPI_SIZE, SPI_SIZE, TEST_SIZE,
            RST_CTRL_SIZE, SPINLOCK_SIZE, BIFROST_SIZE
        })
        /* Multimaster wishbone interconnect */
    ) aetherlink_interconnect (
        .clk(clk),
        .rst(rst),
        .masters(bus_masters[0:7]), 
        .slaves(slaves)
    );

    // CPU cores (cores 0-3)
    Hadi_V #(
        .RESET_VECTOR(CPU0_RESET_VECTOR),
        .HART_ID(32'h0)
    ) core0 (
        .clk(clk),
        .rst(rst),
        .memory_fetch_port(bus_masters[8].master),
        .memory_mem_port(bus_masters[0].master),
        .external_interrupt_in(uart_interrupt || spi0_intr || dma_interrupt || test_interrupt[0]),
        .timer_interrupt_in(timer_interrupt[0])
    );

    Hadi_V #(
        .RESET_VECTOR(CPU1_RESET_VECTOR),
        .HART_ID(32'h1)
    ) core1 (
        .clk(clk),
        .rst(rst_out[1]),
        .memory_fetch_port(bus_masters[9].master),
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
        .memory_fetch_port(bus_masters[10].master),
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
        .memory_fetch_port(bus_masters[11].master),
        .memory_mem_port(bus_masters[3].master),
        .external_interrupt_in(uart_interrupt || i2c_intr || spi1_intr || test_interrupt[3]), 
        .timer_interrupt_in(timer_interrupt[3])
    );

    bifrost_wb_dma #(
        .START_ADDRESS(BIFROST_START),
        .SIZE(BIFROST_SIZE)
    ) dma_core (
        .clk(clk),
        .rst(rst),
        .intr(dma_interrupt),
        .wb(slaves[15].slave),
        .dma(bus_masters[4].master)
    );

    // (TCIM 0-3)
    wishbone_ram #(
        .ADDRESS(TCIM0_START),
        .SIZE(MEMORY_SIZE),
        .INIT_FILE("init.mem")
    ) tcim0 (
        .clk(~clk),
        .rst(rst),
        .port_a(bus_masters[8].master),
        .port_b(slaves[0].slave)
    );

    wishbone_ram #(
        .ADDRESS(TCIM1_START),
        .SIZE(MEMORY_SIZE)
    ) tcim1 (
        .clk(~clk),
        .rst(rst),
        .port_a(bus_masters[9].master),
        .port_b(slaves[1].slave)
    );

    wishbone_ram #(
        .ADDRESS(TCIM2_START),
        .SIZE(MEMORY_SIZE)
    ) tcim2 (
        .clk(~clk),
        .rst(rst),
        .port_a(bus_masters[10].master),
        .port_b(slaves[2].slave)
    );

    wishbone_ram #(
        .ADDRESS(TCIM3_START),
        .SIZE(MEMORY_SIZE)
    ) tcim3 (
        .clk(~clk),
        .rst(rst),
        .port_a(bus_masters[11].master),
        .port_b(slaves[3].slave)
    );

    // Shared SRAM
    wishbone_ram #(
        .ADDRESS(MEMORY_START),
        .SIZE(MEMORY_SIZE)
    ) sram (
        .clk(~clk),
        .rst(rst),
        .port_a(slaves[4].slave),
        .port_b(dummy_sram_port.slave) /* unused port */ 
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
        .leds(leds_out),
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

    dotara_wb_i2c #(
        .START_ADDRESS(I2C_START),
        .SIZE(I2C_SIZE),
        .FIFO_DEPTH(16),
        .DEFAULT_PRESCALER(16'd45)
    ) wb_i2c (
        .clk(clk),
        .rst(rst),
        .wb(slaves[9].slave),
        .intr(i2c_intr),
        .scl_pad_i(i2c_scl_i),
        .scl_pad_o(i2c_scl_o),
        .scl_padoen_o(i2c_scl_oe),
        .sda_pad_i(i2c_sda_i),
        .sda_pad_o(i2c_sda_o),
        .sda_padoen_o(i2c_sda_oe)
    );

    karnaphuli_wb_spi #( /*for external spi flash*/
        .START_ADDRESS(SPI0_START),
        .SIZE(SPI_SIZE),
        .NUM_SLAVES(1),
        .FIFO_DEPTH(256),
        .DEFAULT_PRESCALER(16'd2)
    ) wb_spi0 (
        .clk(clk),
        .rst(rst),
        .wb(slaves[10].slave),
        .intr(spi0_intr),
        .spi_sclk(spi0_sclk),
        .spi_mosi(spi0_mosi),
        .spi_miso(spi0_miso),
        .spi_cs_n(spi0_cs_n)
    );

    karnaphuli_wb_spi #(
        .START_ADDRESS(SPI1_START),
        .SIZE(SPI_SIZE),
        .NUM_SLAVES(8),
        .FIFO_DEPTH(64),
        .DEFAULT_PRESCALER(16'd7)
    ) wb_spi1 (
        .clk(clk),
        .rst(rst),
        .wb(slaves[11].slave),
        .intr(spi1_intr),
        .spi_sclk(spi1_sclk),
        .spi_mosi(spi1_mosi),
        .spi_miso(spi1_miso),
        .spi_cs_n(spi1_cs_n)
    );

    wishbone_test #(
        .ADDRESS(TEST_START),
        .SIZE(TEST_SIZE)
    ) test_periph (
        .clk(clk),
        .rst(rst),
        .interrupt(test_interrupt),
        .wishbone(slaves[12].slave)
    );

    proloy_wb_rst #(
        .ADDRESS(RST_CTRL_START),
        .SIZE(RST_CTRL_SIZE)
    ) rst_ctrl (
        .clk(clk),
        .rst(rst),
        .wb(slaves[13].slave),
        .rst_out(rst_out)
    );

    shikol_wb_spinlock #(
        .ADDRESS(SPINLOCK_START),
        .SIZE(SPINLOCK_SIZE)
    ) spinlock_periph (
        .clk(clk),
        .rst(rst),
        .wb(slaves[14].slave)
    );

    // ~Wishbone peripherals
endmodule

