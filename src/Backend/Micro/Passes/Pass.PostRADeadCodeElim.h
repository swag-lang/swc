#pragma once
#include "Backend/Micro/MicroPass.h"

SWC_BEGIN_NAMESPACE();

// Post-RA dead-code elimination on physical registers.
// Uses CFG-based backward liveness seeded at function exits with the ABI
// live-out set (return regs + callee-saves + stack/frame pointer) to find
// and erase side-effect-free instructions whose defined physical registers
// nobody reads.
//
// Typical targets: rematerialized LoadRegReg copies left dead by register
// allocation, extends feeding an already-folded comparison, narrow moves
// where the destination is overwritten before any use.
class MicroPostRADeadCodeElimPass final : public MicroPass
{
public:
    std::string_view name() const override { return "post-ra-dce"; }
    Result           run(MicroPassContext& context) override;
};

SWC_END_NAMESPACE();
