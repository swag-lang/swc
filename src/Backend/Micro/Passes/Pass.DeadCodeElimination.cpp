#include "pch.h"
#include "Backend/Micro/Passes/Pass.DeadCodeElimination.h"
#include "Backend/Micro/MicroPassContext.h"
#include "Backend/Micro/Passes/Pass.DeadCodeElimination.Private.h"

// Eliminates side-effect-free instructions whose results are not live.
// Example: add r1, 4; ... (r1 never used) -> <remove add>.
// Example: mov r2, r3; ... (r2 never used) -> <remove mov>.
// This pass keeps memory/branch/call side effects intact.

SWC_BEGIN_NAMESPACE();

Result MicroDeadCodeEliminationPass::run(MicroPassContext& context)
{
    SWC_ASSERT(context.instructions != nullptr);
    SWC_ASSERT(context.operands != nullptr);

    lastPureDefByReg_.clear();
    lastPureDefByReg_.reserve(64);

    if (DeadCodeEliminationPass::runForwardPureDefElimination(context, lastPureDefByReg_))
        context.passChanged = true;

    if (DeadCodeEliminationPass::eliminateDeadPureDefsByBackwardLiveness(context, *context.instructions, *context.operands, context.encoder, context.callConvKind))
        context.passChanged = true;

    return Result::Continue;
}

SWC_END_NAMESPACE();
