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
// 14 Nov 2025   Kalrav Mathur          Original
//
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
module cache_controller (
    input wire clk,
    input wire rst_n,

    // --- Interface to MMU/CPU ---
    input wire [31:0] phy_addr,        // Physical Address from MMU
    input wire [31:0] data_from_cpu, // Data from CPU (for writes)
    input wire        read_mem,        // CPU Read Request
    input wire        write_mem,       // CPU Write Request
    
    // Sends responses back to the CPU
    output wire [31:0] data_to_cpu,   // Data to CPU (on read hit)
    output wire        hit_miss,        // 1 for hit, 0 for miss
    output wire        ready_stall,     // 0 for ready, 1 for stall

   
     // --- Interface to Cache Memory ---
    output reg[5:0]  cache_mem_index,  // Index to read/write in cache (6 bits cause 64 sets for current Block and cache size)
    output reg [511:0] cache_mem_data_in,  // Data block to write to cache
    output reg        cache_mem_write_en, // Write enable for cache
    input wire  [511:0] cache_mem_data_out, // Data block read from cache


    // --- Interface to Main Memory ---
    output reg [31:0] main_mem_addr,       // Address to main memory
    output reg [31:0] main_mem_data_out,   // Data to write to main mem
    output reg        main_mem_read_req,   // Read request to main mem
    output reg        main_mem_write_req,  // Write request to main mem
    input wire  [511:0] main_mem_data_in,    // Data block from main mem
    input wire         main_mem_ready       // 1 when main mem is done
);

    // --- Parameter Definitions ---
    localparam TAG_BITS   = 20;
    localparam INDEX_BITS = 6;
    localparam OFFSET_BITS = 6;
    
    localparam NUM_SETS   = 64; // 2^INDEX_BITS
    localparam BLOCK_WORDS = 16; // 64 bytes / 4 bytes per word

    // --- State Machine Definitions ---
    localparam [2:0] S_IDLE              = 3'b000; // Waiting for request
    localparam [2:0] S_CHECK_HIT         = 3'b001; // Check tag store
    localparam [2:0] S_READ_MISS_FETCH   = 3'b010; // Read miss: get block from mem
    localparam [2:0] S_READ_MISS_WAIT    = 3'b011; // Wait for main memory
    localparam [2:0] S_READ_MISS_REFILL  = 3'b100; // Write new block to cache
    localparam [2:0] S_WRITE_THROUGH     = 3'b101; // Write request: write to mem
    localparam [2:0] S_WRITE_THROUGH_WAIT = 3'b110; // Wait for main memory

    reg [2:0] state, next_state;
    // --- Internal Storage (Tag, Valid, LRU) ---
    // These are the core registers of the controller
    reg [TAG_BITS-1:0] tag_store   [0:NUM_SETS-1][0:1]; // Tag store for 2 ways
    reg                valid_store [0:NUM_SETS-1][0:1]; // Valid bit for 2 ways
    reg                lru_store   [0:NUM_SETS-1];      // LRU bit (0=Way0, 1=Way1)

    // --- Address Decomposition ---
    wire [TAG_BITS-1:0]   addr_tag;
    wire [INDEX_BITS-1:0] addr_index;
    wire [OFFSET_BITS-1:0] addr_offset;

    assign addr_tag    = phy_addr[31 : 32-TAG_BITS];
    assign addr_index  = phy_addr[31-TAG_BITS : OFFSET_BITS];
    assign addr_offset = phy_addr[OFFSET_BITS-1 : 0];
    // Word-level select from a 512-bit block
    wire [3:0] word_offset = addr_offset[5:2]; // 64B block, 4B word

    // --- Hit/Miss Logic (Combinational) ---
    wire way0_hit = (tag_store[addr_index][0] == addr_tag) && valid_store[addr_index][0];
    wire way1_hit = (tag_store[addr_index][1] == addr_tag) && valid_store[addr_index][1];
    wire is_hit   = way0_hit || way1_hit;
    
    // --- Data Path Registers ---
    // Registers to hold data and addresses between states
    
    // ** BUG FIX: This is now a true sequential register for the output **
    reg [31:0] reg_data_to_cpu; 
    
    reg [511:0] reg_block_from_mem;
    reg [31:0] reg_phy_addr;
    reg [31:0] reg_data_from_mmu;
    reg        reg_is_write;
    reg        reg_is_read;
    
    
    // --- FSM Sequential Logic ---
    
    integer i; //index cursor for arrays
    reg victim_way; //temp reg for storing which way to evict
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= S_IDLE;
            reg_data_to_cpu <= 'd0; // ** BUG FIX: Reset the output register **
            
            // Initialize tag/valid stores on reset
            for (i = 0; i < NUM_SETS; i = i + 1) begin
                valid_store[i][0] <= 1'b0;
                valid_store[i][1] <= 1'b0;
                tag_store[i][0]   <= 'd0;
                tag_store[i][1]   <= 'd0;
                lru_store[i]      <= 1'b0;
            end
        end //if !rst
     
        else begin
            state <= next_state; //increment state for next clock
            
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
                    lru_store[addr_index] <= 1'b1; // Way 1 is now LRU so we set the bit to 1
                else
                    lru_store[addr_index] <= 1'b0; // Way 0 is now LRU so we set the bit to 0
            end
            
            // ** BUG FIX: Latch the output data on a Read Hit **
            // This happens on the same cycle the FSM is in S_CHECK_HIT
            if (state == S_CHECK_HIT && is_hit && reg_is_read) begin
                // Select correct 32-bit word from 512-bit block
                // (The 'if/else' is redundant but harmless)
                if (way0_hit)
                    reg_data_to_cpu <= cache_mem_data_out >> (word_offset * 32);
                else
                    reg_data_to_cpu <= cache_mem_data_out >> (word_offset * 32);
            end

            // Update cache on refill
            if (state == S_READ_MISS_REFILL) begin
            //eviction is decided here
                victim_way = lru_store[reg_phy_addr[31-TAG_BITS : OFFSET_BITS]]; //victim way is the way which is decided to be evicted based on LRU
                
                tag_store[reg_phy_addr[31-TAG_BITS : OFFSET_BITS]][victim_way]   <= reg_phy_addr[31 : 32-TAG_BITS]; //set the new phy addr tag in the tag array 
                valid_store[reg_phy_addr[31-TAG_BITS : OFFSET_BITS]][victim_way] <= 1'b1;
                lru_store[reg_phy_addr[31-TAG_BITS : OFFSET_BITS]]   <= ~victim_way; // Update LRU and set the other tag in current set as victim for next evistion
            end
        end //end else 
    end //end always block

    // --- FSM Combinational Logic ---
    // Default outputs
    assign data_to_cpu        = reg_data_to_cpu; // Default to registered value
    assign hit_miss           = is_hit;          // Default to hit logic
    assign ready_stall        = (state != S_IDLE); // Stall CPU if not idle


    always @(*) begin
        next_state = state;
        // **FIX:** Default values MUST be set inside the always block
        cache_mem_index    = addr_index; // Default to current index for read hits
        cache_mem_data_in  = 'd0;
        cache_mem_write_en = 1'b0;
        
        main_mem_addr      = 'd0;
        main_mem_data_out  = 'd0;
        main_mem_read_req  = 1'b0;
        main_mem_write_req = 1'b0;
        
        // ** BUG FIX: Removed default assignment for reg_data_to_cpu **
        // (This default is also needed for the internal reg_data_to_cpu latch)
        // reg_data_to_cpu = 'd0;  <-- This was the bug
        
        case (state)
            S_IDLE: begin
                if (read_mem || write_mem) begin
                    next_state = S_CHECK_HIT;
                end
            end
            
            S_CHECK_HIT: begin
                if (reg_is_read) begin
                    if (is_hit) begin
                       
                         // Read Hit: Get data from cache 
                        // ** BUG FIX: Logic moved to sequential block **
                        next_state = S_IDLE;
                    end 
                    else begin
                        // Read Miss
                        next_state = S_READ_MISS_FETCH;
                    end
                end 
                else if (reg_is_write) begin
                    // Write Request (Write-Through)
                    // We go to memory regardless of hit/miss
              
                     next_state = S_WRITE_THROUGH;
                end
            end
            
            S_READ_MISS_FETCH: begin
                // Request block from main memory
                // Align address to the start of the block
         
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
                // Write the fetched block into the cache data store
                cache_mem_index    = reg_phy_addr[31-TAG_BITS : OFFSET_BITS];
                cache_mem_data_in  = reg_block_from_mem;
                cache_mem_write_en = 1'b1;
                
                // The FSM will go to IDLE, CPU will retry,
                // and this time it will be a READ_HIT.
                next_state = S_IDLE; 
            end
            
            S_WRITE_THROUGH: begin
                // Write-Through: Send write to main memory
                // We send the *word* address and *word* data
                main_mem_addr      = reg_phy_addr;
                main_mem_data_out  = reg_data_from_mmu;
                main_mem_write_req = 1'b1;
                
                // Note: We also need to update cache if it was a hit
                // This simplified version doesn't, it stalls until mem write is done
                // A better version would update cache in parallel
                
              
                 next_state = S_WRITE_THROUGH_WAIT;
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

    // --- Cache Data Store Read Muxing ---
    // Combinational read from Cache Data Store based on index
    // This is required for the 1-cycle read hit.
    // NOTE: This implies the Cache Mem (SRAM) has a combinational read path.
    // We tie the cache_mem_index to the current request's index.
endmodule