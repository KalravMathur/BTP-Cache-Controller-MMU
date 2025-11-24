`ifndef MMU_PARAMS_VH
`define MMU_PARAMS_VH

// --- Architecture parameters ---
localparam ADDR_WIDTH = 32;
localparam PAGE_SIZE = 4096;     // 4KB
localparam OFFSET_BITS = $clog(PAGE_SIZE);     // log2(4096)

// derived parameters
localparam VPN_BITS = ADDR_WIDTH - OFFSET_BITS; // 32 - 12 = 20 bits
localparam PFN_BITS = ADDR_WIDTH - OFFSET_BITS; // 20 bits

// --- TLB parameters ---
localparam TLB_ENTRIES = 4; // Small fully associative TLB
// Bits needed for index pointer.
localparam TLB_PTR_BITS = $clog2(TLB_ENTRIES); // 2 bits for 4 entries

// --- Status Codes used in response ---
localparam STATUS_OK          = 2'b10; // Translation successful
// Other statuses unused in this simplified version but kept for compatibility

`endif
