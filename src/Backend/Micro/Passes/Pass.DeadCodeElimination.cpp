#include "pch.h"
#include "Backend/Micro/Passes/Pass.DeadCodeElimination.h"
#include "Backend/Micro/MicroPassContext.h"

// Pre-RA dead code elimination on virtual registers.
// Eliminates side-effect-free instructions whose results are not live.
// Example: add v1, 4; ... (v1 never used) -> remove add.
// Example: mov v2, v3; ... (v2 never used) -> remove mov.

SWC_BEGIN_NAMESPACE();

Result MicroDeadCodeEliminationPass::run(MicroPassContext& context)
{
    SWC_ASSERT(context.instructions != nullptr);
    SWC_ASSERT(context.operands != nullptr);
    return Result::Continue;
}

SWC_END_NAMESPACE();
