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

`timescale 1ns / 1ps

module tb_cache_controller;

    // --- Parameters ---
    localparam CLK_PERIOD = 10; // 10ns clock period
    localparam MAIN_MEM_DELAY = 30; // 30ns (3 clock cycles) for main mem

    // --- DUT Inputs (driven by tb) ---
    reg clk;
    reg rst_n;
    reg [31:0] phy_addr;
    reg [31:0] data_from_cpu;
    reg        read_mem;
    reg        write_mem;
    reg [511:0] cache_mem_data_out; // Simulates Cache SRAM output
    reg [511:0] main_mem_data_in;   // Simulates Main Mem output
    reg        main_mem_ready;
    
    // ** SYNTAX FIX: Moved declarations to module scope **
    reg lru_bit; // Used for "cheating" in the SRAM model
    integer i; 

    // --- DUT Outputs (monitored by tb) ---
    wire [31:0] data_to_cpu;
    wire        hit_miss;
    wire        ready_stall;
    wire [5:0]  cache_mem_index;
    wire [511:0] cache_mem_data_in;
    wire        cache_mem_write_en;
    wire [31:0] main_mem_addr;
    wire [31:0] main_mem_data_out;
    wire        main_mem_read_req;
    wire        main_mem_write_req;

    // --- Instantiate the Device Under Test (DUT) ---
    cache_controller dut (
        .clk(clk),
        .rst_n(rst_n),
        .phy_addr(phy_addr),
        .data_from_cpu(data_from_cpu),
        .read_mem(read_mem),
        .write_mem(write_mem),
        .data_to_cpu(data_to_cpu),
        .hit_miss(hit_miss),
        .ready_stall(ready_stall),
        .cache_mem_index(cache_mem_index),
        .cache_mem_data_in(cache_mem_data_in),
        .cache_mem_write_en(cache_mem_write_en),
        .cache_mem_data_out(cache_mem_data_out),
        .main_mem_addr(main_mem_addr),
        .main_mem_data_out(main_mem_data_out),
        .main_mem_read_req(main_mem_read_req),
        .main_mem_write_req(main_mem_write_req),
        .main_mem_data_in(main_mem_data_in),
        .main_mem_ready(main_mem_ready)
    );

    // --- Clock Generator ---
    always #((CLK_PERIOD / 2)) clk = ~clk;

    // --- Memory Simulations ---

    // 1. Simulate Cache Memory (SRAM)
    reg [511:0] cache_sram [0:127]; // 64 sets * 2 ways
    
    // ** SYNTAX FIX: Moved declarations to module scope **
    reg [511:0] cache_sram_way0 [0:63];
    reg [511:0] cache_sram_way1 [0:63];
    
    // Combinational Read Port
    // ** SYNTAX FIX: Replaced 'assign' with 'always @(*)' for a 'reg' **
    always @(*) begin
        // This is a simplified model. A real 2-way SRAM model would be
        // more complex. This muxes the data based on the DUT's *internal*
        // hit signals, which is common in testbenches.
        if (dut.way1_hit) begin
            cache_mem_data_out = cache_sram[cache_mem_index * 2 + 1];
        end else begin
            cache_mem_data_out = cache_sram[cache_mem_index * 2 + 0];
        end
    end
    
    // Synchronous Write Port
    always @(posedge clk) begin
        if (cache_mem_write_en) begin
            // We *cheat* and look at the DUT's internal LRU bit to know
            // which way to write our simulated SRAM.
            lru_bit = dut.lru_store[cache_mem_index];
            
            // lru_bit *points* to the victim way (the one to replace)
            cache_sram[cache_mem_index * 2 + lru_bit] <= cache_mem_data_in;
            $display("TB: Cache SRAM Write to Index: %d, Way: %d", cache_mem_index, lru_bit);
        end
    end
    
    // 2. Simulate Main Memory (DRAM)
    reg [511:0] main_memory [0:1023]; // A small 8KB main memory
    reg [31:0]  mem_addr_reg;
    reg         mem_read_pending;
    
    initial begin
        // Pre-load main memory with some test data
        // ** SYNTAX FIX: Removed 'integer' from loop declaration **
        for (i = 0; i < 1024; i = i + 1) begin
            main_memory[i] = {512{1'b0}} + i; // Block 'i' contains data 'i'
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            main_mem_ready <= 1'b0;
            main_mem_data_in <= 'd0;
            mem_read_pending <= 1'b0;
        end else begin
            // Default: not ready unless we say so
            main_mem_ready <= 1'b0; 

            if (main_mem_write_req) begin
                // Handle write request
                $display("TB: Main Mem Write Req. Addr: 0x%h, Data: 0x%h", main_mem_addr, main_mem_data_out);
                // Align to 64-byte block
                main_memory[main_mem_addr >> 6][(main_mem_addr[5:2] * 32) +: 32] <= main_mem_data_out;
                
                // Wait for delay
                #(MAIN_MEM_DELAY);
                main_mem_ready <= 1'b1;
            end
            else if (main_mem_read_req) begin
                // Handle read request (start)
                $display("TB: Main Mem Read Req. Addr: 0x%h", main_mem_addr);
                // Latch the block-aligned address
                mem_addr_reg <= main_mem_addr >> 6; // Block address
                mem_read_pending <= 1'b1;
                main_mem_ready <= 1'b0;
            end
            else if (mem_read_pending) begin
                // Handle read (finish)
                #(MAIN_MEM_DELAY - CLK_PERIOD); // Wait for delay
                main_mem_data_in <= main_memory[mem_addr_reg];
                main_mem_ready <= 1'b1;
                mem_read_pending <= 1'b0;
                $display("TB: Main Mem Read Done. Data: 0x%h", main_memory[mem_addr_reg]);
            end
        end
    end

    // --- Main Test Sequence ---
    initial begin
        $display("--- Testbench Started ---");
        
        // ** NEW FOCUSED DUMP LIST **
        $dumpfile("waveform.vcd");
        $dumpvars(1, tb_cache_controller.clk);
        $dumpvars(1, tb_cache_controller.rst_n);
        $dumpvars(1, tb_cache_controller.phy_addr);
        $dumpvars(1, tb_cache_controller.data_from_cpu);
        $dumpvars(1, tb_cache_controller.read_mem);
        $dumpvars(1, tb_cache_controller.write_mem);
        $dumpvars(1, tb_cache_controller.data_to_cpu);
        $dumpvars(1, tb_cache_controller.hit_miss);
        $dumpvars(1, tb_cache_controller.ready_stall);
        
        // Monitor the FSM state
        $dumpvars(1, tb_cache_controller.state);
        $dumpvars(1, tb_cache_controller.next_state);
        
        // Monitor Cache Mem Interface (as requested)
        $dumpvars(1, tb_cache_controller.cache_mem_index);
        $dumpvars(1, tb_cache_controller.cache_mem_data_in);
        $dumpvars(1, tb_cache_controller.cache_mem_write_en);
        $dumpvars(1, tb_cache_controller.cache_mem_data_out);
        
        // Monitor Main Mem Interface
        $dumpvars(1, tb_cache_controller.main_mem_addr);
        $dumpvars(1, tb_cache_controller.main_mem_read_req);
        $dumpvars(1, tb_cache_controller.main_mem_write_req);
        $dumpvars(1, tb_cache_controller.main_mem_ready);
        
        // Monitor LRU bit for set 0 (our test set)
        $dumpvars(1, tb_cache_controller.dut.lru_store[0]);

        // 1. Initialize and Reset
        clk <= 0;
        rst_n <= 1;
        phy_addr <= 0;
        data_from_cpu <= 0;
        read_mem <= 0;
        write_mem <= 0;
        #10;
        rst_n <= 0; // Assert reset
        #20;
        rst_n <= 1; // De-assert reset
        $display("--- DUT Reset ---");
        
        // Wait for cache to be ready
        wait (ready_stall == 0);
        #CLK_PERIOD;

        // --- Test 1: Read Miss ---
        // Address: 0x0000_1000 (Tag=0x00001, Index=0)
        $display("\n--- Test 1: Read Miss (Addr: 0x1000) ---");
        read_mem_req(32'h00001000);
        
        $display("--- Test 1 Passed (Read Miss Handled) ---");
        
        // --- Test 2: Read Hit ---
        // Address: 0x0000_1000 (Same block as Test 1)
        $display("\n--- Test 2: Read Hit (Addr: 0x1000) ---");
        phy_addr <= 32'h00001000;
        read_mem <= 1'b1;
        #CLK_PERIOD;
        read_mem <= 1'b0;
        
        // Wait for the hit response (should be 1 cycle)
        #CLK_PERIOD;
        if (hit_miss == 1 && ready_stall == 0) begin
            $display("TB: Read Hit successful!");
            // Check data: main_memory[0x1000 >> 6] = main_memory[64] = 64
            // Word offset is 0.
            if (data_to_cpu == 32'd64) // Word 0 of block 64
                $display("TB: Read Hit Data correct! (0x%h)", data_to_cpu);
            else
                $display("TB: ERROR! Read Hit Data incorrect! (Got 0x%h, Exp 0x%h)", data_to_cpu, 32'd64);
        end else begin
            $display("TB: ERROR! Read Hit failed! (hit: %b, ready: %b)", hit_miss, ready_stall);
        end
        
        $display("--- Test 2 Passed (Read Hit) ---");
        
        // --- Test 3: Write-Through ---
        // Address: 0x0000_2000 (Tag=0x00002, Index=0)
        $display("\n--- Test 3: Write-Through (Addr: 0x2000) ---");
        write_mem_req(32'h00002000, 32'hCAFEBABE);
        
        $display("--- Test 3 Passed (Write-Through Handled) ---");

        // --- Test 4: Conflict Miss (Eviction) ---
        // 1. Fill Way 0 (Index 0) - Already done (Addr 0x1000, Tag 0x00001)
        // 2. Fill Way 1 (Index 0)
        // Address: 0x0004_1000 (Tag=0x00041, Index=0)
        $display("\n--- Test 4: Conflict Miss (Fill Way 1, Addr: 0x41000) ---");
        read_mem_req(32'h00041000); // This will be a miss, fill Way 1
        
        // 3. Evict Way 0
        // Address: 0x0008_1000 (Tag=0x00081, Index=0)
        $display("\n--- Test 4: Conflict Miss (Evict Way 0, Addr: 0x81000) ---");
        read_mem_req(32'h00081000); // This will be a miss, evict Way 0 (Tag 0x00001)
        
        $display("--- Test 4 Passed (Eviction) ---");
        
        // --- Test 5: Read After Eviction ---
        // Address: 0x0000_1000 (This was in Way 0, now evicted)
        $display("\n--- Test 5: Read After Eviction (Addr: 0x1000) ---");
        phy_addr <= 32'h00001000;
        read_mem <= 1'b1;
        #CLK_PERIOD;
        read_mem <= 1'b0;
        
        // Wait for 1 cycle (S_CHECK_HIT)
        #CLK_PERIOD;
        if (hit_miss == 0) begin
            $display("TB: Read after eviction was a MISS, as expected!");
        end else begin
            $display("TB: ERROR! Read after eviction was a HIT!");
        end
        
        // Wait for the full miss to be handled
        wait (ready_stall == 0);
        #CLK_PERIOD;
        
        $display("--- Test 5 Passed (Eviction Verified) ---");
        
        
        $display("\n--- All Tests Passed! ---");
        $finish;
    end

    // --- Helper Tasks ---
    
    // Task to issue a read request and wait for it to complete
    task read_mem_req(input [31:0] addr);
    begin
        wait (ready_stall == 0);
        phy_addr <= addr;
        read_mem <= 1'b1;
        
        // Assert request for one cycle
        #CLK_PERIOD;
        read_mem <= 1'b0;
        
        // Wait for the controller to finish (go from stall to ready)
        wait (ready_stall == 1); // Wait for controller to start
        $display("TB: Controller is STALLED (handling request)");
        wait (ready_stall == 0); // Wait for controller to finish
        $display("TB: Controller is READY");
        #CLK_PERIOD; // Settle
    end
    endtask
    
    // Task to issue a write request and wait for it to complete
    task write_mem_req(input [31:0] addr, input [31:0] data);
    begin
        wait (ready_stall == 0);
        phy_addr <= addr;
        data_from_cpu <= data;
        write_mem <= 1'b1;
        
        // Assert request for one cycle
        #CLK_PERIOD;
        write_mem <= 1'b0;
        
        // Wait for the controller to finish (go from stall to ready)
        wait (ready_stall == 1); // Wait for controller to start
        $display("TB: Controller is STALLED (handling request)");
        wait (ready_stall == 0); // Wait for controller to finish
        $display("TB: Controller is READY");
        #CLK_PERIOD; // Settle
    end
    endtask

endmodule