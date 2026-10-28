# CVA6 with Attached Matrix Extension (Ztt v0.6) Support

This fork adds the core-side support needed to drive any Ztt v0.6 (Attached
Matrix Extension, AME) coprocessor from CVA6. The coprocessor is attached over
CV-X-IF, which remains the **only** interface between the core and the matrix
unit: no extra ports, no changes to the CV-X-IF protocol.

The first user is the MMAU (MACH Research Lab, DARE SGA1), which depends on this
fork. Everything MMAU-specific lives in the MMAU repository.

> **Status:** implemented but **not yet compiled or simulated**. The first build
> happens in the MMAU integration. See [Status and next steps](#status-and-next-steps).


## Enabling

Set both flags in the CVA6 configuration package:

```systemverilog
CvxifEn: bit'(1),
ZttEn:   bit'(1),
```

`config_pkg::check_cfg` asserts that `ZttEn` requires `CvxifEn`. Every config
shipped in this repository sets `ZttEn: bit'(0)`. With `ZttEn = 0` the core
behaves exactly as upstream CVA6.


## What the core does

The core never executes AME instructions. It only does what the spec requires
from the hart:

1. **MS state field.** `MS[1:0]` (Off / Initial / Clean / Dirty) in `mstatus`,
   `sstatus` and `vsstatus`, at bits **26:25**. It follows the FS/VS model and
   feeds `SD`. Bits 24:23 were avoided because they are now used by the ratified
   `SDT` (Ssdbltrp) and `SPELP` (Zicfilp). MS resets to Off.
2. **Trap while Off.** When MS is Off (or `vsstatus.MS` is Off with V=1), AME
   instructions and AME CSR accesses raise an illegal-instruction exception in
   the decoder and are **not** offloaded.
3. **Offload AME CSR accesses.** CSR instructions targeting AME CSR addresses
   are sent to the coprocessor over CV-X-IF instead of the CVA6 CSR unit.
   AME instructions (CUSTOM-1) already reach CV-X-IF as unknown instructions.
4. **Track MS on commit.** Offloaded AME instructions are tagged in the
   decoder, and the CSR file updates MS when they retire:

   | Retiring instruction | Condition | Effect |
   |---|---|---|
   | `ame.acquire` | result bit 0 set and not owned | MS = Initial, OWNED = 1 |
   | `ame.acquire` | already owned | none |
   | `ame.release` | owned | MS = Initial, OWNED = 0 |
   | `ame.release` | not owned | none |
   | other AME instruction | | MS = Dirty |
   | AME CSR write | | MS = Dirty |
   | AME CSR read | | none |

   With V=1 the update also applies to `vsstatus.MS`. OWNED is a core-side copy
   of the ownership state, rebuilt only from committed acquire/release results.
5. **MS cannot be turned Off while owned.** A write to `mstatus`, `sstatus` or
   `vsstatus` that sets MS = Off while OWNED = 1 is discarded and raises an
   illegal-instruction exception.

An AME CSR write counts as one where the CSR instruction writes: `CSRRW`/`CSRRWI`
always, `CSRRS`/`CSRRC`/`CSRRSI`/`CSRRCI` only with a non-zero `rs1`/`uimm`.


## Coprocessor contract

What an AME coprocessor must do when attached to this core:

- **Ownership and acceptance.** Keep its own OWNED state and accept or reject
  each CV-X-IF issue request. A rejection becomes an illegal-instruction trap
  in the core. The core does not check ownership before offloading.
- **ame.acquire result.** Write the result to `rd`. Bit 0 is SUCCESS. The
  core reads this bit at commit.
- **AME CSRs.** Decode Zicsr itself for the AME CSR addresses, including the
  immediate forms: the core forwards the raw instruction and the `rs1` register
  value, and does not substitute `uimm`. Return the old CSR value in `rd` for
  accepted accesses, and reject writes to read-only CSRs.
- **Memory.** Make matrix loads and stores visible to the core before it
  executes the fence that software uses to order them, for example by
  completing a store only after the AXI write response.


## Limitations

- **Bare metal only.** The coprocessor accesses memory with physical
  addresses. There is no address translation, PMP check or precise memory
  fault for matrix loads and stores.
- **Software coherence.** Ordering and coherence between the core caches and
  the coprocessor memory path are handled with software fences, not hardware.
- **Single hart.** OWNED is one bit per core. No multi-hart arbitration.


## Encodings and CSR addresses

Ztt v0.6 is not ratified, so all encodings and addresses are kept in one place,
[`core/include/cva6_ztt_pkg.sv`](core/include/cva6_ztt_pkg.sv). A spec update
should only need changes there.

| Item | Value |
|---|---|
| AME instructions | opcode CUSTOM-1 (`0x2b`), funct3 = `000` |
| `ame.acquire rd, rs1` | match `0xa490002b`, mask `0xfff0707f` |
| `ame.release` | match `0xa4a0002b`, mask `0xffffffff` |
| AME CSRs | `0xCC0`–`0xCC5`, `0x800` |

**Spec issue to report.** Writable CSRs `0xCC2`, `0xCC4` and `0xCC5` sit in the
`0xCxx` range, which the privileged spec reserves for read-only user CSRs.
CVA6 does not enforce this for AME CSRs, because they bypass its CSR unit.


## Changed files

| File | Change |
|---|---|
| `core/include/cva6_ztt_pkg.sv` | new: encodings, CSR addresses, helpers, `ame_op_t` |
| `core/include/config_pkg.sv`, `build_config_pkg.sv` | `ZttEn` flag and config check |
| `core/include/*_config_pkg.sv` and other config packages | `ZttEn: bit'(0)` |
| `core/include/riscv_pkg.sv` | MS field in `mstatus_rv_t` / `sstatus_rv_t`, `SSTATUS_MS` |
| `core/include/ariane_pkg.sv` | MS in the S-mode status read/write masks |
| `core/csr_regfile.sv` | MS state, SD, OWNED copy, MS updates on commit, MS Off check, `ms_o` / `vms_o` |
| `core/decoder.sv` | trap while Off, AME CSR offload, `ame_op` tagging |
| `core/commit_stage.sv` | reports `ame_op` and the acquire result at commit |
| `core/id_stage.sv`, `core/cva6.sv` | wiring; `ame_op` field in `scoreboard_entry_t` |
| `Bender.yml`, `Flist.ariane`, `core/Flist.cva6`, `src_files.yml` | add `cva6_ztt_pkg.sv` after `riscv_pkg.sv` |


## Status and next steps

- [ ] **Compile and elaborate** with `ZttEn = 1` and `ZttEn = 0` (Verilator lint
  or slang). Nothing has been built yet.
- [ ] **Integrate in the MMAU** with a config that sets `CvxifEn = 1` and
  `ZttEn = 1`, then check that:
  - AME instructions and AME CSR accesses trap while MS is Off and never reach
    CV-X-IF;
  - acquire sets MS to Initial, AME operations set Dirty, release sets Initial;
  - writing MS = Off while owned traps.
- [ ] Optional: standalone tests with a stub coprocessor based on
  `core/cvxif_example`, and an upstream regression with `ZttEn = 0`.
