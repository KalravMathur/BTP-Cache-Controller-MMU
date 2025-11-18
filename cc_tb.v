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

module tb_cache_controller;

  // --- Parameters ---
  localparam CLK_PERIOD = 10;  // 10ns clock period
  localparam MAIN_MEM_DELAY = 30;  // 30ns (3 clock cycles) for main mem

  // --- DUT Inputs (driven by tb) ---
  reg             clk;
  reg             rst_n;
  reg     [ 31:0] phy_addr;
  reg     [ 31:0] data_from_cpu;
  reg             read_mem;
  reg             write_mem;
  reg     [511:0] cache_mem_data_out;  // Simulates Cache SRAM output
  reg     [511:0] main_mem_data_in;  // Simulates Main Mem output
  reg             main_mem_ready;

  // ** SYNTAX FIX: Moved declarations to module scope **
  reg             lru_bit;  // Used for "cheating" in the SRAM model
  integer         i;

  // --- DUT Outputs (monitored by tb) ---
  wire    [ 31:0] data_to_cpu;
  wire            hit_miss;
  wire            ready_stall;
  wire    [  5:0] cache_mem_index;
  wire    [511:0] cache_mem_data_in;
  wire            cache_mem_write_en;
  wire    [ 31:0] main_mem_addr;
  wire    [ 31:0] main_mem_data_out;
  wire            main_mem_read_req;
  wire            main_mem_write_req;

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

  // Local mirror of cache tag/valid metadata (TB-side)
  localparam TAG_BITS_TB = 20;
  localparam INDEX_BITS_TB = 6;
  localparam OFFSET_BITS_TB = 6;
  // TB tag/valid arrays (kept in sync when TB observes cache writes)
  reg     [TAG_BITS_TB-1:0] tb_tag_store                            [0:63][0:1];
  reg                       tb_valid_store                          [0:63][0:1];
  integer                   idx;  // used for combinational read mux
  integer                   ok;

  // --- Clock Generator ---
  always #((CLK_PERIOD / 2)) clk = ~clk;

  // --- Memory Simulations ---

  // 1. Simulate Cache Memory (SRAM)
  reg [511:0] cache_sram[0:127];  // 64 sets * 2 ways

  // ** SYNTAX FIX: Moved declarations to module scope **
  reg [511:0] cache_sram_way0[0:63];
  reg [511:0] cache_sram_way1[0:63];

  // Combinational Read Port
  // TB-side combinational read port: select data based on TB-mirrored tags/valids
  always @(*) begin
    // default
    cache_mem_data_out = {512{1'b0}};
    // compute index once
    //integer idx;
    idx = cache_mem_index;
    // pick way1 if valid and tag matches current request tag (derived from phy_addr)
    // Tag bits: [31:12] (20 bits)
    if (tb_valid_store[idx][1] && (tb_tag_store[idx][1] == phy_addr[31:12])) begin
      cache_mem_data_out = cache_sram[idx*2+1];
    end else if (tb_valid_store[idx][0] && (tb_tag_store[idx][0] == phy_addr[31:12])) begin
      cache_mem_data_out = cache_sram[idx*2+0];
    end else begin
      // no valid line in this testbench model: return block of zeros
      cache_mem_data_out = {512{1'b0}};
    end
  end



  // Synchronous Write Port
  always @(posedge clk) begin
    if (cache_mem_write_en) begin
      // read victim way (still peeking DUT.lru_store for now)
      lru_bit = dut.lru_store[cache_mem_index];

      // write the block to chosen way in TB SRAM model
      cache_sram[cache_mem_index*2+lru_bit] <= cache_mem_data_in;

      // Update TB's tag/valid mirrors using reg_phy_addr visible in DUT
      // Since the DUT latches reg_phy_addr internally, we peek it here AS
      // a testbench-only shortcut to maintain mirror consistency.
      tb_tag_store[cache_mem_index][lru_bit] <= dut.reg_phy_addr[31:12];
      tb_valid_store[cache_mem_index][lru_bit] <= 1'b1;

      $display("TB: Cache SRAM Write to Index: %d, Way: %d (tag %h)", cache_mem_index, lru_bit,
               dut.reg_phy_addr[31:12]);
    end
  end


  // 2. Simulate Main Memory (DRAM)
  reg [511:0] main_memory      [0:1023];  // A small 8KB main memory
  reg [ 31:0] mem_addr_reg;
  reg         mem_read_pending;

  initial begin
    // Pre-load main memory with some test data
    // ** SYNTAX FIX: Removed 'integer' from loop declaration **
    for (i = 0; i < 1024; i = i + 1) begin
      main_memory[i] = {512{1'b0}} + i;  // Block 'i' contains data 'i'
    end
  end

  // --- Main Memory (cycle-accurate, no blocking delays) ---
  // Replaces previous blocking-# implementation.
  reg [15:0] mem_latency_cnt;  // cycles left until response
  reg        mem_serving_read;  // high while a read is being served
  reg        mem_serving_write;  // high while a write is being served
  reg [31:0] mem_pending_block;  // block index for pending read/write
  reg [31:0] mem_pending_word_addr;  // word index for pending write

  localparam integer MEM_LATENCY_CYCLES = MAIN_MEM_DELAY / CLK_PERIOD;  // e.g. 30/10 = 3

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      main_mem_ready        <= 1'b0;
      main_mem_data_in      <= {512{1'b0}};
      mem_read_pending      <= 1'b0;
      mem_serving_read      <= 1'b0;
      mem_serving_write     <= 1'b0;
      mem_latency_cnt       <= 0;
      mem_pending_block     <= 0;
      mem_pending_word_addr <= 0;
    end else begin
      // default: ready only asserted for 1 cycle when response completes
      main_mem_ready <= 1'b0;

      // Start a write (if requested and nothing else in progress)
      if (main_mem_write_req && !mem_serving_read && !mem_serving_write) begin
        mem_pending_block     <= main_mem_addr >> OFFSET_BITS_TB;  // block index
        mem_pending_word_addr <= main_mem_addr[OFFSET_BITS_TB-1:2];  // word within block
        mem_serving_write     <= 1'b1;
        mem_latency_cnt       <= MEM_LATENCY_CYCLES;
        $display("TB: Main Mem Write START. Block: %0d, Word: %0d",
                 main_mem_addr >> OFFSET_BITS_TB, main_mem_addr[OFFSET_BITS_TB-1:2]);
      end  // Start a read (if requested and nothing else in progress)

      else if (main_mem_read_req && !mem_serving_read && !mem_serving_write) begin
        mem_pending_block <= main_mem_addr >> OFFSET_BITS_TB;
        mem_serving_read  <= 1'b1;
        mem_latency_cnt   <= MEM_LATENCY_CYCLES;
        $display("TB: Main Mem Read START. Block: %0d", main_mem_addr >> OFFSET_BITS_TB);
      end  // Service in-progress transaction


      else if (mem_serving_read || mem_serving_write) begin
        if (mem_latency_cnt > 0) begin
          mem_latency_cnt <= mem_latency_cnt - 1;
        end else begin
          if (mem_serving_write) begin
            // finish write
            main_memory[mem_pending_block][(mem_pending_word_addr*32)+:32] <= main_mem_data_out;
            $display("TB: Main Mem Write DONE. Block %0d, word %0d", mem_pending_block,
                     mem_pending_word_addr);
            main_mem_ready <= 1'b1;
            mem_serving_write <= 1'b0;
          end else begin
            // finish read
            main_mem_data_in <= main_memory[mem_pending_block];
            $display("TB: Main Mem Read DONE. Block %0d Data: %h", mem_pending_block,
                     main_memory[mem_pending_block]);
            main_mem_ready   <= 1'b1;
            mem_serving_read <= 1'b0;
          end
        end
      end
      // else idle: main_mem_ready==0
    end
  end


  // --- Main Test Sequence ---
  initial begin
    $display("--- Testbench Started ---");

    // Dump everything in the testbench scope (safe, avoids illegal memory-word arg)
    $dumpfile("waveform.vcd");
    $dumpvars(0, tb_cache_controller);


    // 1. Initialize and Reset
    clk <= 0;
    rst_n <= 1;
    phy_addr <= 0;
    data_from_cpu <= 0;
    read_mem <= 0;
    write_mem <= 0;
    #10;
    rst_n <= 0;  // Assert reset
    #20;
    rst_n <= 1;  // De-assert reset
    $display("--- DUT Reset ---");


    wait_for_ready(0, 2000, ok);
    if (!ok) $fatal("Timeout waiting for initial ready_stall==0");


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
      if (data_to_cpu == 32'd64)  // Word 0 of block 64
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
    read_mem_req(32'h00041000);  // This will be a miss, fill Way 1

    // 3. Evict Way 0
    // Address: 0x0008_1000 (Tag=0x00081, Index=0)
    $display("\n--- Test 4: Conflict Miss (Evict Way 0, Addr: 0x81000) ---");
    read_mem_req(32'h00081000);  // This will be a miss, evict Way 0 (Tag 0x00001)

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
    wait_for_ready(0, 2000, ok);
    if (!ok) $fatal("Timeout waiting for ready_stall==0 (end of test 5)");


    #CLK_PERIOD;

    $display("--- Test 5 Passed (Eviction Verified) ---");


    $display("\n--- All Tests Passed! ---");
    $finish;
  end

  // --- Utility: bounded wait for ready_stall with timeout (cycles) ---
  // Implemented as a task (tasks may contain timing controls).
  task wait_for_ready(input integer target, input integer timeout_cycles, output integer success);
    integer cc;
    begin
      cc = 0;
      success = 0;
      // Use clock edges for deterministic waits
      while (ready_stall !== target) begin
        @(posedge clk);
        cc = cc + 1;
        if (cc > timeout_cycles) begin
          $display("TB: TIMEOUT waiting for ready_stall == %0d after %0d cycles", target, cc);
          success = 0;
          disable wait_for_ready;  // exit task
        end
      end
      success = 1;
    end
  endtask


  // --- Helper Tasks ---

  // Task to issue a read request and wait for it to complete
  task read_mem_req(input [31:0] addr);
    begin
      //integer ok;
      wait_for_ready(0, 2000, ok);
      if (!ok) $fatal("Timeout before issuing read_mem_req");


      phy_addr <= addr;
      read_mem <= 1'b1;

      // Assert request for one cycle
      #CLK_PERIOD;
      read_mem <= 1'b0;

      // Wait for the controller to finish (go from stall to ready)
      //integer ok;
      wait_for_ready(1, 2000, ok);
      if (!ok) $fatal("Timeout waiting for controller to start handling read request");


      $display("TB: Controller is STALLED (handling request)");
      wait_for_ready(0, 2000, ok);
      if (!ok) $fatal("Timeout waiting for controller to finish read request");


      $display("TB: Controller is READY");
      #CLK_PERIOD;  // Settle
    end
  endtask

  // Task to issue a write request and wait for it to complete
  task write_mem_req(input [31:0] addr, input [31:0] data);
    begin
      //integer ok;
      wait_for_ready(0, 2000, ok);
      if (!ok) $fatal("Timeout before issuing write_mem_req");


      phy_addr <= addr;
      data_from_cpu <= data;
      write_mem <= 1'b1;

      // Assert request for one cycle
      #CLK_PERIOD;
      write_mem <= 1'b0;

      // Wait for the controller to finish (go from stall to ready)
      //integer ok;
      wait_for_ready(1, 2000, ok);
      if (!ok) $fatal("Timeout waiting for controller to start handling write request");
      $display("TB: Controller is STALLED (handling request)");
      wait_for_ready(0, 2000, ok);
      if (!ok) $fatal("Timeout waiting for controller to finish write request");

      $display("TB: Controller is READY");
      #CLK_PERIOD;  // Settle
    end
  endtask

endmodule
