
module boot_rom #(
    parameter bit [31:0] ADDRESS,
    parameter bit [31:0] SIZE,
    parameter string     INIT_FILE = ""
)(
    input logic clk,
    input logic rst,
    
    wishbone_interface.slave wb
);

    (* ram_decomp = "power" *)
    logic [31:0] memory [SIZE];

    initial begin
        if (INIT_FILE != "")
            $readmemh(INIT_FILE, memory);
    end


    always_ff @(posedge clk) begin
        if (rst) begin
            wb.ack      <= 0;
            wb.err      <= 0;
            wb.dat_miso <= 0;
        end
        else begin
            // default output
            wb.ack      <= 0;
            wb.err      <= 0;
            wb.dat_miso <= 0;
            // wishbone access
            if (wb.cyc && wb.stb) begin
                // check address space
                if (wb.adr >= ADDRESS && wb.adr < ADDRESS + SIZE) begin
                    wb.ack <= 1;
                    wb.err <= 0;
                    if (wb.we == 0) begin
                        // read
                        wb.dat_miso <= memory[wb.adr - ADDRESS];
                    end
                end
                else begin
                    wb.ack <= 0;
                    wb.err <= 1;
                end
            end
        end
    end


endmodule

