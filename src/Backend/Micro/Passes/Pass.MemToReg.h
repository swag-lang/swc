#pragma once
#include "Backend/Micro/MicroPass.h"

SWC_BEGIN_NAMESPACE();

// Pre-RA promotion of non-escaping scalar integer stack slots to virtual
// registers (a "mem2reg" pass).
//
// The front-end materializes every local as a stack slot accessed through the
// local frame-base register, so a loop variable is reloaded and stored to
// memory on every iteration. When a slot's address never escapes and it is only
// touched by fixed-width scalar load/store, we replace the memory traffic with a
// single virtual register. The register allocator's pinning of loop-carried
// values then keeps the promoted register resident across CFG boundaries.
//
// The IR is non-SSA (registers are freely redefinable; phis are an analysis
// overlay), so a promoted slot simply becomes a mutable virtual register.
class MicroMemToRegPass final : public MicroPass
{
public:
    std::string_view name() const override { return "mem-to-reg"; }
    Result           run(MicroPassContext& context) override;
};

SWC_END_NAMESPACE();
