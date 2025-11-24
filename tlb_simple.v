`timescale 1ns / 1ps
`include "mmu_params.v"

module tlb_simple (
    input wire clk,
    input wire rst_n,

    // --- Lookup Interface (Combinational) ---
    input wire [`VPN_WIDTH-1:0] lookup_vpn,
    output reg                lookup_hit,
    output reg [`PFN_WIDTH-1:0] lookup_pfn,

    // --- Refill Interface (Sequential) ---
    // In this simplified model, these are driven by the Testbench "backdoor"
    input wire                refill_en,
    input wire [`VPN_WIDTH-1:0] refill_vpn,
    input wire [`PFN_WIDTH-1:0] refill_pfn
);

    // Internal storage
    reg [`VPN_WIDTH-1:0] tag_mem [0:`TLB_ENTRIES-1];
    reg [`PFN_WIDTH-1:0] data_mem [0:`TLB_ENTRIES-1];
    reg                valid_mem [0:`TLB_ENTRIES-1];

    // Replacement Pointer (Round-Robin/FIFO)
    reg [`TLB_PER_BITS-1:0] replace_ptr;

    integer i;

    // =================================================================
    // 1. Combinational Lookup Logic (Fully Associative)
    // =================================================================
    always @(*) begin
        lookup_hit = 1'b0;
        lookup_pfn = {`PFN_WIDTH{1'b0}};

        for (i = 0; i < `TLB_ENTRIES; i = i + 1) begin
            // Check if entry is valid AND tags match
            if (valid_mem[i] && (tag_mem[i] == lookup_vpn)) begin
                lookup_hit = 1'b1;
                lookup_pfn = data_mem[i];
                // In fully associative, only one should match, so we can break
                // (though synthesis tools handle it without break too)
            end
        end
    end

    // =================================================================
    // 2. Sequential Update Logic (Refill and Pointer Update)
    // =================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            replace_ptr <= {`TLB_PER_BITS{1'b0}};
            for (i = 0; i < `TLB_ENTRIES; i = i + 1) begin
                valid_mem[i] <= 1'b0;
                tag_mem[i] <= {`VPN_WIDTH{1'b0}};
                data_mem[i] <= {`PFN_WIDTH{1'b0}};
            end
        end else begin
            if (refill_en) begin
                // Write data to the slot indicated by the pointer
                tag_mem[replace_ptr]   <= refill_vpn;
                data_mem[replace_ptr]  <= refill_pfn;
                valid_mem[replace_ptr] <= 1'b1;

                // Increment pointer, wrapping around (Round-Robin)
                replace_ptr <= replace_ptr + 1'b1;
            end
        end
    end

endmodule
