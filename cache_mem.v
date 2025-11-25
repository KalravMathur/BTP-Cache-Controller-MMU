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
// 18 Nov 2025   Kalrav Mathur          Fix multiple critical TB Issues
//
////////////////////////////////////////////////////////////////////////////////
/*
 * Simple L1 Cache Memory Model
 * * - Size: 64 sets * 2 ways = 128 blocks
 * - Block Size: 512 bits (64 bytes)
 * - Behavior: 
 * - Asynchronous read (combinational)
 * - Synchronous write
 * - Takes 'lru_bit' as an input to decide which way to write to (for simplicity in TB)
 * OR just blindly writes to an internal array based on an absolute index if the controller provided it.
 * * NOTE: Since the controller's "cache_mem_index" is only 6 bits (the set index), 
 * this memory model needs to know *which way* to access. 
 * Real hardware would typically have separate SRAM banks for each way, or a larger address width.
 * * To keep this compatible with your current controller interface (which only outputs a 6-bit index),
 * we will simulate TWO separate SRAM arrays (Way 0 and Way 1) inside this module.
 * * For READS: We output the data from BOTH ways (muxed by the controller later? No, the controller expects 512 bits).
 * Actually, looking at your controller, it expects "cache_mem_data_out" to be the CORRECT data.
 * This implies the cache memory logic needs to know about hits/misses to mux the output, 
 * OR the controller should take two 512-bit inputs.
 * * SIMPLIFICATION FOR TESTBENCH:
 * We will make this memory "cheat" slightly. It will have a backdoor access to the controller's 
 * hit signals to select the right read data.
 */
`timescale 1ns / 1ps
module cache_mem (
    input  wire         clk,
    input  wire [  5:0] index,     // Set index from controller
    input  wire [511:0] data_in,   // Data to write
    input  wire         write_en,  // Write enable
    output reg  [511:0] data_out,  // Data read out

    input wire way0_hit,  // From Controller
    input wire way1_hit,  // From Controller
    input wire lru_bit    // From Controller (to know which way to write on refill)
);

    // Storage: 64 sets, 2 ways
    // Cache block: 512 bits 
    reg [511:0] way0[0:63];
    reg [511:0] way1[0:63];

    // Initialize memory to 0
    integer i;
    initial begin
        for (i = 0; i < 64; i = i + 1) begin
            way0[i] = i;
            way1[i] = i;
        end
    end

    // --- Write Operation (Synchronous) ---
    always @(posedge clk) begin
        if (write_en) begin
            // If we are writing, we use the LRU bit to decide which way is the victim
            // (The controller flips the LRU *after* the write, so the current LRU value points to the victim)
            $display("[CacheMem] Write en");
            if (lru_bit == 1'b0) begin
                way0[index] <= data_in;
                $display("[CacheMem] Wrote to Set %0d, Way 0: %h", index, data_in);
            end else begin
                way1[index] <= data_in;
                $display("[CacheMem] Wrote to Set %0d, Way 1: %h", index, data_in);
            end
        end
    end

    // --- Read Operation (Combinational/Asynchronous) ---
    // This mimics the behavior of selecting the correct way based on the hit logic
    always @(*) begin
        if (way0_hit) begin
            data_out = way0[index];
        end else if (way1_hit) begin
            data_out = way1[index];
        end else begin
            // On a miss, or idle, just output Way 0 (default) or 0
            // This doesn't matter since the controller ignores data on a miss
            data_out = way0[index];
        end
    end

endmodule
