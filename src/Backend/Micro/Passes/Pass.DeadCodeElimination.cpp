#include "pch.h"
#include "Backend/Micro/Passes/Pass.DeadCodeElimination.h"
#include "Backend/Micro/MicroPassContext.h"
#include "Support/Memory/MemoryProfile.h"

// Eliminates side-effect-free instructions whose results are not live.
// Example: add r1, 4; ... (r1 never used) -> <remove add>.
// Example: mov r2, r3; ... (r2 never used) -> <remove mov>.
// This pass keeps memory/branch/call side effects intact.

SWC_BEGIN_NAMESPACE();

void MicroDeadCodeEliminationPass::initRunState(MicroPassContext& context)
{
    context_                 = &context;
    storage_                 = context.instructions;
    operands_                = context.operands;
    encoder_                 = context.encoder;
    callConvKind_            = context.callConvKind;
    usesIntReturnRegOnRet_   = context.usesIntReturnRegOnRet;
    usesFloatReturnRegOnRet_ = context.usesFloatReturnRegOnRet;
}

Result MicroDeadCodeEliminationPass::run(MicroPassContext& context)
{
    SWC_MEM_SCOPE("Backend/MicroLower/DCE");
    SWC_ASSERT(context.instructions != nullptr);
    SWC_ASSERT(context.operands != nullptr);

    initRunState(context);
    lastPureDefByReg_.clear();
    lastPureDefByReg_.reserve(64);

    if (runForwardPureDefElimination())
        context.passChanged = true;

    if (eliminateDeadPureDefsByBackwardLiveness())
        context.passChanged = true;

    return Result::Continue;
}

SWC_END_NAMESPACE();
