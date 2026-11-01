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
    // System clock and reset
    input  logic clk,
    input  logic rst_async,

    // UART alternate channel
    input  logic uart_rx_async,
    output logic uart_tx,
    
    // GPIO facing outside world
    inout  logic [15:0] gpioa,
    inout  logic [15:0] gpiob,
    inout  logic [15:0] gpioc,

    // Ext. SPI flash
    output logic spi0_sclk,
    output logic spi0_mosi,
    input  logic spi0_miso,
    output logic spi0_cs_n
);
    import constants::*;

    // Internal wirings
    logic uart_tx_gpio, gpio_uart_rx, /*GPIO x UART*/
        i2c_sda_o_gpio, i2c_sda_oe_gpio, gpio_i2c_sda_i, i2c_scl_o_gpio, 
        i2c_scl_oe_gpio, gpio_i2c_scl_i, /*GPIO x I2C*/
        spi1_mosi_gpio, spi1_sclk_gpio, gpio_spi1_miso_muxed; /* SPI1 x GPIO */
    
    logic [1:0] spi1_cs_n_gpio, gpio_spi1_miso; /*SPI1 all cs x GPIO*/

    assign gpio_spi1_miso_muxed = (spi1_cs_n_gpio[0] == 1'b0) ? gpio_spi1_miso[0] : 
        (spi1_cs_n_gpio[1] == 1'b0) ? gpio_spi1_miso[1] : 1'b0;
        
    logic [15:0] rst_reg;
    logic rst = 1;
    
    always_ff @(posedge clk) begin
        rst <= rst_async;
    end

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
            MEMORY_START, ROM_START, UART_START, TIMER_START, 
            I2C_START, SPI0_START, SPI1_START, GPIO_START, 
            TEST_START, RST_CTRL_START, SPINLOCK_START, BIFROST_START
        }),
        .SLAVE_SIZE
        ({
            MEMORY_SIZE, MEMORY_SIZE, MEMORY_SIZE, MEMORY_SIZE, 
            MEMORY_SIZE * 2, ROM_SIZE, UART_SIZE, TIMER_SIZE, 
            I2C_SIZE, SPI_SIZE, SPI_SIZE, GPIO_SIZE, 
            TEST_SIZE, RST_CTRL_SIZE, SPINLOCK_SIZE, BIFROST_SIZE
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
        .rst(rst_reg[1]),
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
        .rst(rst_reg[2]),
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
        .rst(rst_reg[3]),
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

    // Boot ROM
    boot_rom #(
        .ADDRESS(ROM_START),
        .SIZE(ROM_SIZE),
        .INIT_FILE("boot_rom.mem")
    ) boot_rom (
        .clk(~clk),
        .rst(rst),
        .wb(slaves[5].slave)
    );

    // Wishbone peripherals

    wishbone_uart #(
        .ADDRESS(UART_START),
        .SIZE(UART_SIZE),
        .BAUD_RATE(UART_BAUD_RATE),
        .CLK_FREQUENCY_MHZ(CLK_FREQUENCY_MHZ)
    ) uart_periph (
        .clk(clk),
        .rst(rst),
        .rx_serial_in(gpio_uart_rx),
        .tx_serial_out(uart_tx_gpio),
        .interrupt(uart_interrupt),
        .wishbone(slaves[6].slave)
    );

    wishbone_timer #(
        .ADDRESS(TIMER_START),
        .SIZE(TIMER_SIZE),
        .CLK_FREQUENCY_MHZ(CLK_FREQUENCY_MHZ)
    ) timer_periph (
        .clk(clk),
        .rst(rst),
        .interrupt(timer_interrupt),
        .wishbone(slaves[7].slave)
    );

    dotara_wb_i2c #(
        .START_ADDRESS(I2C_START),
        .SIZE(I2C_SIZE),
        .FIFO_DEPTH(16),
        .DEFAULT_PRESCALER(16'd45)
    ) wb_i2c (
        .clk(clk),
        .rst(rst),
        .wb(slaves[8].slave),
        .intr(i2c_intr),
        .scl_pad_i(gpio_i2c_scl_i),
        .scl_pad_o(i2c_scl_o_gpio),
        .scl_pad_oe(i2c_scl_oe_gpio),
        .sda_pad_i(gpio_i2c_sda_i),
        .sda_pad_o(i2c_sda_o_gpio),
        .sda_pad_oe(i2c_sda_oe_gpio)
    );

    karnaphuli_wb_spi #( /*for external spi flash*/
        .START_ADDRESS(SPI0_START),
        .SIZE(SPI_SIZE),
        .NUM_SLAVES(1),
        .FIFO_DEPTH(4096),
        .DEFAULT_PRESCALER(16'd2)
    ) wb_spi0 (
        .clk(clk),
        .rst(rst),
        .wb(slaves[9].slave),
        .intr(spi0_intr),
        .spi_sclk(spi0_sclk),
        .spi_mosi(spi0_mosi),
        .spi_miso(spi0_miso),
        .spi_cs_n(spi0_cs_n)
    );

    karnaphuli_wb_spi #(
        .START_ADDRESS(SPI1_START),
        .SIZE(SPI_SIZE),
        .NUM_SLAVES(2),
        .FIFO_DEPTH(64),
        .DEFAULT_PRESCALER(16'd7)
    ) wb_spi1 (
        .clk(clk),
        .rst(rst),
        .wb(slaves[10].slave),
        .intr(spi1_intr),
        .spi_sclk(spi1_sclk_gpio),
        .spi_mosi(spi1_mosi_gpio),
        .spi_miso(gpio_spi1_miso_muxed),
        .spi_cs_n(spi1_cs_n_gpio)
    );
    
    brahmaputra_wb_gpio #(
        .START_ADDRESS(GPIO_START),
        .SIZE(GPIO_SIZE)
    ) wb_gpio (
        .clk(clk),
        .rst(rst),
        .wb(slaves[11].slave),
        // gpio facing outside world
        .gpioa(gpioa),
        .gpiob(gpiob),
        .gpioc(gpioc),
        // uart channel
        .uart_tx(uart_tx_gpio),
        .uart_rx(gpio_uart_rx),
        // i2c channel
        .i2c_sda_o(i2c_sda_o_gpio),
        .i2c_sda_oe(i2c_sda_oe_gpio),
        .i2c_sda_i(gpio_i2c_sda_i),
        .i2c_scl_o(i2c_scl_o_gpio),
        .i2c_scl_oe(i2c_scl_oe_gpio),
        .i2c_scl_i(gpio_i2c_scl_i),
        // spi1 channel0
        .spi0_mosi(spi1_mosi_gpio),
        .spi0_sck(spi1_sclk_gpio),
        .spi0_cs_n(spi1_cs_n_gpio[0]),
        .spi0_miso(gpio_spi1_miso[0]),
        // spi1 channel1
        .spi1_mosi(spi1_mosi_gpio),
        .spi1_sck(spi1_sclk_gpio),
        .spi1_cs_n(spi1_cs_n_gpio[1]),
        .spi1_miso(gpio_spi1_miso[1])
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
        .rst_out(rst_reg)
    );

    shikol_wb_spinlock #(
        .ADDRESS(SPINLOCK_START),
        .SIZE(SPINLOCK_SIZE)
    ) spinlock_periph (
        .clk(clk),
        .rst(rst),
        .wb(slaves[14].slave)
    );

endmodule

