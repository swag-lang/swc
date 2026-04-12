#include "pch.h"
#include "Backend/Micro/Passes/Pass.InstructionCombine.h"
#include "Backend/Micro/MicroPassContext.h"

// Pre-RA instruction combining on virtual registers.
// Combines nearby immediate ops on the same destination into one op.
// Example: add v1, 2; add v1, 3  ->  add v1, 5.
// Example: load v1, [base+8]; op v1; store [base+8], v1  ->  op [base+8].

SWC_BEGIN_NAMESPACE();

Result MicroInstructionCombinePass::run(MicroPassContext& context)
{
    SWC_ASSERT(context.instructions != nullptr);
    SWC_ASSERT(context.operands != nullptr);
    return Result::Continue;
}

SWC_END_NAMESPACE();
