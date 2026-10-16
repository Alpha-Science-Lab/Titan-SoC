
module sim_top_alphatitan ();

    import clk_params::*;

    integer error_count = 0;

    logic clk;
    logic [15:0] leds;
    logic [4:0] buttons_async = 0;
    logic uart_rx_async = 1;
    logic uart_tx;
    
    Titan #(
        .CLK_FREQUENCY_MHZ(SYS_CLK_FREQUENCY_MHZ),
        .UART_BAUD_RATE(int'((SYS_CLK_FREQUENCY_MHZ*1_000_000) / 15))
    ) alphatitan_soc (
        .clk(clk),
        .leds(leds),
        .buttons_async(buttons_async),
        .uart_rx_async(uart_rx_async),
        .uart_tx(uart_tx)
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
    end

    initial begin
        $dumpfile("sim.fst");
        $dumpvars;

        // Run for 10000000 cycles max
        repeat (10000000) @(negedge clk);

        // Stop simulation
        $display("\033[0;33m"); // color_orange
        $display("Simulation timeout!");
        $display("\033[0m"); // color off
        $finish();
    end

    // Respond to test interface
    always @(posedge clk) begin
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
