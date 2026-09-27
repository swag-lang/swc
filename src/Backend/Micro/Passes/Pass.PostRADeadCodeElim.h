#pragma once
#include "Backend/Micro/MicroPass.h"
#include "Support/Core/Result.h"

SWC_BEGIN_NAMESPACE();

// Post-RA dead-code elimination on physical registers.
// Uses CFG-based backward liveness seeded at function exits with the ABI
// live-out set (return regs + callee-saves + stack/frame pointer) to find
// and erase side-effect-free instructions whose defined physical registers
// nobody reads.
// Before the prologue is built, callee-saved definitions need not be seeded:
// an unused definition should not force a save and restore into existence.
//
// Typical targets: rematerialized LoadRegReg copies left dead by register
// allocation, extends feeding an already-folded comparison, narrow moves
// where the destination is overwritten before any use.
class MicroPostRaDeadCodeElimPass final : public MicroPass
{
public:
    explicit MicroPostRaDeadCodeElimPass(bool beforePrologue = false) : beforePrologue_(beforePrologue) {}
    std::string_view name() const override { return beforePrologue_ ? "pre-prologue-dce" : "post-ra-dce"; }
    Result           run(MicroPassContext& context) override;

private:
    bool beforePrologue_ = false;
};

SWC_END_NAMESPACE();
