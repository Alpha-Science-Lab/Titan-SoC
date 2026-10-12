/* Copyright (c) 2026 Alpha Science Lab
 * SPDX-License-Identifier: MIT
 * ---------------------------------------------------------------------
 * File: aetherlink.sv
 * Author: Md. Mosharrof, Jubayer Fahad
 *
 * Multi-master Wishbone interconnect
 * - Arbitrates between NUM_MASTERS bus initiators (round-robin)
 * - Routes one granted master to NUM_SLAVES targets
 * - Preserves existing address/size decode style
 */

module aetherlink #(
    parameter int NUM_MASTERS = 4,
    parameter int NUM_SLAVES,
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
    logic [MASTER_IDX_W-1:0] grant_idx_d, grant_idx_q, last_grant_q;
    logic granted_d, granted_q;

    logic [NUM_SLAVES-1:0] select;
    logic invalid_address;

    logic [NUM_SLAVES-1:0] masked_ack, masked_err;
    logic [NUM_SLAVES-1:0][31:0] masked_dat_miso;
    logic [31:0] slave_dat_miso;
    logic slave_ack, slave_err;

    logic done;
    logic [7:0] timeout_count;
    logic timeout;

    integer m;
    integer s;

    always_comb begin
        for (m = 0; m < NUM_MASTERS; m++) begin
            req[m] = masters[m].cyc && masters[m].stb;
        end
    end

    // Round-robin arbiter: choose next requester after last_grant_q
    always_comb begin
        grant_idx_d = grant_idx_q;
        granted_d = granted_q;

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
        else if (done || !masters[grant_idx_q].cyc) begin
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
        assign select[NUM_SLAVES - slave - 1] = &{
            granted_q,
            masters[grant_idx_q].cyc,
            masters[grant_idx_q].adr >= SLAVE_ADDRESS[31 + slave * 32 : slave * 32],
            masters[grant_idx_q].adr < SLAVE_ADDRESS[31 + slave * 32 : slave * 32] + SLAVE_SIZE[31 + slave * 32 : slave * 32]
        };
    end

    assign invalid_address = granted_q && masters[grant_idx_q].cyc && masters[grant_idx_q].stb && (select == '0);

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
        else if (masters[grant_idx_q].cyc && masters[grant_idx_q].stb && (timeout_count < 8'hff)) begin
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
        assign slaves[slave].cyc      = granted_q && masters[grant_idx_q].cyc;
        assign slaves[slave].stb      = granted_q && masters[grant_idx_q].stb && select[slave];
        assign slaves[slave].adr      = masters[grant_idx_q].adr;
        assign slaves[slave].sel      = masters[grant_idx_q].sel;
        assign slaves[slave].we       = masters[grant_idx_q].we;
        assign slaves[slave].dat_mosi = masters[grant_idx_q].dat_mosi;
    end

endmodule
