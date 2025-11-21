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
// 18 Nov 2025   Kalrav Mathur          Fix crital logic errors (now simulation working) - need to fix some logic errors now based on the waveform
////////////////////////////////////////////////////////////////////////////////

/*
 * Cache Controller Module (2-Way Set-Associative, Write-Through)
 *
 * This module implements the cache controller logic based on the project slides
 * and report parameters.
 *
 * Parameters from Report:
 * - Physical Address: 32 bits
 * - Cache Size:a 8 KB
 * - Block Size: 64 Bytes
 * - Associativity: 2-Way
 *
 * Derived Parameters:
 * - Offset bits = log2(64) = 6 bits
 * - Total Blocks = 8KB / 64B = 128 blocks
 * - Number of Sets = 128 blocks / 2 ways = 64 sets
 * - Index bits = log2(64) = 6 bits
 * - Tag bits = 32 - 6 (Index) - 6 (Offset) = 20 bits
 *
 * Policies:
 * - Write Policy: Write-Through (data is written 
 * to both cache and main memory)
 * - Replacement Policy: Least Recently Used (LRU)
 */

`timescale 1ns / 1ps
module cache_controller (
    input wire clk,
    input wire rst_n,

    // --- Interface to MMU/CPU ---
    input wire [31:0] phy_addr,       // Physical Address from MMU
    input wire [31:0] data_from_cpu,  // Data from CPU (for writes)
    input wire        read_mem,       // CPU Read Request
    input wire        write_mem,      // CPU Write Request

    // Sends responses back to the CPU
    output wire [31:0] data_to_cpu,  // Data to CPU (on read hit)
    output wire        hit_miss,     // 1 for hit, 0 for miss
    output wire        ready_stall,  // 0 for ready, 1 for stall


    // --- Interface to Cache Memory ---
    output reg [5:0] cache_mem_index,  // Index to read/write in cache
    output reg [511:0] cache_mem_data_in,  // Data block to write to cache
    output reg cache_mem_write_en,  // Write enable for cache
    input wire [511:0] cache_mem_data_out,  // Data block read from cache


    // --- Interface to Main Memory ---
    output reg  [ 31:0] main_mem_addr,       // Address to main memory
    output reg  [ 31:0] main_mem_data_out,   // Data to write to main mem
    output reg          main_mem_read_req,   // Read request to main mem
    output reg          main_mem_write_req,  // Write request to main mem
    input  wire [511:0] main_mem_data_in,    // Data block from main mem
    input  wire         main_mem_ready       // 1 when main mem is done
);

    // --- Parameter Definitions ---
    localparam TAG_BITS = 20;
    localparam INDEX_BITS = 6;
    localparam OFFSET_BITS = 6;

    localparam NUM_SETS = 64;
    localparam BLOCK_WORDS = 16;

    // --- State Machine Definitions ---
    localparam [2:0] S_IDLE = 3'b000;
    localparam [2:0] S_CHECK_HIT = 3'b001;
    localparam [2:0] S_READ_MISS_FETCH = 3'b010;
    localparam [2:0] S_READ_MISS_WAIT = 3'b011;
    localparam [2:0] S_READ_MISS_REFILL = 3'b100;
    localparam [2:0] S_WRITE_THROUGH = 3'b101;
    localparam [2:0] S_WRITE_THROUGH_WAIT = 3'b110;

    reg [2:0] state, next_state;

    // --- Data Path Registers ---
    reg [31:0] reg_data_to_cpu;
    reg [511:0] reg_block_from_mem;
    reg [31:0] reg_phy_addr;
    reg [31:0] reg_data_from_mmu;
    reg reg_is_write;
    reg reg_is_read;

    // --- Internal Storage (Tag, Valid, LRU) ---
    reg [TAG_BITS-1:0] tag_store[0:NUM_SETS-1][0:1];
    reg valid_store[0:NUM_SETS-1][0:1];
    reg lru_store[0:NUM_SETS-1];

    // --- Address Decomposition ---
    wire [TAG_BITS-1:0] addr_tag;
    wire [INDEX_BITS-1:0] addr_index;
    wire [OFFSET_BITS-1:0] addr_offset;

    assign addr_tag    = reg_phy_addr[31 : 32-TAG_BITS];
    assign addr_index  = reg_phy_addr[31-TAG_BITS : OFFSET_BITS];
    assign addr_offset = reg_phy_addr[OFFSET_BITS-1 : 0];

    wire    [3:0] word_offset = addr_offset[5:2];

    // --- Hit/Miss Logic (Combinational) ---
    wire          way0_hit = (tag_store[addr_index][0] == addr_tag) && valid_store[addr_index][0];
    wire          way1_hit = (tag_store[addr_index][1] == addr_tag) && valid_store[addr_index][1];
    wire          is_hit = way0_hit || way1_hit;

    // --- FSM Sequential Logic ---
    integer       i;
    reg           victim_way;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= S_IDLE;
            reg_data_to_cpu <= 'd0;

            // Initialize tag/valid stores on reset
            for (i = 0; i < NUM_SETS; i = i + 1) begin
                valid_store[i][0] <= 1'b0;
                valid_store[i][1] <= 1'b0;
                tag_store[i][0]   <= 'd0;
                tag_store[i][1]   <= 'd0;
                lru_store[i]      <= 1'b0;
            end
            reg_is_read  <= 1'b0;
            reg_is_write <= 1'b0;

        end else begin
            state <= next_state;

            if (next_state == S_IDLE) begin
                reg_is_read  <= 1'b0;
                reg_is_write <= 1'b0;
            end

            // Latch request data
            if (state == S_IDLE && (read_mem || write_mem)) begin
                reg_phy_addr      <= phy_addr;
                reg_data_from_mmu <= data_from_cpu;
                reg_is_write      <= write_mem;
                reg_is_read       <= read_mem;
            end

            // Latch block from main memory
            if (state == S_READ_MISS_WAIT && main_mem_ready) begin
                reg_block_from_mem <= main_mem_data_in;
            end

            // Update LRU on hit
            if (state == S_CHECK_HIT && is_hit) begin
                if (way0_hit) lru_store[addr_index] <= 1'b1;
                else lru_store[addr_index] <= 1'b0;
            end

            // Latch the output data on a Read Hit
            if (state == S_CHECK_HIT && is_hit && reg_is_read) begin
                if (way0_hit || way1_hit) begin
                    reg_data_to_cpu <= cache_mem_data_out[(word_offset*32)+:32];
                end
            end

            // ** NEW: Invalidate cache line on Write Hit **
            if (state == S_CHECK_HIT && is_hit && reg_is_write) begin
                if (way0_hit) valid_store[addr_index][0] <= 1'b0;
                if (way1_hit) valid_store[addr_index][1] <= 1'b0;
            end

            // Update cache on refill
            if (state == S_READ_MISS_REFILL) begin
                victim_way = lru_store[reg_phy_addr[31-TAG_BITS : OFFSET_BITS]];

                tag_store[reg_phy_addr[31-TAG_BITS : OFFSET_BITS]][victim_way]   <= reg_phy_addr[31 : 32-TAG_BITS];
                valid_store[reg_phy_addr[31-TAG_BITS : OFFSET_BITS]][victim_way] <= 1'b1;
                lru_store[reg_phy_addr[31-TAG_BITS : OFFSET_BITS]] <= ~victim_way;
            end
        end
    end

    // --- FSM Combinational Logic ---
    assign data_to_cpu = reg_data_to_cpu;
    assign hit_miss    = is_hit;

    wire serviced_now = (state == S_CHECK_HIT) && is_hit && reg_is_read;
    wire write_done = (state == S_WRITE_THROUGH_WAIT) && main_mem_ready;
    assign ready_stall = ~((state == S_IDLE) || serviced_now || write_done);

    always @(*) begin
        next_state         = state;
        cache_mem_index    = addr_index;
        cache_mem_data_in  = 'd0;
        cache_mem_write_en = 1'b0;

        main_mem_addr      = 'd0;
        main_mem_data_out  = 'd0;
        main_mem_read_req  = 1'b0;
        main_mem_write_req = 1'b0;

        case (state)
            S_IDLE: begin
                if (read_mem || write_mem) begin
                    next_state = S_CHECK_HIT;
                end
            end

            S_CHECK_HIT: begin
                if (reg_is_read) begin
                    if (is_hit) begin
                        next_state = S_IDLE;
                    end else begin
                        next_state = S_READ_MISS_FETCH;
                    end
                end else if (reg_is_write) begin
                    // Write Request -> Go to Write Through state
                    next_state = S_WRITE_THROUGH;
                end
            end

            S_READ_MISS_FETCH: begin
                main_mem_addr     = {reg_phy_addr[31:OFFSET_BITS], {OFFSET_BITS{1'b0}}};
                main_mem_read_req = 1'b1;
                next_state        = S_READ_MISS_WAIT;
            end

            S_READ_MISS_WAIT: begin
                if (main_mem_ready) begin
                    next_state = S_READ_MISS_REFILL;
                end
            end

            S_READ_MISS_REFILL: begin
                cache_mem_index    = reg_phy_addr[31-TAG_BITS : OFFSET_BITS];
                cache_mem_data_in  = reg_block_from_mem;
                cache_mem_write_en = 1'b1;
                next_state = S_IDLE;
            end

            S_WRITE_THROUGH: begin
                main_mem_addr      = reg_phy_addr;
                main_mem_data_out  = reg_data_from_mmu;
                main_mem_write_req = 1'b1;
                next_state         = S_WRITE_THROUGH_WAIT;
            end

            S_WRITE_THROUGH_WAIT: begin
                if (main_mem_ready) begin
                    next_state = S_IDLE;
                end
            end

            default: begin
                next_state = S_IDLE;
            end
        endcase
    end
endmodule
