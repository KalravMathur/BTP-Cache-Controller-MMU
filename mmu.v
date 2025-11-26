`include "mmu_params.v"
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

module system_top (
    input wire clk,
    input wire rst_n,

    
    // CPU Interface
    input wire [31:0] cpu_va,
    input wire [31:0] cpu_data_out, 
    input wire        cpu_read_req,
    input wire        cpu_write_req,

    // Responses TO CPU
    output wire [31:0] cpu_data_in,  // Data TO CPU read from memory
    output wire        cpu_stall,    // Stall signal (1=stall, 0=ready)
    output wire        cache_hit,    // status from cache

    // TLB Refill Interface (for Testbench/PTW)
    // Signal that a translation is missing
    output reg                  tlb_miss_detected,

    // "Backdoor" inputs to fill the TLB
    input wire                  tb_refill_en,
    input wire [`VPN_WIDTH-1:0] tb_refill_vpn,
    input wire [`PFN_WIDTH-1:0] tb_refill_pfn,

    // Main Memory & Cache RAM Interfaces (Passed through from Cache Controller)
    // Interface to Cache SRAM (Data Store)
    output wire [5:0]   cache_mem_index,
    output wire [511:0] cache_mem_data_in,
    output wire         cache_mem_write_en,
    input wire  [511:0] cache_mem_data_out,

    // Interface to Main Memory (DRAM)
    output wire [31:0]  main_mem_addr,
    output wire [31:0]  main_mem_data_out,
    output wire         main_mem_read_req,
    output wire         main_mem_write_req,
    // FIX: Changed to 32 bits to match Cache Controller fix
    input wire  [31:0]  main_mem_data_in,
    input wire          main_mem_ready
);

    // Address components
    wire [`VPN_WIDTH-1:0]    cpu_vpn;
    wire [`OFFSET_BITS-1:0]  page_offset;

    // TLB signals
    wire                     tlb_hit;
    wire [`PFN_WIDTH-1:0]    tlb_pfn;

    // Physical Address constructed from TLB result
    reg [31:0]               phy_addr_comb;

    // Control signals for the cache controller
    reg                      cache_read_req;
    reg                      cache_write_req;

    // Stall signal from the cache controller (0=ready, 1=stall)
    wire                     cache_ready_stall;

    // Address Splitting
    // Extract VPN and offset from the CPU's Virtual Address
    assign cpu_vpn     = cpu_va[31:`OFFSET_BITS];
    assign page_offset = cpu_va[`OFFSET_BITS-1:0];

    // Instantiate TLB
    tlb_simple u_tlb (
        .clk        (clk),
        .rst_n      (rst_n),
        // Lookup Port
        .lookup_vpn (cpu_vpn),
        .lookup_hit (tlb_hit),
        .lookup_pfn (tlb_pfn),
        // Refill Port
        .refill_en  (tb_refill_en),
        .refill_vpn (tb_refill_vpn),
        .refill_pfn (tb_refill_pfn)
    );

    // Translation & Control Logic (Combinational)
    always @(*) begin
        // Defaults
        tlb_miss_detected = 1'b0;
        cache_read_req    = 1'b0;
        cache_write_req   = 1'b0;
        phy_addr_comb     = 32'h0;

        // Is the CPU making a request?
        if (cpu_read_req || cpu_write_req) begin
            if (tlb_hit) begin
                // --- TLB Hit ---
                // 1. Construct the Physical Address
                phy_addr_comb = {tlb_pfn, page_offset};

                // 2. Forward the request to the cache controller
                cache_read_req  = cpu_read_req;
                cache_write_req = cpu_write_req;
                // tlb_miss_detected remains 0
            end else begin
                // --- TLB Miss ---
                // 1. Signal the miss
                tlb_miss_detected = 1'b1;

                // 2. Do NOT forward requests to the cache
                cache_read_req  = 1'b0;
                cache_write_req = 1'b0;
                // The resulting stall is handled by the assign cpu_stall below
            end
        end
    end

    // The CPU must stall if either:
    // 1. The cache controller is busy (cache_ready_stall is 1).
    // 2. There is a TLB miss, so we can't even access the cache yet.
    assign cpu_stall = cache_ready_stall || tlb_miss_detected;


    // Instantiate Cache Controller
    cache_controller u_cache_controller (
        .clk                (clk),
        .rst_n              (rst_n),
        // CPU/MMU side interface
        .phy_addr           (phy_addr_comb),   // Translated PA from TLB
        .data_from_cpu      (cpu_data_out),    // Data to be written
        .read_mem           (cache_read_req),  // Gated read signal
        .write_mem          (cache_write_req), // Gated write signal
        .data_to_cpu        (cpu_data_in),     // Data read from cache
        .hit_miss           (cache_hit),       // Cache hit/miss status
        .ready_stall        (cache_ready_stall), // Cache's stall signal

        // Cache RAM interface (pass-through)
        .cache_mem_index    (cache_mem_index),
        .cache_mem_data_in  (cache_mem_data_in),
        .cache_mem_write_en (cache_mem_write_en),
        .cache_mem_data_out (cache_mem_data_out),

        // Main Memory interface (pass-through)
        .main_mem_addr      (main_mem_addr),
        .main_mem_data_out  (main_mem_data_out),
        .main_mem_read_req  (main_mem_read_req),
        .main_mem_write_req (main_mem_write_req),
        .main_mem_data_in   (main_mem_data_in),
        .main_mem_ready     (main_mem_ready)
    );

endmodule
