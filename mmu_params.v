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
`ifndef MMU_PARAMS_V
`define MMU_PARAMS_V

// --- Address Sizes (configurable) ---
`define ADDR_WIDTH 32
`define PAGE_SIZE 4096 //
// FIX: Changed $clog to $clog2
`define OFFSET_BITS $clog2(`PAGE_SIZE)
// FIX: Added backticks to internal usage for safety
`define VPN_WIDTH (`ADDR_WIDTH - `OFFSET_BITS)
`define PFN_WIDTH (`ADDR_WIDTH - `OFFSET_BITS)

// --- TLB Configuration ---
`define TLB_ENTRIES 4
// FIX: Added backticks for safety
`define TLB_PER_BITS $clog2(`TLB_ENTRIES)

// --- MMU Status Codes ---
`define STATUS_OK 2'b10 // Translation successful

`endif  // MMU_PARAMS_V
