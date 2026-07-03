#pragma once
#include "Backend/Runtime.h"

SWC_BEGIN_NAMESPACE();

class Sanitizer;
struct SanitizerState;
struct MicroInstr;
struct MicroInstrDef;
struct MicroInstrOperand;

// A single sanitizer check.
//
// The engine (`Sanitizer`) runs the shared abstract-interpretation data-flow to a
// fixpoint, then applies every enabled check to each reachable instruction against its
// converged incoming state. A check queries the tracked values through the engine and
// reports findings via `Sanitizer::report`. New checks are added by subclassing this
// and registering an instance in the sanity pass.
class SanitizerCheck
{
public:
    virtual ~SanitizerCheck() = default;

    // The runtime-safety guard this check belongs to; the check runs only when that
    // guard is enabled for the function (build-config default + `#[Swag.Safety]`).
    virtual Runtime::SafetyWhat safety() const = 0;

    // Inspect one instruction against its converged incoming state.
    virtual void run(Sanitizer& sanitizer, const SanitizerState& state, const MicroInstr& inst, const MicroInstrDef& def, const MicroInstrOperand* ops) = 0;
};

SWC_END_NAMESPACE();
