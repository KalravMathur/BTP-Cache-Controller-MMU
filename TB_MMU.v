////////////////////////////////////////////////////////////////////////////////
// Copyright (c) 2025, Shiv Nadar University, Delhi NCR, India. All Rights
// Reserved. Permission to use, copy, modify and distribute this software for
// educational, research, and not-for-profit purposes, without fee and without a
// signed license agreement, is hereby granted, provided that this paragraph and
// the following two paragraphs appear in all copies, modifications, and
// distributions.
//
// IN NO EVENT SHALL SHIV NADAR UNIVERSITY BE LIABLE TO ANY PARTY FOR DIRECT,
// INDIRECT, SPECIAL, INCIDENTAL, OR CONSEQUENTIAL DAMAGES, INCLUDING LOST
// PROFITS, ARISING OUT OF THE USE OF THIS SOFTWARE.
//
// SHIV NADAR UNIVERSITY SPECIFICALLY DISCLAIMS ANY WARRANTIES, INCLUDING, BUT
// NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A
// PARTICULAR PURPOSE. THE SOFTWARE PROVIDED HEREUNDER IS PROVIDED "AS IS". SHIV
// NADAR UNIVERSITY HAS NO OBLIGATION TO PROVIDE MAINTENANCE, SUPPORT, UPDATES,
// ENHANCEMENTS, OR MODIFICATIONS.
//
// Revision History:
// Date          By                     Change Notes
// 14 Nov 2025   Kalrav Mathur          Original
//
////////////////////////////////////////////////////////////////////////////////

`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 06.11.2025 13:27:03
// Design Name: 
// Module Name: TB_MMU
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


`include "MMU_declarations.v"

module simple_mmu_tb;

    // Clock / reset
    reg                    clk;
    reg                    rst_n;

    // DUT I/O
    reg                    mmu_req_valid;
    reg  [`ADDR_WIDTH-1:0] mmu_req_va;
    wire                   mmu_req_ready;

    wire                   mmu_resp_valid;
    wire [`ADDR_WIDTH-1:0] mmu_resp_pa;
    wire [            1:0] mmu_resp_status;
    reg                    mmu_resp_ready;

    // Instantiate DUT
    simple_mmu dut (
        .clk            (clk),
        .rst_n          (rst_n),
        .mmu_req_valid  (mmu_req_valid),
        .mmu_req_va     (mmu_req_va),
        .mmu_req_ready  (mmu_req_ready),
        .mmu_resp_valid (mmu_resp_valid),
        .mmu_resp_pa    (mmu_resp_pa),
        .mmu_resp_status(mmu_resp_status),
        .mmu_resp_ready (mmu_resp_ready)
    );

    // Clock gen: 10ns period
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    // Simple task to issue one MMU request and consume one response
    task automatic issue_req(input [`ADDR_WIDTH-1:0] va);
        begin
            // Wait until ready
            @(posedge clk);
            while (!mmu_req_ready) @(posedge clk);

            mmu_req_va    <= va;
            mmu_req_valid <= 1'b1;

            // Fire one cycle when ready
            @(posedge clk);
            if (mmu_req_ready && mmu_req_valid) begin
                mmu_req_valid <= 1'b0;
            end

            // Wait for response valid
            while (!mmu_resp_valid) @(posedge clk);

            // Sample + print
            $display("[%0t] VA=0x%08h  ->  PA=0x%08h  status=%0d", $time, va, mmu_resp_pa,
                     mmu_resp_status);

            // Accept response
            mmu_resp_ready <= 1'b1;
            @(posedge clk);
            mmu_resp_ready <= 1'b0;
        end
    endtask

    // Helpers to construct VA
    function automatic [`ADDR_WIDTH-1:0] make_va(input [`VPN_WIDTH-1:0] vpn,
                                                 input [`PAGE_OFFSET_WIDTH-1:0] off);
        make_va = {vpn, off};
    endfunction

    // Stimulus
    initial begin
        // Init
        mmu_req_valid  = 0;
        mmu_req_va     = 0;
        mmu_resp_ready = 0;

        // Reset
        rst_n          = 0;
        repeat (5) @(posedge clk);
        rst_n = 1;
        repeat (2) @(posedge clk);

        // Access a few addresses:
        // VPN 0..3 map to PFN 10..13 in mock PTW; others fault.

        // 1) First access to VPN=0 -> TLB miss, PTW resolve -> MISS status
        issue_req(make_va(20'd0, 12'h123));

        // 2) Second access to same VPN=0 -> TLB HIT -> HIT status
        issue_req(make_va(20'd0, 12'hABC));

        // 3) Access to VPN=1 -> MISS then fill
        issue_req(make_va(20'd1, 12'h010));

        // 4) Access to VPN=2 -> MISS then fill
        issue_req(make_va(20'd2, 12'h020));

        // 5) Access to VPN=3 -> MISS then fill (TLB now full)
        issue_req(make_va(20'd3, 12'h030));

        // 6) Access to VPN=4 -> PAGE FAULT
        issue_req(make_va(20'd4, 12'h040));

        // 7) Re-access VPN=1 to exercise LRU/HIT (depending on which got evicted)
        issue_req(make_va(20'd1, 12'h055));

        // Done
        repeat (10) @(posedge clk);
        $finish;
    end

endmodule

