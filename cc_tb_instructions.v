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

`timescale 1ns / 1ps

module tb_cache_controller;

    // --- Signals ---
    reg clk;
    reg rst_n;
    reg [31:0] phy_addr;
    reg [31:0] data_from_cpu;
    reg read_mem;
    reg write_mem;

    // Outputs from DUT
    wire [31:0] data_to_cpu;
    wire hit_miss;
    wire ready_stall;

    // Cache Memory Interface
    wire [5:0] cache_index;
    wire [511:0] cache_data_write;
    wire cache_write_en;
    wire [511:0] cache_data_read;

    // Main Memory Interface
    wire [31:0] main_mem_addr;
    wire [31:0] main_mem_data_out;
    wire main_mem_read_req;
    wire main_mem_write_req;
    reg [511:0] main_mem_data_in;
    reg main_mem_ready;

    // Verification Variables
    reg was_hit;
    integer file_handle;
    integer scan_result;
    reg [8*10:1] cmd;  // Stores "R" or "W"
    reg [31:0] file_addr;
    reg [31:0] file_data;
    integer instruction_count;

    // --- Clock Generation ---
    initial clk = 0;
    always #5 clk = ~clk;  // 10ns period

    // --- Instantiate Cache Controller (DUT) ---
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
        .cache_mem_index(cache_index),
        .cache_mem_data_in(cache_data_write),
        .cache_mem_write_en(cache_write_en),
        .cache_mem_data_out(cache_data_read),
        .main_mem_addr(main_mem_addr),
        .main_mem_data_out(main_mem_data_out),
        .main_mem_read_req(main_mem_read_req),
        .main_mem_write_req(main_mem_write_req),
        .main_mem_data_in(main_mem_data_in),
        .main_mem_ready(main_mem_ready)
    );

    // --- Instantiate Simple Cache Memory ---
    cache_mem l1_cache (
        .clk(clk),
        .index(cache_index),
        .data_in(cache_data_write),
        .write_en(cache_write_en),
        .data_out(cache_data_read),
        .way0_hit(dut.way0_hit),
        .way1_hit(dut.way1_hit),
        .lru_bit(dut.lru_store[cache_index])
    );

    // --- Main Test Sequence ---
    initial begin
        $display("\n========================================================");
        $display("            Cache Controller Verification");
        $display("========================================================");

        // 1. Initialize
        rst_n = 0;
        read_mem = 0;
        write_mem = 0;
        phy_addr = 0;
        data_from_cpu = 0;
        was_hit = 0;
        instruction_count = 0;
        main_mem_ready = 0;
        main_mem_data_in = 0;

        // 2. Reset
        #20 rst_n = 1;
        #10;
        $display("[TB] Reset Complete. Controller State: (%0d)", dut.state);

        // 3. Open Instruction File
        file_handle = $fopen("instructions.txt", "r");
        if (file_handle == 0) begin
            $display("[TB] ERROR: Could not open 'instructions.txt'. Make sure it exists.");
            $finish;
        end

        // 4. Parse Loop
        while (!$feof(
            file_handle
        )) begin
            // Read command (R/W) and Address
            scan_result = $fscanf(file_handle, "%s %h", cmd, file_addr);

            if (scan_result >= 2) begin  // Ensure we read at least cmd and addr
                instruction_count = instruction_count + 1;
                $display("\n--- Instruction #%0d ---", instruction_count);

                if (cmd == "R") begin
                    // Execute Read
                    $display("[TB] EXEC: READ  Addr: 0x%h", file_addr);
                    execute_read(file_addr);
                end else if (cmd == "W") begin
                    // For Write, we need to read one more value (Data)
                    scan_result = $fscanf(file_handle, "%h", file_data);
                    $display("[TB] EXEC: WRITE Addr: 0x%h Data: 0x%h", file_addr, file_data);
                    execute_write(file_addr, file_data);
                end else begin
                    // Handle comments or invalid lines gracefully (simplified)
                    // Note: $fscanf might get stuck on comments in complex files, 
                    // but for simple "R addr" this works.
                end
            end
        end

        $fclose(file_handle);
        $display("\n========================================================");
        $display("   Test Complete: %0d instructions executed.", instruction_count);
        $display("========================================================");
        $finish;
    end

    // --- Main Memory Simulation Logic (REAL MEMORY) ---
    // NOTE: SystemVerilog associative array for sparse memory
    // If using standard Verilog-2001, use a large reg array or $readmemh
    // Since VCS supports SV by default with .v files usually, we try SV associative.
    // If strict Verilog required, we can't simulate full 32-bit space easily.
    // We'll use a simplified approach: A modest array masked by lower bits.

    // 16KB Main Memory Model (simulating 32-bit address space with aliasing)
    reg [31:0] mm_storage[0:4095];

    reg [ 2:0] mm_state;
    localparam MM_IDLE = 0;
    localparam MM_READ_WAIT = 1;
    localparam MM_WRITE_WAIT = 2;
    localparam MM_DONE = 3;
    integer mm_counter;
    integer i;

    // Helper to build a 512-bit block from 16 words
    reg [511:0] temp_block;
    reg [31:0] base_word_addr;

    initial begin
        mm_state = MM_IDLE;
        // Initialize memory to 0
        for (i = 0; i < 4096; i = i + 1) mm_storage[i] = 32'hFFFF_FFFF;
    end

    always @(posedge clk) begin
        main_mem_ready <= 0;

        case (mm_state)
            MM_IDLE: begin
                if (main_mem_read_req) begin
                    $display("    [MainMem] Read Req -> Addr: %h", main_mem_addr);
                    mm_counter <= 0;
                    mm_state   <= MM_READ_WAIT;
                end else if (main_mem_write_req) begin
                    $display("    [MainMem] Write Req -> Addr: %h Data: %h", main_mem_addr,
                             main_mem_data_out);
                    mm_counter <= 0;
                    mm_state   <= MM_WRITE_WAIT;
                end
            end

            MM_READ_WAIT: begin
                mm_counter <= mm_counter + 1;
                if (mm_counter >= 3) begin
                    // Fetch 16 words to form a 512-bit block
                    // Align address to 64-byte boundary (lower 6 bits 0)
                    // Use lower 14 bits of address for our small 16KB array
                    base_word_addr = (main_mem_addr[13:0] & ~6'b111111) >> 2;

                    for (i = 0; i < 16; i = i + 1) begin
                        temp_block[(i*32)+:32] = mm_storage[base_word_addr+i];
                    end
                    main_mem_data_in <= temp_block;

                    mm_state <= MM_DONE;
                end
            end

            MM_WRITE_WAIT: begin
                mm_counter <= mm_counter + 1;
                if (mm_counter >= 3) begin
                    // Perform the write
                    // Use lower 14 bits for index
                    mm_storage[main_mem_addr[13:0]>>2] <= main_mem_data_out;
                    $display("    [MainMem] Stored %h at index %h", main_mem_data_out,
                             main_mem_addr[13:0] >> 2);

                    mm_state <= MM_DONE;
                end
            end

            MM_DONE: begin
                main_mem_ready <= 1;
                $display("    [MainMem] Ready asserted.");
                mm_state <= MM_IDLE;
            end
        endcase
    end

    // --- Tasks ---

    task execute_read(input [31:0] addr);
        begin
            phy_addr = addr;
            read_mem = 1;

            @(posedge clk);
            #1;
            was_hit  = hit_miss;
            read_mem = 0;

            wait_for_idle();
            print_result("READ ", addr);
        end
    endtask

    task execute_write(input [31:0] addr, input [31:0] data);
        begin
            phy_addr = addr;
            data_from_cpu = data;
            write_mem = 1;

            @(posedge clk);
            #1;
            was_hit   = hit_miss;
            write_mem = 0;

            wait_for_idle();
            print_result("WRITE", addr);
        end
    endtask

    task wait_for_idle;
        integer timeout;
        begin
            timeout = 0;
            while (ready_stall == 1 && timeout < 100) begin
                @(posedge clk);
                timeout = timeout + 1;
            end
            if (timeout == 100) $display("    [TB] WARNING: Timeout waiting for idle!");
            #5;
        end
    endtask

    task print_result(input [8*5:1] op_name, input [31:0] addr);
        begin
            $display("    [RESULT] %s @ %h | Status: %s | Data Out: %h | Set: %0d | Tag: %h",
                     op_name, addr, (was_hit ? "HIT " : "MISS"), data_to_cpu,
                     addr[11:6],  // Set Index
                     addr[31:12]  // Tag
            );
        end
    endtask

endmodule
