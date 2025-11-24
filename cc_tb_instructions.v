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

    wire [31:0] data_to_cpu;
    wire hit_miss;
    wire ready_stall;

    wire [5:0] cache_index;
    wire [511:0] cache_data_write;
    wire cache_write_en;
    wire [511:0] cache_data_read;

    wire [31:0] main_mem_addr;
    wire [31:0] main_mem_data_out;
    wire main_mem_read_req;
    wire main_mem_write_req;
    reg [511:0] main_mem_data_in;
    reg main_mem_ready;

    reg is_hit_result;
    integer file_handle;
    integer scan_result;
    reg [8*10:1] cmd;
    reg [31:0] file_addr;
    reg [31:0] file_data;
    integer instruction_count;

    initial clk = 0;
    always #5 clk = ~clk;

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

    // --- Main Memory Model (16KB Real Storage) ---
    reg [31:0] mm_storage[0:4095];
    reg [ 2:0] mm_state;
    localparam MM_IDLE = 0, MM_READ_WAIT = 1, MM_WRITE_WAIT = 2, MM_DONE = 3;
    integer mm_cnt;
    integer k;
    reg [511:0] temp_blk;
    reg [31:0] base_addr;

    // ** FIX: Latch address and data from bus **
    reg [31:0] latched_addr;
    reg [31:0] latched_data_in;

    initial begin
        mm_state = MM_IDLE;
        for (k = 0; k < 4096; k = k + 1) mm_storage[k] = 0;
    end

    always @(posedge clk) begin
        main_mem_ready <= 0;
        case (mm_state)
            MM_IDLE: begin
                if (main_mem_read_req) begin
                    latched_addr <= main_mem_addr;  // Capture Address
                    $display("    [MainMem] Read Req -> Addr: %h", main_mem_addr);
                    mm_cnt   <= 0;
                    mm_state <= MM_READ_WAIT;
                end else if (main_mem_write_req) begin
                    latched_addr <= main_mem_addr;  // Capture Address
                    latched_data_in <= main_mem_data_out;  // Capture Data
                    $display("    [MainMem] Write Req -> Addr: %h Data: %h", main_mem_addr,
                             main_mem_data_out);
                    mm_cnt   <= 0;
                    mm_state <= MM_WRITE_WAIT;
                end
            end
            MM_READ_WAIT: begin
                mm_cnt <= mm_cnt + 1;
                if (mm_cnt >= 3) begin
                    // Use LATCHED address for read
                    base_addr = (latched_addr[13:0] & 14'h3FC0) >> 2;
                    for (k = 0; k < 16; k = k + 1) temp_blk[k*32+:32] = mm_storage[base_addr+k];
                    main_mem_data_in <= temp_blk;
                    mm_state <= MM_DONE;
                end
            end
            MM_WRITE_WAIT: begin
                mm_cnt <= mm_cnt + 1;
                if (mm_cnt >= 3) begin
                    // Use LATCHED address and data for write
                    mm_storage[latched_addr[13:0]>>2] <= latched_data_in;
                    $display("    [MainMem] Stored %h at index %h", latched_data_in,
                             latched_addr[13:0] >> 2);
                    mm_state <= MM_DONE;
                end
            end
            MM_DONE: begin
                main_mem_ready <= 1;
                mm_state <= MM_IDLE;
            end
        endcase
    end

    // --- Tasks ---
    task execute_read(input [31:0] addr);
        begin
            phy_addr = addr;
            read_mem = 1;
            #1;  // Setup time
            @(posedge clk);

            // Check Hit/Miss immediately after request clock edge
            #1;
            if (ready_stall == 1) is_hit_result = 0;
            else is_hit_result = 1;

            read_mem = 0;
            wait_for_idle();
            print_result("READ ", addr);
        end
    endtask

    task execute_write(input [31:0] addr, input [31:0] data);
        begin
            phy_addr = addr;
            data_from_cpu = data;

            #5;  // Data setup
            write_mem = 1;
            @(posedge clk);

            is_hit_result = 1;  // Writes are accepted

            write_mem = 0;
            wait_for_idle();
            print_result("WRITE", addr);
        end
    endtask

    task wait_for_idle;
        integer t;
        begin
            t = 0;
            while (ready_stall == 1 && t < 500) begin
                @(posedge clk);
                t = t + 1;
            end
            if (t == 500) $display("    [TB] WARNING: Timeout waiting for idle!");
            #5;
        end
    endtask

    task print_result(input [8*5:1] op, input [31:0] adr);
        begin
            $display("    [RESULT] %s @ %h | Status: %s | Data Out: %h | Set: %0d | Tag: %h", op,
                     adr, (is_hit_result ? "HIT " : "MISS"), data_to_cpu, adr[11:6], adr[31:12]);
        end
    endtask

    // --- Main Execution ---
    initial begin
        $display("\n========================================================");
        $display("   Script-Driven Cache Controller Verification");
        $display("========================================================");

        rst_n = 0;
        read_mem = 0;
        write_mem = 0;
        phy_addr = 0;
        data_from_cpu = 0;
        is_hit_result = 0;
        instruction_count = 0;
        main_mem_ready = 0;
        main_mem_data_in = 0;

        #20 rst_n = 1;
        #10;
        $display("[TB] Reset Complete.");

        file_handle = $fopen("instructions.txt", "r");
        if (file_handle == 0) begin
            $display("[TB] ERROR: Could not open 'instructions.txt'.");
            $finish;
        end

        while (!$feof(
            file_handle
        )) begin
            scan_result = $fscanf(file_handle, "%s %h", cmd, file_addr);
            if (scan_result >= 2) begin
                instruction_count = instruction_count + 1;
                $display("\n--- Instruction #%0d ---", instruction_count);

                if (cmd == "R") begin
                    $display("[TB] EXEC: READ  Addr: 0x%h", file_addr);
                    execute_read(file_addr);
                end else if (cmd == "W") begin
                    scan_result = $fscanf(file_handle, "%h", file_data);
                    $display("[TB] EXEC: WRITE Addr: 0x%h Data: 0x%h", file_addr, file_data);
                    execute_write(file_addr, file_data);
                end
            end
        end

        $fclose(file_handle);
        $display("\n========================================================");
        $display("   Test Complete: %0d instructions executed.", instruction_count);
        $display("========================================================");
        $finish;
    end

endmodule
