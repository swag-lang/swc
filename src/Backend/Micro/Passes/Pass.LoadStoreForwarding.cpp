#include "pch.h"
#include "Backend/Micro/Passes/Pass.LoadStoreForwarding.h"
#include "Backend/Micro/MicroPassContext.h"
#include "Backend/Micro/Passes/Pass.LoadStoreForwarding.Private.h"

// Forwards recent store values into matching following loads.
// Example: store [rbp+8], r1; load r2, [rbp+8] -> mov r2, r1.
// Example: store [rbp+8], 5;  load r2, [rbp+8] -> load r2, 5.
// This removes redundant memory traffic when aliasing is provably safe.

SWC_BEGIN_NAMESPACE();

Result MicroLoadStoreForwardingPass::run(MicroPassContext& context)
{
    SWC_ASSERT(context.instructions != nullptr);
    SWC_ASSERT(context.operands != nullptr);

    const bool forwardedAny = LoadStoreForwardingPass::runForwardStoreToLoad(context);
    const bool promotedAny  = LoadStoreForwardingPass::promoteStackSlotLoads(context);
    if (forwardedAny || promotedAny)
        context.passChanged = true;

    return Result::Continue;
}

SWC_END_NAMESPACE();
