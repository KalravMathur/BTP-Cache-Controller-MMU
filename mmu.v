////////////////////////////////////////////////////////////////////////////////
// Copyright (c) 2021, Shiv Nadar University, Delhi NCR, India. All Rights
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
// ------------ ---------------------- ------------------------------------------
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

`include "mmu_defines.v"

module simple_mmu (
    input                               clk,
    input                               rst_n,

    // MMU Request Interface (from CPU)
    input                               mmu_req_valid,
    input  [`ADDR_WIDTH-1:0]            mmu_req_va,
    output                              mmu_req_ready,  // combinational

    // MMU Response Interface (to CPU)
    output reg                          mmu_resp_valid,
    output reg [`ADDR_WIDTH-1:0]        mmu_resp_pa,
    output reg [1:0]                    mmu_resp_status,
    input                               mmu_resp_ready
);

    // --- FSM States ---
    localparam S_IDLE       = 2'b00;
    localparam S_PTW_LOOKUP = 2'b01;
    localparam S_UPDATE_TLB = 2'b10;

    reg [1:0] current_state, next_state;

    // --- Registers for FSM Data ---
    reg [`ADDR_WIDTH-1:0] r_current_va;
    reg [`VPN_WIDTH-1:0]  r_current_vpn;

    // --- Embedded TLB Data Structures ---
    reg [`VPN_WIDTH-1:0]       tlb_vpn   [`NUM_TLB_ENTRIES-1:0];
    reg [`PFN_WIDTH-1:0]       tlb_pfn   [`NUM_TLB_ENTRIES-1:0];
    reg                        tlb_valid [`NUM_TLB_ENTRIES-1:0];
    // Small LRU counters (0=most recent). For 4 entries, 2 bits are enough.
    reg [`TLB_INDEX_WIDTH-1:0] tlb_lru   [`NUM_TLB_ENTRIES-1:0];

    // Loop indices
    integer i;

    // --- TLB Lookup (fully associative) ---
    reg                 tlb_hit;
    reg [`TLB_INDEX_WIDTH-1:0] tlb_hit_idx;
    reg [`PFN_WIDTH-1:0]       tlb_hit_pfn;

    always @(*) begin
        tlb_hit     = 1'b0;
        tlb_hit_idx = {`TLB_INDEX_WIDTH{1'b0}};
        tlb_hit_pfn = {`PFN_WIDTH{1'b0}};

        for (i = 0; i < `NUM_TLB_ENTRIES; i = i + 1) begin
            if (tlb_valid[i] && (tlb_vpn[i] == r_current_vpn) && !tlb_hit) begin
                tlb_hit     = 1'b1;
                tlb_hit_idx = i[`TLB_INDEX_WIDTH-1:0];
                tlb_hit_pfn = tlb_pfn[i];
            end
        end
    end

    // --- LRU Victim Selection ---
    reg [`TLB_INDEX_WIDTH-1:0] lru_victim_idx;
    reg [`TLB_INDEX_WIDTH-1:0] max_lru_counter;

    always @(*) begin
        lru_victim_idx = 0;
        max_lru_counter = tlb_lru[0];
        for (i = 1; i < `NUM_TLB_ENTRIES; i = i + 1) begin
            if (tlb_lru[i] > max_lru_counter) begin
                max_lru_counter = tlb_lru[i];
                lru_victim_idx = i[`TLB_INDEX_WIDTH-1:0];
            end
        end
    end

    // --- Page Table Walker (PTW) Mock ---
    localparam PTW_LOOKUP_LATENCY = 3;
    reg [PTW_LOOKUP_LATENCY-1:0] ptw_timer;
    reg                          ptw_active;
    reg [`PFN_WIDTH-1:0]         ptw_fetched_pfn;
    reg                          ptw_fetched_pte_valid;

    // --- Request ready is combinational: accept when idle and no pending resp ---
    assign mmu_req_ready = (current_state == S_IDLE) && (!mmu_resp_valid);

    // --- Next-state logic (combinational) ---
    always @(*) begin
        next_state = current_state;
        case (current_state)
            S_IDLE: begin
                if (mmu_req_valid && mmu_req_ready) begin
                    if (tlb_hit)
                        next_state = S_IDLE;        // respond immediately in seq block
                    else
                        next_state = S_PTW_LOOKUP;  // start PTW
                end
            end

            S_PTW_LOOKUP: begin
                if (ptw_timer == PTW_LOOKUP_LATENCY-1)
                    next_state = S_UPDATE_TLB;
                else
                    next_state = S_PTW_LOOKUP;
            end

            S_UPDATE_TLB: begin
                next_state = S_IDLE;
            end
        endcase
    end

    // --- Sequential block ---
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            current_state       <= S_IDLE;
            r_current_va        <= {`ADDR_WIDTH{1'b0}};
            r_current_vpn       <= {`VPN_WIDTH{1'b0}};
            mmu_resp_valid      <= 1'b0;
            mmu_resp_pa         <= {`ADDR_WIDTH{1'b0}};
            mmu_resp_status     <= `MMU_STATUS_HIT;

            ptw_timer           <= {PTW_LOOKUP_LATENCY{1'b0}};
            ptw_active          <= 1'b0;
            ptw_fetched_pfn     <= {`PFN_WIDTH{1'b0}};
            ptw_fetched_pte_valid <= 1'b0;

            for (i = 0; i < `NUM_TLB_ENTRIES; i = i + 1) begin
                tlb_vpn[i]   <= {`VPN_WIDTH{1'b0}};
                tlb_pfn[i]   <= {`PFN_WIDTH{1'b0}};
                tlb_valid[i] <= 1'b0;
                tlb_lru[i]   <= {`TLB_INDEX_WIDTH{1'b0}};
            end
        end else begin
            // State update
            current_state <= next_state;

            // Clear resp if taken
            if (mmu_resp_valid && mmu_resp_ready)
                mmu_resp_valid <= 1'b0;

            case (current_state)
                S_IDLE: begin
                    ptw_active <= 1'b0;
                    ptw_timer  <= {PTW_LOOKUP_LATENCY{1'b0}};

                    if (mmu_req_valid && mmu_req_ready) begin
                        r_current_va  <= mmu_req_va;
                        r_current_vpn <= mmu_req_va[`ADDR_WIDTH-1:`PAGE_OFFSET_WIDTH];

                        if (tlb_hit) begin
                            // TLB hit: respond this cycle
                            mmu_resp_pa     <= (tlb_hit_pfn << `PAGE_OFFSET_WIDTH)
                                               | mmu_req_va[`PAGE_OFFSET_WIDTH-1:0];
                            mmu_resp_status <= `MMU_STATUS_HIT;
                            mmu_resp_valid  <= 1'b1;

                            // LRU: hit entry to 0, increment others
                            for (i = 0; i < `NUM_TLB_ENTRIES; i = i + 1) begin
                                if (tlb_valid[i]) begin
                                    if (i[`TLB_INDEX_WIDTH-1:0] == tlb_hit_idx)
                                        tlb_lru[i] <= {`TLB_INDEX_WIDTH{1'b0}};
                                    else
                                        tlb_lru[i] <= tlb_lru[i] + 1'b1;
                                end
                            end
                        end else begin
                            // TLB miss: start PTW
                            ptw_active <= 1'b1;
                            ptw_timer  <= {PTW_LOOKUP_LATENCY{1'b0}};
                        end
                    end
                end

                S_PTW_LOOKUP: begin
                    // simulate latency
                    if (ptw_timer < PTW_LOOKUP_LATENCY-1)
                        ptw_timer <= ptw_timer + 1'b1;

                    if (ptw_timer == PTW_LOOKUP_LATENCY-1) begin
                        ptw_active <= 1'b0;

                        // Mock PTEs for small VPNs; others fault
                        case (r_current_vpn)
                            20'd0: begin ptw_fetched_pfn <= 20'd10; ptw_fetched_pte_valid <= 1'b1; end
                            20'd1: begin ptw_fetched_pfn <= 20'd11; ptw_fetched_pte_valid <= 1'b1; end
                            20'd2: begin ptw_fetched_pfn <= 20'd12; ptw_fetched_pte_valid <= 1'b1; end
                            20'd3: begin ptw_fetched_pfn <= 20'd13; ptw_fetched_pte_valid <= 1'b1; end
                            default: begin ptw_fetched_pfn <= {`PFN_WIDTH{1'b0}}; ptw_fetched_pte_valid <= 1'b0; end
                        endcase
                    end
                end

                S_UPDATE_TLB: begin
                    if (ptw_fetched_pte_valid) begin
                        // Install entry at LRU victim
                        tlb_vpn[lru_victim_idx]   <= r_current_vpn;
                        tlb_pfn[lru_victim_idx]   <= ptw_fetched_pfn;
                        tlb_valid[lru_victim_idx] <= 1'b1;
                        tlb_lru[lru_victim_idx]   <= {`TLB_INDEX_WIDTH{1'b0}};

                        // Increment others
                        for (i = 0; i < `NUM_TLB_ENTRIES; i = i + 1) begin
                            if (i != lru_victim_idx && tlb_valid[i])
                                tlb_lru[i] <= tlb_lru[i] + 1'b1;
                        end

                        // Respond (resolved miss)
                        mmu_resp_pa     <= (ptw_fetched_pfn << `PAGE_OFFSET_WIDTH)
                                           | r_current_va[`PAGE_OFFSET_WIDTH-1:0];
                        mmu_resp_status <= `MMU_STATUS_MISS;
                        mmu_resp_valid  <= 1'b1;
                    end else begin
                        // Page fault
                        mmu_resp_pa     <= {`ADDR_WIDTH{1'b0}};
                        mmu_resp_status <= `MMU_STATUS_PAGE_FAULT;
                        mmu_resp_valid  <= 1'b1;
                    end
                end
            endcase
        end
    end

endmodule