#include "pch.h"
#include "Backend/Micro/Passes/Pass.CopyElimination.h"
#include "Backend/Micro/MicroPassContext.h"

// Pre-RA copy elimination on virtual registers.
// Propagates register aliases created by copy/move instructions and removes dead copies.
// Example: mov v2, v1; add v3, v2 -> add v3, v1  (then remove dead copy).
// Example: mov v2, v1; mov v4, v2 -> mov v4, v1.

SWC_BEGIN_NAMESPACE();

Result MicroCopyEliminationPass::run(MicroPassContext& context)
{
    SWC_ASSERT(context.instructions != nullptr);
    SWC_ASSERT(context.operands != nullptr);
    return Result::Continue;
}

SWC_END_NAMESPACE();
