#include "pch.h"
#include "Backend/Micro/Passes/Pass.LoadStoreForwarding.h"
#include "Backend/Micro/MicroPassContext.h"
#include "Backend/Micro/MicroPassHelpers.h"
#include "Support/Memory/MemoryProfile.h"

// Forwards recent store values into matching following loads.
// Example: store [rbp+8], r1; load r2, [rbp+8] -> mov r2, r1.
// Example: store [rbp+8], 5;  load r2, [rbp+8] -> load r2, 5.
// This removes redundant memory traffic when aliasing is provably safe.

SWC_BEGIN_NAMESPACE();

void MicroLoadStoreForwardingPass::initRunState(MicroPassContext& context)
{
    context_  = &context;
    storage_  = context.instructions;
    operands_ = context.operands;
    referencedLabels_.clear();
    referencedLabels_.reserve(storage_->count());
    MicroPassHelpers::collectReferencedLabels(*storage_, *operands_, referencedLabels_, true);
}

Result MicroLoadStoreForwardingPass::run(MicroPassContext& context)
{
    SWC_MEM_SCOPE("Backend/MicroLower/LoadStoreFwd");
    SWC_ASSERT(context.instructions != nullptr);
    SWC_ASSERT(context.operands != nullptr);

    initRunState(context);

    const bool forwardedAny = runForwardStoreToLoad();
    const bool promotedAny  = promoteStackSlotLoads();
    if (forwardedAny || promotedAny)
        context.passChanged = true;

    return Result::Continue;
}

SWC_END_NAMESPACE();
