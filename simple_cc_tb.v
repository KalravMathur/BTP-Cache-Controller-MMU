`timescale 1ns / 1ps

module tb_cache_controller_unit;

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
    wire [31:0] main_mem_data_out;  // Data FROM controller TO main mem
    wire main_mem_read_req;
    wire main_mem_write_req;
    reg [511:0] main_mem_data_in;  // Data FROM main mem TO controller
    reg main_mem_ready;

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

        // Cache Mem Interface
        .cache_mem_index(cache_index),
        .cache_mem_data_in(cache_data_write),
        .cache_mem_write_en(cache_write_en),
        .cache_mem_data_out(cache_data_read),

        // Main Mem Interface
        .main_mem_addr(main_mem_addr),
        .main_mem_data_out(main_mem_data_out),
        .main_mem_read_req(main_mem_read_req),
        .main_mem_write_req(main_mem_write_req),
        .main_mem_data_in(main_mem_data_in),
        .main_mem_ready(main_mem_ready)
    );

    // --- Instantiate Simple Cache Memory ---
    // Note: We tap into internal DUT signals for the "cheat" logic
    cache_mem l1_cache (
        .clk(clk),
        .index(cache_index),
        .data_in(cache_data_write),
        .write_en(cache_write_en),
        .data_out(cache_data_read),
        .way0_hit(dut.way0_hit),
        .way1_hit(dut.way1_hit),
        .lru_bit(dut.lru_store[cache_index])  // Pass the LRU bit for the current set
    );

    // --- Main Test Sequence ---
    initial begin
        // 1. Initialize
        $display("\n=== Starting Simple Cache Controller Test ===");
        rst_n = 0;
        read_mem = 0;
        write_mem = 0;
        phy_addr = 0;
        data_from_cpu = 0;
        main_mem_ready = 0;
        main_mem_data_in = 0;

        // 2. Reset
        #20 rst_n = 1;
        #10;
        $display("Reset Complete. Controller State: %0d", dut.state);

        // -------------------------------------------------------
        // TEST 1: Read Miss (Addr: 0x1000)
        // -------------------------------------------------------
        $display("\n--- Test 1: Read Request @ 0x1000 (Expect MISS) ---");
        send_read_req(32'h00001000);

        // Wait for processing and print result
        wait_for_idle();
        print_status("Test 1 Result");

        // -------------------------------------------------------
        // TEST 2: Read Hit (Addr: 0x1000)
        // -------------------------------------------------------
        $display("\n--- Test 2: Read Request @ 0x1000 (Expect HIT) ---");
        send_read_req(32'h00001000);

        // For a hit, ready_stall might not go high long enough to catch with a slow wait
        // We just wait a few cycles
        #20;
        print_status("Test 2 Result");

        // -------------------------------------------------------
        // TEST 3: Read Miss (New Set) (Addr: 0x2000)
        // -------------------------------------------------------
        $display("\n--- Test 3: Read Request @ 0x2000 (Expect MISS) ---");
        send_read_req(32'h00002000);
        wait_for_idle();
        print_status("Test 3 Result");

        // -------------------------------------------------------
        // TEST 4: Write Request (Write-Through) (Addr: 0x2000)
        // -------------------------------------------------------
        $display("\n--- Test 4: Write Request @ 0x2000 (Data: 0xDEADBEEF) ---");
        send_write_req(32'h00002000, 32'hDEADBEEF);
        wait_for_idle();
        print_status("Test 4 Result");

        // -------------------------------------------------------
        // TEST 5: Read Hit Check Data (Addr: 0x2000)
        // -------------------------------------------------------
        $display("\n--- Test 5: Read Request @ 0x2000 (Check Data) ---");
        send_read_req(32'h00002000);
        #20;
        print_status("Test 5 Result");

        $display("\n=== Test Complete ===");
        $finish;
    end

    // --- Main Memory Simulation Logic ---
    // This block simply waits for a request from the controller, waits a bit, 
    // and then asserts 'ready'.
    always @(posedge clk) begin
        main_mem_ready <= 0;  // Default

        if (main_mem_read_req) begin
            $display("[MainMem] Read Request received for Addr: %h", main_mem_addr);
            #30;  // Simulate latency
            // Return some identifiable dummy data: {Addr, Addr...}
            main_mem_data_in <= {16{main_mem_addr}};
            main_mem_ready   <= 1;
            $display("[MainMem] Data sent: %h", {16{main_mem_addr}});
        end

        if (main_mem_write_req) begin
            $display("[MainMem] Write Request received for Addr: %h, Data: %h", main_mem_addr,
                     main_mem_data_out);
            #30;  // Simulate latency
            main_mem_ready <= 1;
            $display("[MainMem] Write Acknowledge sent");
        end
    end

    // --- Helper Tasks ---

    task send_read_req(input [31:0] addr);
        begin
            phy_addr = addr;
            read_mem = 1;
            #10;  // Hold for 1 cycle
            read_mem = 0;
        end
    endtask

    task send_write_req(input [31:0] addr, input [31:0] data);
        begin
            phy_addr = addr;
            data_from_cpu = data;
            write_mem = 1;
            #10;
            write_mem = 0;
        end
    endtask

    task wait_for_idle;
        begin
            // Wait until the controller is no longer stalled
            wait (ready_stall == 1);  // Wait for it to start working
            wait (ready_stall == 0);  // Wait for it to finish
            #5;
        end
    endtask

    task print_status(input [100*8:1] label);
        begin
            $display("%s -> Hit: %b | Data Out: %h | Stall: %b | State: %0d", label, hit_miss,
                     data_to_cpu, ready_stall, dut.state);
        end
    endtask

endmodule
