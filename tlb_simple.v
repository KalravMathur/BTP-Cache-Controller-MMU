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
`include "mmu_params.v"

module tlb_simple (
    input wire clk,
    input wire rst_n,

    
    input wire [`VPN_WIDTH-1:0] lookup_vpn,
    output reg                lookup_hit,
    output reg [`PFN_WIDTH-1:0] lookup_pfn,

    // --- Refill Interface (Sequential) ---
    input wire                refill_en,
    input wire [`VPN_WIDTH-1:0] refill_vpn,
    input wire [`PFN_WIDTH-1:0] refill_pfn
);

    // Internal storage
    reg [`VPN_WIDTH-1:0] tag_mem [0:`TLB_ENTRIES-1];
    reg [`PFN_WIDTH-1:0] data_mem [0:`TLB_ENTRIES-1];
    reg                valid_mem [0:`TLB_ENTRIES-1];

    // Replacement Pointer (Round-Robin/FIFO)
    reg [`TLB_PER_BITS-1:0] replace_ptr;

    integer i;

    // 1. Combinational Lookup Logic (Fully Associative)
  
    always @(*) begin
        lookup_hit = 1'b0;
        lookup_pfn = {`PFN_WIDTH{1'b0}};

        for (i = 0; i < `TLB_ENTRIES; i = i + 1) begin
            if (valid_mem[i] && (tag_mem[i] == lookup_vpn)) begin
                lookup_hit = 1'b1;
                lookup_pfn = data_mem[i];
            end
        end
    end

   
    // 2. Sequential Update Logic (Refill and Pointer Update)
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            replace_ptr <= {`TLB_PER_BITS{1'b0}};
            for (i = 0; i < `TLB_ENTRIES; i = i + 1) begin
                valid_mem[i] <= 1'b0;
                tag_mem[i] <= {`VPN_WIDTH{1'b0}};
                data_mem[i] <= {`PFN_WIDTH{1'b0}};
            end
        end else begin
            if (refill_en) begin
               
                tag_mem[replace_ptr]   <= refill_vpn;
                data_mem[replace_ptr]  <= refill_pfn;
                valid_mem[replace_ptr] <= 1'b1;
                
                replace_ptr <= replace_ptr + 1'b1;
            end
        end
    end

endmodule
