/*
 File: aetherlink.sv
 Multi-master Wishbone interconnect
 Organization: Alpha Science Lab
 October 2026
 Author: Md. Mosharrof, Jubayer Fahad
*/

module aetherlink #(
    parameter int NUM_MASTERS = 4,
    parameter int NUM_SLAVES = 16,
    parameter bit [32*NUM_SLAVES-1:0] SLAVE_ADDRESS,
    parameter bit [32*NUM_SLAVES-1:0] SLAVE_SIZE
) (
    input logic clk,
    input logic rst,

    wishbone_interface.slave masters [NUM_MASTERS],
    wishbone_interface.master slaves [NUM_SLAVES]
);

    localparam int MASTER_IDX_W = (NUM_MASTERS > 1) ? $clog2(NUM_MASTERS) : 1;

    logic [NUM_MASTERS-1:0] req;
    logic [NUM_MASTERS-1:0] grant_vec;
    logic [NUM_MASTERS-1:0] master_req, master_cyc, master_stb, master_we;
    logic [NUM_MASTERS-1:0][31:0] master_adr, master_dat_mosi;
    logic [NUM_MASTERS-1:0][3:0] master_sel;
    logic [MASTER_IDX_W-1:0] grant_idx_d, grant_idx_q, last_grant_q;
    logic granted_d, granted_q;

    logic [NUM_SLAVES-1:0] select;
    logic invalid_address;
    logic granted_cyc, granted_stb, granted_we;
    logic [31:0] granted_adr, granted_dat_mosi;
    logic [3:0] granted_sel;

    logic [NUM_SLAVES-1:0] masked_ack, masked_err;
    logic [NUM_SLAVES-1:0][31:0] masked_dat_miso;
    logic [31:0] slave_dat_miso;
    logic slave_ack, slave_err;

    logic done;
    logic [7:0] timeout_count;
    logic timeout;

    integer m;
    integer s;

    for (genvar i = 0; i < NUM_MASTERS; i++) begin : master_signals
        assign master_req[i] = masters[i].cyc && masters[i].stb;
        assign master_cyc[i] = masters[i].cyc;
        assign master_stb[i] = masters[i].stb;
        assign master_we[i] = masters[i].we;
        assign master_adr[i] = masters[i].adr;
        assign master_sel[i] = masters[i].sel;
        assign master_dat_mosi[i] = masters[i].dat_mosi;
    end

    always_comb begin
        req = master_req;
    end

    // Round-robin arbiter: choose next requester after last_grant_q
    always_comb begin
        grant_idx_d = grant_idx_q;
        granted_d = granted_q;

        granted_cyc = master_cyc[grant_idx_q];
        granted_stb = master_stb[grant_idx_q];
        granted_we  = master_we[grant_idx_q];
        granted_adr = master_adr[grant_idx_q];
        granted_sel = master_sel[grant_idx_q];
        granted_dat_mosi = master_dat_mosi[grant_idx_q];

        if (!granted_q) begin
            granted_d = 1'b0;
            for (m = 1; m <= NUM_MASTERS; m++) begin
                int cand;
                cand = (last_grant_q + m) % NUM_MASTERS;
                if (!granted_d && req[cand]) begin
                    grant_idx_d = cand[MASTER_IDX_W-1:0];
                    granted_d   = 1'b1;
                end
            end
        end
        else if (done || !granted_cyc) begin
            granted_d = 1'b0;
        end
    end

    always_ff @(posedge clk) begin
        if (rst) begin
            grant_idx_q  <= '0;
            last_grant_q <= '0;
            granted_q    <= 1'b0;
        end
        else begin
            grant_idx_q <= grant_idx_d;
            granted_q   <= granted_d;
            if (granted_q && done) begin
                last_grant_q <= grant_idx_q;
            end
        end
    end

    always_comb begin
        grant_vec = '0;
        if (granted_q) begin
            grant_vec[grant_idx_q] = 1'b1;
        end
    end

    // Decode slaves for the currently granted master
    for (genvar slave = 0; slave < NUM_SLAVES; slave++) begin
        assign select[NUM_SLAVES - slave - 1] =
            granted_q &&
            granted_cyc &&
            (granted_adr >= SLAVE_ADDRESS[31 + slave * 32 : slave * 32]) &&
            (granted_adr < (SLAVE_ADDRESS[31 + slave * 32 : slave * 32] + SLAVE_SIZE[31 + slave * 32 : slave * 32]));
    end

    assign invalid_address = granted_q && granted_cyc && granted_stb && (select == '0);

    for (genvar slave = 0; slave < NUM_SLAVES; slave++) begin
        assign masked_dat_miso[slave] = select[slave] ? slaves[slave].dat_miso : '0;
        assign masked_ack[slave]      = select[slave] && slaves[slave].ack;
        assign masked_err[slave]      = select[slave] && slaves[slave].err;
    end

    always_comb begin
        slave_dat_miso = '0;
        for (s = 0; s < NUM_SLAVES; s++) begin
            slave_dat_miso |= masked_dat_miso[s];
        end
    end

    assign slave_ack = |masked_ack;
    assign slave_err = |masked_err;

    always_ff @(posedge clk) begin
        if (rst) begin
            timeout_count <= '0;
        end
        else if (done || !granted_q) begin
            timeout_count <= '0;
        end
        else if (granted_cyc && granted_stb && (timeout_count < 8'hff)) begin
            timeout_count <= timeout_count + 8'd1;
        end
        else begin
            timeout_count <= '0;
        end
    end

    assign timeout = (timeout_count == 8'hff);
    assign done = slave_ack || slave_err || invalid_address || timeout;

    // Return path to masters: only granted master receives responses
    for (genvar master = 0; master < NUM_MASTERS; master++) begin
        assign masters[master].dat_miso = (granted_q && (grant_idx_q == master[MASTER_IDX_W-1:0])) ? slave_dat_miso : '0;
        assign masters[master].ack      = (granted_q && (grant_idx_q == master[MASTER_IDX_W-1:0])) ? slave_ack : 1'b0;
        assign masters[master].err      = (granted_q && (grant_idx_q == master[MASTER_IDX_W-1:0])) ? (slave_err || invalid_address || timeout) : 1'b0;
    end

    // Forward granted master request to selected slave
    for (genvar slave = 0; slave < NUM_SLAVES; slave++) begin
        assign slaves[slave].cyc      = granted_q && granted_cyc;
        assign slaves[slave].stb      = granted_q && granted_stb && select[slave];
        assign slaves[slave].adr      = granted_adr;
        assign slaves[slave].sel      = granted_sel;
        assign slaves[slave].we       = granted_we;
        assign slaves[slave].dat_mosi = granted_dat_mosi;
    end

endmodule
