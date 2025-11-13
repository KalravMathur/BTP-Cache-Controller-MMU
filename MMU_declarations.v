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
// ------------ ---------------------- ------------------------------------------
//
////////////////////////////////////////////////////////////////////////////////
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