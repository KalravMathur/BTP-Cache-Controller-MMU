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
// Create Date: 30.10.2025 11:20:01
// Design Name: 
// Module Name: mmu
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


`include "mmu_params.v"

module mmu_simple_top (
    input wire clk,
    input wire rst_n,

    // =================================================================
    // CPU Interface (Input request and Stall output)
    // =================================================================
    input wire [`ADDR_WIDTH-1:0] cpu_req_va,
    input wire                  cpu_req_valid,

    // EXPLICIT STALL SIGNAL: Tells CPU pipeline to freeze
    output reg                  cpu_stall,

    // =================================================================
    // Cache Controller Interface (Physical Address Output)
    // =================================================================
    output reg [`ADDR_WIDTH-1:0] cache_pa,     // Physical address for tag comparison
    output reg [1:0]            mmu_status,   // Status for cache controller
    output reg                  mmu_pa_valid, // Indicates cache_pa is valid right now

    // =================================================================
    // Simplified PTW / Testbench Interface
    // =================================================================
    // Signal to outside world (Testbench) that a miss occurred
    output reg                  ptw_miss_detected,

    // "Backdoor" refill interface for the Testbench to act as memory
    input wire                  tb_refill_en,
    input wire [`VPN_BITS-1:0]   tb_refill_vpn,
    input wire [`PFN_BITS-1:0]   tb_refill_pfn
);

    // --- Internal Signals ---
    wire [`VPN_BITS-1:0] current_vpn;
    wire [`OFFSET_BITS-1:0] current_offset;

    // Split address into VPN and Offset
    assign current_vpn = cpu_req_va[`ADDR_WIDTH-1:`OFFSET_BITS];
    assign current_offset = cpu_req_va[`OFFSET_BITS-1:0];

    // TLB Signals
    wire tlb_hit;
    wire [`PFN_BITS-1:0] tlb_hit_pfn;

    // --- Instantiate Simplified TLB ---
    tlb_simple u_tlb (
        .clk            (clk),
        .rst_n          (rst_n),
        // Lookup path (from CPU input)
        .lookup_vpn     (current_vpn),
        .lookup_hit     (tlb_hit),
        .lookup_pfn     (tlb_hit_pfn),
        // Refill path (from Testbench inputs)
        .refill_en      (tb_refill_en),
        .refill_vpn     (tb_refill_vpn),
        .refill_pfn     (tb_refill_pfn)
    );


    // =================================================================
    // Output Logic (Combinational)
    // =================================================================
    always @(*) begin
        // 1. Set Default Outputs
        mmu_pa_valid = 1'b0;
        cache_pa = {`ADDR_WIDTH{1'b0}};
        mmu_status = `STATUS_OK;
        ptw_miss_detected = 1'b0;
        // Default: Do not stall
        cpu_stall = 1'b0;

        // 2. Evaluation Logic
        // Only process if CPU is making a valid request
        if (cpu_req_valid) begin
            if (tlb_hit) begin
                // --- TLB HIT ---
                // Compose PA immediately for the cache controller
                cache_pa = {tlb_hit_pfn, current_offset};
                mmu_status = `STATUS_OK;
                // Tell Cache Controller the PA is valid
                mmu_pa_valid = 1'b1;
                // cpu_stall remains 0 (default)
            end else begin
                // --- TLB MISS ---
                // Signal the outside world that we need a refill
                ptw_miss_detected = 1'b1;

                // IMPORTANT: Explicitly stall the CPU.
                // The CPU pipeline must freeze until this miss is resolved.
                cpu_stall = 1'b1;

                // mmu_pa_valid remains 0, so cache controller knows not to use the PA yet.
            end
        end
    end

endmodule
