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
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 06.11.2025 13:27:03
// Design Name: 
// Module Name: TB_MMU
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
`include "mmu_params.v"

module tb_mmu_simple_top;

    // --- Parameters ---
    localparam CLK_PERIOD = 10;  // 100 MHz clock
    localparam MEM_LATENCY = 4;  // Cycles to simulate PTW fetching data

    // --- DUT Signals ---
    reg                    clk;
    reg                    rst_n;

    // CPU Interface
    reg  [`ADDR_WIDTH-1:0] cpu_req_va;
    reg                    cpu_req_valid;
    wire                   cpu_stall;

    // Cache Controller Interface
    wire [`ADDR_WIDTH-1:0] cache_pa;
    wire [            1:0] mmu_status;
    wire                   mmu_pa_valid;

    // PTW / Testbench Interface
    wire                   ptw_miss_detected;
    reg                    tb_refill_en;
    reg  [ `VPN_WIDTH-1:0] tb_refill_vpn;
    reg  [ `PFN_WIDTH-1:0] tb_refill_pfn;

    // --- Testbench Memory Map (VPN -> PFN) ---
    // Simple mapping: PFN = VPN + some offset for easy checking
    function [`PFN_WIDTH-1:0] get_expected_pfn(input [`VPN_WIDTH-1:0] vpn);
        get_expected_pfn = vpn + 20'hA0000;
    endfunction

    // --- Instantiate the Device Under Test (DUT) ---
    mmu_simple_top u_dut (
        .clk(clk),
        .rst_n(rst_n),
        // CPU
        .cpu_req_va(cpu_req_va),
        .cpu_req_valid(cpu_req_valid),
        .cpu_stall(cpu_stall),
        // Cache
        .cache_pa(cache_pa),
        .mmu_status(mmu_status),
        .mmu_pa_valid(mmu_pa_valid),
        // PTW/TB
        .ptw_miss_detected(ptw_miss_detected),
        .tb_refill_en(tb_refill_en),
        .tb_refill_vpn(tb_refill_vpn),
        .tb_refill_pfn(tb_refill_pfn)
    );

    // --- Clock Generation ---
    always #(CLK_PERIOD / 2) clk = ~clk;

    // =================================================================
    // PTW Request Handler (Simulates Memory Subsystem)
    // =================================================================
    // This block automatically monitors for misses and performs refills.
    always @(posedge clk) begin
        if (rst_n && ptw_miss_detected && !tb_refill_en) begin
            $display("[PTW] Miss detected for VPN %h. Starting fetch...",
                     cpu_req_va[`ADDR_WIDTH-1:`OFFSET_BITS]);

            // Extract VPN that caused the miss
            tb_refill_vpn <= cpu_req_va[`ADDR_WIDTH-1:`OFFSET_BITS];
            // Look up corresponding PFN from our testbench memory map
            tb_refill_pfn <= get_expected_pfn(cpu_req_va[`ADDR_WIDTH-1:`OFFSET_BITS]);

            // Simulate Memory Latency
            repeat (MEM_LATENCY) @(posedge clk);

            $display("[PTW] Fetch complete. Refilling TLB with VPN %h -> PFN %h", tb_refill_vpn,
                     tb_refill_pfn);

            // Assert refill signal for one clock cycle
            tb_refill_en <= 1'b1;
            @(posedge clk);
            tb_refill_en <= 1'b0;
        end  // Default state for refill enable
        else if (!ptw_miss_detected) begin
            tb_refill_en <= 1'b0;
        end
    end


    // =================================================================
    // Main Test Stimulus
    // =================================================================
    initial begin
        // 1. Initialize Signals
        clk = 0;
        rst_n = 0;
        cpu_req_va = 0;
        cpu_req_valid = 0;
        tb_refill_en = 0;
        tb_refill_vpn = 0;
        tb_refill_pfn = 0;

        $display("=== Starting MMU Simple Top Testbench ===");
        $display("TLB Entries: %0d, Replacement: Round-Robin", TLB_ENTRIES);

        // 2. Reset Sequence
        #(CLK_PERIOD * 5);
        rst_n = 1;
        #(CLK_PERIOD * 2);
        $display("[TEST] Reset complete.");

        // ============================================================
        // Test Case 1: Initial Misses and Fills
        // ============================================================
        $display("\n--- Test Case 1: Compulsory Misses & Fills ---");
        // Request 1: VA 0x10000 -> Should Miss
        send_cpu_req(32'h0001_0000);
        // Request 2: VA 0x20000 -> Should Miss
        send_cpu_req(32'h0002_0000);
        // Request 3: VA 0x30000 -> Should Miss
        send_cpu_req(32'h0003_0000);
        // Request 4: VA 0x40000 -> Should Miss (TLB now full)
        send_cpu_req(32'h0004_0000);

        #(CLK_PERIOD * 2);

        // ============================================================
        // Test Case 2: Hits on previously loaded entries
        // ============================================================
        $display("\n--- Test Case 2: Verifying Hits ---");
        // Re-Request 1: VA 0x10000 -> Should HIT immediately
        send_cpu_req(32'h0001_0000);
        // Re-Request 3: VA 0x30000 -> Should HIT immediately
        send_cpu_req(32'h0003_0000);

        #(CLK_PERIOD * 2);

        // ============================================================
        // Test Case 3: TLB Replacement (Round-Robin)
        // ============================================================
        $display("\n--- Test Case 3: TLB Replacement ---");
        // TLB contains VPNs: 0x10, 0x20, 0x30, 0x40. RR pointer should be at slot 0.

        // Request 5: VA 0x50000 -> New VPN. Should Miss and evict entry 0 (VPN 0x10).
        $display("[TEST] Requesting VA 0x50000 (Expecting eviction of 0x10000)");
        send_cpu_req(32'h0005_0000);

        // Verify eviction: Request VA 0x10000 again. It should now MISS.
        $display("[TEST] Re-requesting VA 0x10000 (Expecting MISS due to eviction)");
        send_cpu_req(32'h0001_0000);

        // Verify others are still there: Request VA 0x20000. Should HIT.
        $display("[TEST] Re-requesting VA 0x20000 (Should still HIT)");
        send_cpu_req(32'h0002_0000);

        #(CLK_PERIOD * 10);
        $display("\n=== All Tests Completed Successfully ===");
        $finish;
    end


    // =================================================================
    // Tasks for driver and monitor
    // =================================================================

    // Task to drive CPU requests and wait for completion
    task send_cpu_req;
        input [ADDR_WIDTH-1:0] va;
        reg [ VPN_WIDTH-1:0] expected_vpn;
        reg [ PFN_WIDTH-1:0] expected_pfn;
        reg [ADDR_WIDTH-1:0] expected_pa;
        begin
            // Calculate expected values
            expected_vpn = va[`ADDR_WIDTH-1:`OFFSET_BITS];
            expected_pfn = get_expected_pfn(expected_vpn);
            expected_pa  = {expected_pfn, va[`OFFSET_BITS-1:0]};

            // Drive Request at positive edge
            @(posedge clk);
            cpu_req_va = va;
            cpu_req_valid = 1'b1;

            // Check for immediate combinational Hit or Miss/Stall
            // Wait a small delay to allow combinational logic to settle after clock edge
            #1;
            if (cpu_stall) begin
                // It's a miss. We need to wait for the Stall to deassert.
                $display("[CPU] Request VA %h: Stall detected (Miss). Waiting...", va);
                // Keep request valid while stalled
                wait (!cpu_stall);
                $display("[CPU] Stall deasserted. Checking response...");
            end else if (mmu_pa_valid) begin
                $display("[CPU] Request VA %h: Immediate Hit detected.", va);
            end

            // At this point, stall is low, verify the valid response
            verify_response(expected_pa);

            // Deassert request on next clock cycle
            @(posedge clk);
            cpu_req_valid = 1'b0;
        end
    endtask

    // Task to verify MMU output
    task verify_response;
        input [`ADDR_WIDTH-1:0] exp_pa;
        begin
            // Ensure we are checking at a time when valid should be high and stall low
            if (mmu_pa_valid && !cpu_stall && mmu_status == STATUS_OK) begin
                if (cache_pa == exp_pa) begin
                    $display("[PASS] Got correctly translated PA: %h", cache_pa);
                end else begin
                    $display("[FAIL] PA Mismatch! Expected %h, Got %h", exp_pa, cache_pa);
                    $stop;
                end
            end else begin
                $display(
                    "[FAIL] Invalid response state! Valid=%b, Stall=%b, Status=%b (Expected 1, 0, OK)",
                    mmu_pa_valid, cpu_stall, mmu_status);
                $stop;
            end
        end
    endtask

    // Safety timeout
    initial begin
        #(CLK_PERIOD * 500);
        $display("\n[ERROR] Testbench timed out!");
        $finish;
    end

endmodule
