#pragma once
#include "Support/Core/Result.h"
#include "Backend/Micro/MicroPass.h"

SWC_BEGIN_NAMESPACE();

// Pre-RA promotion of non-escaping scalar stack slots to virtual registers
// (a "mem2reg" pass).
//
// The front-end materializes every local as a stack slot accessed through the
// local frame-base register, so a local is reloaded from / stored to memory on
// every access. When a slot's address never escapes and it is only touched by
// fixed-width scalar load/store, we replace the memory traffic with a single
// virtual register; the rest of the pipeline (copy elimination, instruction
// combine, register allocation) then keeps the value in a register.
//
// The micro IR is non-SSA (a register is freely redefinable), so a promoted
// slot simply becomes a mutable virtual register: loads become register copies
// and stores become register writes. That rewrite is semantically faithful to
// memory, BUT promoting a *loop-carried* slot exposes the value to register
// optimizations (copy propagation, RA rematerialization) that make single-def
// assumptions across back-edges and silently miscompile it (this is exactly
// why the previous mem2reg was removed). To stay correct, this pass refuses to
// promote any slot whose value is live across a loop back-edge: such slots keep
// their memory form. Everything else — straight-line locals and loop-LOCAL
// temporaries (re-initialized each iteration) — is promoted.
class MicroMemToRegPass final : public MicroPass
{
public:
    std::string_view name() const override { return "mem-to-reg"; }
    Result           run(MicroPassContext& context) override;
};

SWC_END_NAMESPACE();
