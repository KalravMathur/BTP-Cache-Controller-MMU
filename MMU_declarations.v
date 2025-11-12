`ifndef MMU_DEFINES_V
`define MMU_DEFINES_V

// --- Address Sizes (configurable) ---
`define ADDR_WIDTH        32
`define PAGE_OFFSET_WIDTH 12 // 4KB pages
`define VPN_WIDTH         (`ADDR_WIDTH - `PAGE_OFFSET_WIDTH)
`define PFN_WIDTH         (`ADDR_WIDTH - `PAGE_OFFSET_WIDTH)

// --- TLB Configuration ---
`define NUM_TLB_ENTRIES   4
`define TLB_INDEX_WIDTH   2  // ceil(log2(NUM_TLB_ENTRIES))

// --- MMU Status Codes ---
`define MMU_STATUS_HIT          2'b00
`define MMU_STATUS_MISS         2'b01
`define MMU_STATUS_PAGE_FAULT   2'b10

`endif // MMU_DEFINES_V