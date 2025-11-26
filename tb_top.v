`timescale 1ns / 1ps
`include "mmu_params.v"

module tb_system_top;

    // --- Parameters ---
    localparam CLK_PERIOD = 10;
    localparam MEM_LATENCY = 4; // Cycles for main memory response

    // --- DUT Signals ---
    reg clk;
    reg rst_n;

    // CPU Interface
    reg [31:0] cpu_va;
    reg [31:0] cpu_data_out;
    reg        cpu_read_req;
    reg        cpu_write_req;
    wire [31:0] cpu_data_in;
    wire        cpu_stall;
    wire        cache_hit_miss;

    // TLB Refill Interface
    wire                  tlb_miss_detected;
    reg                   tb_refill_en;
    reg [`VPN_WIDTH-1:0] tb_refill_vpn;
    reg [`PFN_WIDTH-1:0] tb_refill_pfn;

    // Main Memory Interface
    wire [31:0] main_mem_addr;
    wire [31:0] main_mem_data_out;
    wire        main_mem_read_req;
    wire        main_mem_write_req;
    reg  [31:0] main_mem_data_in;
    reg         main_mem_ready;

    // Cache RAM Interface (connecting to behavioral model)
    wire [5:0]   cache_mem_index;
    wire [511:0] cache_mem_data_in_net;
    wire         cache_mem_write_en;
    wire [511:0] cache_mem_data_out_net;

    // --- Testbench Memory Models ---
    // Simple Main Memory (associative array)
    reg [31:0] main_memory_model [int];

    // Simple Cache SRAM Model (64 sets, 512 bits per set)
    reg [511:0] cache_sram_model [0:63];
    integer i;

    // --- Instantiate DUT ---
    system_top u_dut (
        .clk(clk),
        .rst_n(rst_n),
        // CPU
        .cpu_va(cpu_va),
        .cpu_data_out(cpu_data_out),
        .cpu_read_req(cpu_read_req),
        .cpu_write_req(cpu_write_req),
        .cpu_data_in(cpu_data_in),
        .cpu_stall(cpu_stall),
        .cache_hit_miss(cache_hit_miss),
        // TLB Refill
        .tlb_miss_detected(tlb_miss_detected),
        .tb_refill_en(tb_refill_en),
        .tb_refill_vpn(tb_refill_vpn),
        .tb_refill_pfn(tb_refill_pfn),
        // Main Memory
        .main_mem_addr(main_mem_addr),
        .main_mem_data_out(main_mem_data_out),
        .main_mem_read_req(main_mem_read_req),
        .main_mem_write_req(main_mem_write_req),
        .main_mem_data_in(main_mem_data_in),
        .main_mem_ready(main_mem_ready),
        // Cache SRAM
        .cache_mem_index(cache_mem_index),
        .cache_mem_data_in(cache_mem_data_in_net),
        .cache_mem_write_en(cache_mem_write_en),
        .cache_mem_data_out(cache_mem_data_out_net)
    );

    // --- Cache SRAM Behavioral Model ---
    // Combinational Read
    assign cache_mem_data_out_net = cache_sram_model[cache_mem_index];
    // Sequential Write
    always @(posedge clk) begin
        if (cache_mem_write_en) begin
            cache_sram_model[cache_mem_index] <= cache_mem_data_in_net;
        end
    end

    // --- Clock Generation ---
    always #(CLK_PERIOD/2) clk = ~clk;

    // --- Helper Functions ---
    // VPN -> PFN mapping (simple offset)
    function [`PFN_WIDTH-1:0] get_expected_pfn(input [`VPN_WIDTH-1:0] vpn);
        get_expected_pfn = vpn + 20'hA0000;
    endfunction

    // PA -> Expected Data mapping (address itself)
    function [31:0] get_expected_data(input [31:0] pa);
        get_expected_data = pa;
    endfunction


    // =================================================================
    // Main Memory & TLB Refill Subsystem Model
    // =================================================================
    always @(posedge clk) begin
        // Defaults
        main_mem_ready <= 1'b0;
        tb_refill_en   <= 1'b0;

        // --- Handle TLB Misses ---
        if (rst_n && tlb_miss_detected && !tb_refill_en) begin
            $display("[PTW] TLB Miss for VA %h. Fetching translation...", cpu_va);
            tb_refill_vpn <= cpu_va[31:`OFFSET_BITS];
            tb_refill_pfn <= get_expected_pfn(cpu_va[31:`OFFSET_BITS]);
            repeat (MEM_LATENCY) @(posedge clk); // Simulate latency
            tb_refill_en <= 1'b1;
            $display("[PTW] TLB Refilled: VPN %h -> PFN %h", tb_refill_vpn, tb_refill_pfn);
        end

        // --- Handle Main Memory Requests ---
        if (rst_n && main_mem_read_req && !main_mem_ready) begin
            $display("[MEM] Read Request for PA %h", main_mem_addr);
            repeat (MEM_LATENCY) @(posedge clk);
            // Check if data exists in our mock memory, else return expected data
            if (main_memory_model.exists(main_mem_addr)) begin
                 main_mem_data_in <= main_memory_model[main_mem_addr];
            end else begin
                 main_mem_data_in <= get_expected_data(main_mem_addr);
            end
            main_mem_ready <= 1'b1;
            $display("[MEM] Read Data %h ready for PA %h", main_mem_data_in, main_mem_addr);
        end
        else if (rst_n && main_mem_write_req && !main_mem_ready) begin
            $display("[MEM] Write Request: Data %h to PA %h", main_mem_data_out, main_mem_addr);
            repeat (MEM_LATENCY) @(posedge clk);
            main_memory_model[main_mem_addr] = main_mem_data_out;
            main_mem_ready <= 1'b1;
            $display("[MEM] Write Complete.");
        end
    end


    // =================================================================
    // Main Test Stimulus
    // =================================================================
    initial begin
        // Initialize
        clk = 0; rst_n = 0;
        cpu_va = 0; cpu_data_out = 0;
        cpu_read_req = 0; cpu_write_req = 0;
        main_mem_data_in = 0; main_mem_ready = 0;
        tb_refill_en = 0; tb_refill_vpn = 0; tb_refill_pfn = 0;
        // Initialize Cache SRAM model with zeros
        for (i=0; i<64; i=i+1) cache_sram_model[i] = 512'b0;

        // Reset
        #(CLK_PERIOD*5); rst_n = 1; #(CLK_PERIOD*2);
        $display("=== Starting System Top Testbench ===");

        // --- Test Case 1: Cold Read (TLB Miss + Cache Miss) ---
        $display("\n[TEST 1] Cold Read: VA 0x0000_1000");
        cpu_drive_read(32'h0000_1000);
        // Expect: Stall for TLB refill, then stall for cache fetch.
        // Final data should be 0x000A_1000 (PFN A0000 + offset 000).

        // --- Test Case 2: Read Hit (TLB Hit + Cache Hit) ---
        $display("\n[TEST 2] Read Hit: VA 0x0000_1000");
        // We just read this, so it should be in TLB and Cache.
        cpu_drive_read(32'h0000_1000);
        // Expect: No stall, immediate hit, correct data.

        // --- Test Case 3: Write (TLB Hit + Write-Through) ---
        $display("\n[TEST 3] Write: Data 0xDEAD_BEEF to VA 0x0000_1004");
        // Same page as before, so TLB Hit.
        cpu_drive_write(32'h0000_1004, 32'hDEAD_BEEF);
        // Expect: Stall while writing to main memory. Cache line invalidated.

        // --- Test Case 4: Read after Write (TLB Hit + Cache Miss) ---
        $display("\n[TEST 4] Read back: VA 0x0000_1004");
        // Should be a cache miss because the write invalidated the line.
        cpu_drive_read(32'h0000_1004);
        // Expect: Stall for cache fetch from main memory. Data should be 0xDEAD_BEEF.

        // --- Test Case 5: New Page Read (TLB Miss + Cache Miss) ---
        $display("\n[TEST 5] New Page Read: VA 0x0000_2020");
        cpu_drive_read(32'h0000_2020);
        // Expect: TLB Refill, Cache fetch. Data: 0x000A_2020.

        #(CLK_PERIOD*10);
        $display("\n=== All Tests Completed Successfully ===");
        $finish;
    end

    // =================================================================
    // CPU Driver Tasks
    // =================================================================
    task cpu_drive_read;
        input [31:0] va;
        reg [31:0] expected_pa;
        reg [31:0] expected_data;
        begin
            // Calculate expectations
            expected_pa = {get_expected_pfn(va[31:`OFFSET_BITS]), va[`OFFSET_BITS-1:0]};
            // If we wrote to memory, expect that data, else expect default
            if (main_memory_model.exists(expected_pa))
                expected_data = main_memory_model[expected_pa];
            else
                expected_data = get_expected_data(expected_pa);

            @(posedge clk);
            cpu_va = va;
            cpu_read_req = 1'b1;

            $display("[CPU] Read Req: VA %h", va);

            // Wait for stall to clear
            wait(!cpu_stall);
            @(posedge clk); // Data is valid on the cycle *after* stall clears

            if (cpu_data_in === expected_data) begin
                $display("[PASS] Read VA %h -> Got Data %h (Hit/Miss: %b)",
                         va, cpu_data_in, cache_hit_miss);
            end else begin
                $display("[FAIL] Read VA %h -> Expected %h, Got %h",
                         va, expected_data, cpu_data_in);
                $stop;
            end
            cpu_read_req = 1'b0;
        end
    endtask

    task cpu_drive_write;
        input [31:0] va;
        input [31:0] data;
        begin
            @(posedge clk);
            cpu_va = va;
            cpu_data_out = data;
            cpu_write_req = 1'b1;
            $display("[CPU] Write Req: VA %h, Data %h", va, data);

            // Wait for stall to clear (write to main mem complete)
            wait(!cpu_stall);
            $display("[CPU] Write Complete.");
            @(posedge clk);
            cpu_write_req = 1'b0;
        end
    endtask

    // Safety timeout
    initial begin
        #(CLK_PERIOD * 1000);
        $display("\n[ERROR] Testbench timed out!");
        $finish;
    end

endmodule