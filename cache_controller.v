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
    output reg[5:0]  cache_mem_index,  // Index to read/write in cache (6 bits cause 64 sets for current Block and cache size)
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

    localparam NUM_SETS = 64;  // 2^INDEX_BITS
    localparam BLOCK_WORDS = 16;  // 64 bytes / 4 bytes per word

    // --- State Machine Definitions ---
    localparam [2:0] S_IDLE = 3'b000;  // Waiting for request
    localparam [2:0] S_CHECK_HIT = 3'b001;  // Check tag store
    localparam [2:0] S_READ_MISS_FETCH = 3'b010;  // Read miss: get block from mem
    localparam [2:0] S_READ_MISS_WAIT = 3'b011;  // Wait for main memory
    localparam [2:0] S_READ_MISS_REFILL = 3'b100;  // Write new block to cache
    localparam [2:0] S_WRITE_THROUGH = 3'b101;  // Write request: write to mem
    localparam [2:0] S_WRITE_THROUGH_WAIT = 3'b110;  // Wait for main memory

    reg [2:0] state, next_state;

    // --- Data Path Registers ---
    // Registers to hold data and addresses between states
    reg [31:0] reg_data_to_cpu;

    reg [511:0] reg_block_from_mem;
    reg [31:0] reg_phy_addr;
    reg [31:0] reg_data_from_mmu;
    reg reg_is_write;
    reg reg_is_read;

    // --- Internal Storage (Tag, Valid, LRU) ---
    // These are the core registers of the controller
    reg [TAG_BITS-1:0] tag_store[0:NUM_SETS-1][0:1];  // Tag store for 2 ways
    reg valid_store[0:NUM_SETS-1][0:1];  // Valid bit for 2 ways
    reg lru_store[0:NUM_SETS-1];  // LRU bit (0=Way0, 1=Way1)

    // --- Address Decomposition ---
    wire [TAG_BITS-1:0] addr_tag;
    wire [INDEX_BITS-1:0] addr_index;
    wire [OFFSET_BITS-1:0] addr_offset;

    assign addr_tag    = reg_phy_addr[31 : 32-TAG_BITS];
    assign addr_index  = reg_phy_addr[31-TAG_BITS : OFFSET_BITS];
    assign addr_offset = reg_phy_addr[OFFSET_BITS-1 : 0];
    // Word-level select from a 512-bit block
    wire    [  3:0] word_offset = addr_offset[5:2];  // 64B block, 4B word

    // --- Hit/Miss Logic (Combinational) ---
    wire            way0_hit = (tag_store[addr_index][0] == addr_tag) && valid_store[addr_index][0];
    wire            way1_hit = (tag_store[addr_index][1] == addr_tag) && valid_store[addr_index][1];
    wire            is_hit = way0_hit || way1_hit;



    // --- FSM Sequential Logic ---

    integer         i;  //index cursor for arrays
    reg             victim_way;  //temp reg for storing which way to evict

    // Helper to modify a 512-bit block with a new 32-bit word
    // This is needed for updating the cache on a write hit
    reg     [511:0] modified_cache_line;

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

        end //if !rst
     
        else begin
            state <= next_state;

            if (next_state == S_IDLE) begin
                reg_is_read  <= 1'b0;
                reg_is_write <= 1'b0;
            end

            // Latch request data
            //STATE: IDLE
            if (state == S_IDLE && (read_mem || write_mem)) begin
                reg_phy_addr      <= phy_addr;
                reg_data_from_mmu <= data_from_cpu;
                reg_is_write      <= write_mem;
                reg_is_read       <= read_mem;
            end

            // Latch block from main memory
            //STATE: S_READ_MISS_WAIT
            if (state == S_READ_MISS_WAIT && main_mem_ready) begin
                reg_block_from_mem <= main_mem_data_in;
            end

            // Update LRU on hit
            //STATE: S_CHECK_HIT
            if (state == S_CHECK_HIT && is_hit) begin
                if (way0_hit)
                    lru_store[addr_index] <= 1'b1;  // Way 1 is now LRU so we set the bit to 1
                else lru_store[addr_index] <= 1'b0;  // Way 0 is now LRU so we set the bit to 0
            end

            // Latch the output data on a Read Hit
            if (state == S_CHECK_HIT && is_hit && reg_is_read) begin
                if (way0_hit || way1_hit) begin
                    reg_data_to_cpu <= cache_mem_data_out[(word_offset*32)+:32];
                end
            end


            // Update cache on refill
            if (state == S_READ_MISS_REFILL) begin
                //eviction is decided here
                victim_way = lru_store[reg_phy_addr[31-TAG_BITS : OFFSET_BITS]];

                tag_store[reg_phy_addr[31-TAG_BITS : OFFSET_BITS]][victim_way]   <= reg_phy_addr[31 : 32-TAG_BITS];
                valid_store[reg_phy_addr[31-TAG_BITS : OFFSET_BITS]][victim_way] <= 1'b1;
                lru_store[reg_phy_addr[31-TAG_BITS : OFFSET_BITS]] <= ~victim_way;
            end
        end  //end else 
    end  //end always block

    // --- FSM Combinational Logic ---
    // Default outputs
    assign data_to_cpu = reg_data_to_cpu;  // Default to registered value
    assign hit_miss    = is_hit;  // Default to hit logic

    wire serviced_now = (state == S_CHECK_HIT) && is_hit && reg_is_read;
    // Also ready if we just finished a write
    wire write_done = (state == S_WRITE_THROUGH_WAIT) && main_mem_ready;
    assign ready_stall = ~((state == S_IDLE) || serviced_now || write_done);


    always @(*) begin
        next_state          = state;
        // Default values 
        cache_mem_index     = addr_index;  // Default to current index for read hits
        cache_mem_data_in   = 'd0;
        cache_mem_write_en  = 1'b0;

        main_mem_addr       = 'd0;
        main_mem_data_out   = 'd0;
        main_mem_read_req   = 1'b0;
        main_mem_write_req  = 1'b0;

        modified_cache_line = cache_mem_data_out;  // Default to current line

        case (state)
            S_IDLE: begin
                if (read_mem || write_mem) begin
                    next_state = S_CHECK_HIT;
                end
            end

            S_CHECK_HIT: begin
                if (reg_is_read) begin
                    if (is_hit) begin
                        // Read Hit
                        next_state = S_IDLE;
                    end else begin
                        // Read Miss
                        next_state = S_READ_MISS_FETCH;
                    end
                end else if (reg_is_write) begin
                    // Write Request (Write-Through)
                    // Check for hit to update cache (Write-Through with Update)

                    // Note: To support Write Update, we need to know *which* way hit.
                    // The logic below assumes we can write to the cache.
                    // Since our 'cache_mem' interface is simple, we need to use the
                    // 'victim_way' or cheat. Our simple_cache_mem uses 'lru_store' to decide write way.
                    // BUT for a hit update, we must write to the HIT way, not the LRU way.
                    // To fix this properly, we'd need to pass 'way_select' to cache mem.
                    // For now, we will just do Write-Through to Memory (No Allocate, No Update) 
                    // to keep it simple as requested, unless you want full consistency.
                    // ...
                    // OK, let's keep it simple: Write-Through to Memory ONLY.
                    // Test 5 failed because read returned stale data.
                    // To fix Test 5 without complex update logic: We must Invalidate the line on Write Hit.
                    // If we invalidate, the next read will miss, fetch from mem (new data), and be correct.

                    // ** INVALIDATE ON WRITE HIT **
                    if (is_hit) begin
                        if (way0_hit) valid_store[addr_index][0] = 1'b0;
                        if (way1_hit) valid_store[addr_index][1] = 1'b0;
                    end

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
