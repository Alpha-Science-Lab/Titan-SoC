
module top_alphatitan ();

    import clk_params::*;

    localparam int UART_BAUD_RATE = int'((SYS_CLK_FREQUENCY_MHZ*1_000_000) / 15);
    localparam int UART_CLKS_PER_BIT = int'(SYS_CLK_FREQUENCY_MHZ*1_000_000.0/UART_BAUD_RATE);

    integer error_count = 0;

    logic clk;
    logic [15:0] leds;
    logic [4:0] buttons_async = 0;
    logic uart_rx_async = 1;
    logic uart_tx;
    logic [7:0] uart_mon_byte;
    logic uart_mon_done;
    logic uart_mon_error;
    logic [7:0] uart_rx_line_buf [0:255];
    integer uart_rx_line_len = 0;
    logic [15:0] leds_prev = '0;
    
    Titan #(
        .CLK_FREQUENCY_MHZ(SYS_CLK_FREQUENCY_MHZ),
        .UART_BAUD_RATE(UART_BAUD_RATE)
    ) alphatitan_soc (
        .clk(clk),
        .leds(leds),
        .buttons_async(buttons_async),
        .uart_rx_async(uart_rx_async),
        .uart_tx(uart_tx)
    );

    // Reuse existing UART RX logic to decode bytes from DUT TX line
    uart_rx #(
        .CLKS_PER_BIT(UART_CLKS_PER_BIT)
    ) uart_tx_monitor (
        .clk(clk),
        .rst(buttons_async[0]),
        .rx_serial_in(uart_tx),
        .rx_byte_out(uart_mon_byte),
        .rx_done_out(uart_mon_done),
        .rx_error_out(uart_mon_error)
    );

    // System clock
    initial begin
        clk = 1;
        forever begin
            #(int'(SIM_CYCLES_PER_SYS_CLK / 2));
            clk = ~clk;
        end
    end

    initial begin
        buttons_async = 5'b00001; // assert reset

        // hold reset for some cycles
        repeat (32) @(posedge clk);

        buttons_async = 5'b00000; // release reset

        // Repeatedly press and release a random button (button 0 is reset)
        forever begin
            repeat ($urandom_range(900, 1100)) begin
                @(posedge clk);
            end

            buttons_async = 5'b00000;
            buttons_async[$urandom_range(4, 1)] = 1'b1; // press a random non-reset button

            repeat (3) @(posedge clk);
            buttons_async = 5'b00000; // release after 3 cycles
        end
    end

    initial begin
        $dumpfile("sim.fst");
        $dumpvars;

        // Run for 1000000 cycles max
        repeat (1000000) @(negedge clk);

        // Stop simulation
        $display("\033[0;33m"); // color_orange
        $display("Simulation timeout!");
        $display("\033[0m"); // color off
        $finish();
    end

    function automatic void flush_uart_rx_line();
        integer i;

        if (uart_rx_line_len == 0) begin
            return;
        end

        $write("\033[38;5;208m");
        $write("(%6d ps) UART RX: ", $time());
        for (i = 0; i < uart_rx_line_len; i++) begin
            if (uart_rx_line_buf[i] == 8'h09) begin
                $write("\t");
            end else if (uart_rx_line_buf[i] >= 8'h20 && uart_rx_line_buf[i] <= 8'h7E) begin
                $write("%c", uart_rx_line_buf[i]);
            end else begin
                $write(".");
            end
        end
        $display("");
        $write("\033[0m");
        uart_rx_line_len = 0;
    endfunction

    // Respond to test interface
    always @(posedge clk) begin
        if (uart_mon_done) begin
            if (uart_mon_error) begin
                flush_uart_rx_line();
                $display("\033[38;5;208m");
                $display("(%6d ps) UART RX monitor framing error", $time());
                $display("\033[0m");
            end
            else if (uart_mon_byte == 8'h0A || uart_mon_byte == 8'h0D) begin
                flush_uart_rx_line();
            end
            else begin
                if (uart_rx_line_len < 256) begin
                    uart_rx_line_buf[uart_rx_line_len] = uart_mon_byte;
                    uart_rx_line_len = uart_rx_line_len + 1;
                end
            end
        end

        if (leds != leds_prev) begin
            logic [15:0] led_on_mask;
            logic [15:0] led_off_mask;
            integer i;

            led_on_mask = leds & ~leds_prev;
            led_off_mask = ~leds & leds_prev;

            $display("\033[38;5;208m");
            $display("(%6d ps) LED state now: 0x%04h (%016b)", $time(), leds, leds);

            for (i = 0; i < 16; i++) begin
                if (led_on_mask[i]) begin
                    $display("  LED[%0d] ON", i);
                end
                if (led_off_mask[i]) begin
                    $display("  LED[%0d] OFF", i);
                end
            end

            $display("\033[0m");
            leds_prev <= leds;
        end

        if (alphatitan_soc.test_periph.test_stb) begin
            case (alphatitan_soc.test_periph.test_reg)
                0: $display("(%6d ps) Test pass!", $time());
                1: begin
                    $display("(%6d ps) Test fail!", $time());
                    error_count <= error_count + 1;
                end
                2: begin
                    print_test_done();
                    // $fflush();
                    $finish();
                end
            endcase
        end

        if (alphatitan_soc.test_periph.scratchpad_stb) begin
            $display("\033[0;33m"); // color_orange
            $display("(%6d ps) Scratchpad: 0x%08h", 
                $time(), alphatitan_soc.test_periph.scratchpad_reg);
            $display("\033[0m"); // color off

        end

    end


    // print helper functions
    function void print_test_done();
        if (error_count == 0) begin
            $display("\033[0;33m"); // color_orange
            $display("Initial test failed! (# Errors: %1d)", error_count);
        end
        else if (error_count > 1) begin
            $display("\033[0;31m"); // color_red
            $display("Some test(s) failed! (# Errors: %1d)", error_count);
        end
        else begin
            $display("\033[0;32m"); // color green
            $display("All tests passed! (# Errors: %1d = initial test)", error_count);
        end
        
        $display("TEST DONE");
        $display("\033[0m"); // color off
    endfunction

endmodule
