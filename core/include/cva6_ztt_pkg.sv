//
// CVA6 Attached Matrix Extension (Ztt v0.6) Support
//
// MACH Research Lab
// Computer Science and Engineering
// Chalmers University of Technology & University of Gothenburg
//
// DARE SGA1 Project (European HPC Joint Undertaking Grant No 101202459)
//
// Copyright (C) 2026 André Fatela Carvalho
//

// Ztt v0.6 encodings and CSR addresses are provisional. Every value CVA6 needs
// to recognise AME instructions and CSRs lives here, so a spec update only
// touches this file. CVA6 does not execute AME instructions: they are
// offloaded to a coprocessor over CV-X-IF.
package cva6_ztt_pkg;
  //
  // Instructions
  //

  // Every AME instruction uses opcode CUSTOM-1 (0x2b) with funct3 = 000
  localparam logic [31:0] MASK_AME = 32'h0000707f;
  localparam logic [31:0] MATCH_AME = 32'h0000002b;

  // ame.acquire rd, rs1
  localparam logic [31:0] MASK_AME_ACQUIRE = 32'hfff0707f;
  localparam logic [31:0] MATCH_AME_ACQUIRE = 32'ha490002b;

  // ame.release
  localparam logic [31:0] MASK_AME_RELEASE = 32'hffffffff;
  localparam logic [31:0] MATCH_AME_RELEASE = 32'ha4a0002b;

  // Bit of the ame.acquire result that reports a successful acquisition
  localparam int unsigned ACQUIRE_SUCCESS_BIT = 0;


  //
  // CSRs
  //

  // CSR addresses
  localparam logic [11:0] CSR_ADDR_AMENLEN = 12'hCC0;
  localparam logic [11:0] CSR_ADDR_AMEUDSZ = 12'hCC1;
  localparam logic [11:0] CSR_ADDR_AMESTYPE = 12'hCC2;
  localparam logic [11:0] CSR_ADDR_AMEOWN = 12'hCC3;
  localparam logic [11:0] CSR_ADDR_AMEFFLAGS = 12'hCC4;
  localparam logic [11:0] CSR_ADDR_AMEXSAT = 12'hCC5;
  localparam logic [11:0] CSR_ADDR_AMESTATUS = 12'h800;


  //
  // Types
  //

  // MS state update requested by an offloaded instruction when it commits
  typedef enum logic [1:0] {
    AME_OP_NONE,     // not an AME instruction, or an AME CSR read
    AME_OP_ACQUIRE,  // ame.acquire: MS = Initial on a new grant
    AME_OP_RELEASE,  // ame.release: MS = Initial when owned
    AME_OP_DIRTY     // any other AME instruction or AME CSR write: MS = Dirty
  } ame_op_t;


  //
  // Helper Functions
  //

  // Returns whether an instruction is an AME instruction
  function automatic logic is_ame_instr(logic [31:0] instr);
    return (instr & MASK_AME) == MATCH_AME;
  endfunction

  // Returns whether an instruction is ame.acquire
  function automatic logic is_ame_acquire(logic [31:0] instr);
    return (instr & MASK_AME_ACQUIRE) == MATCH_AME_ACQUIRE;
  endfunction

  // Returns whether an instruction is ame.release
  function automatic logic is_ame_release(logic [31:0] instr);
    return (instr & MASK_AME_RELEASE) == MATCH_AME_RELEASE;
  endfunction

  // Returns whether a CSR address belongs to an AME CSR
  function automatic logic is_ame_csr(logic [11:0] addr);
    return addr inside {CSR_ADDR_AMENLEN, CSR_ADDR_AMEUDSZ, CSR_ADDR_AMESTYPE, CSR_ADDR_AMEOWN,
                        CSR_ADDR_AMEFFLAGS, CSR_ADDR_AMEXSAT, CSR_ADDR_AMESTATUS};
  endfunction
endpackage
