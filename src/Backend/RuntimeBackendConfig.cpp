#include "pch.h"
#include "Backend/RuntimeBackendConfig.h"
#include "Support/Core/ByteArray.h"

SWC_BEGIN_NAMESPACE();

void Runtime::BuildCfgBackend::appendCacheIdentity(ByteArray& bytes) const
{
    bytes.pushBack(static_cast<std::byte>(optimLevel));
    bytes.pushBack(static_cast<std::byte>(vectorize));
    bytes.pushBack(static_cast<std::byte>(debugInfo));
    bytes.pushBack(static_cast<std::byte>(enableExceptions));
    bytes.pushBack(static_cast<std::byte>(math.fma));
    bytes.pushBack(static_cast<std::byte>(math.noNaN));
    bytes.pushBack(static_cast<std::byte>(math.noInf));
    bytes.pushBack(static_cast<std::byte>(math.noSignedZero));
    bytes.pushBack(static_cast<std::byte>(math.unsafe));
    bytes.pushBack(static_cast<std::byte>(math.approxFunc));
    bytes.pushBack(static_cast<std::byte>(inlineMode));
    bytes.appendLe32(optimizer.iterations.preRaSweeps);
    bytes.appendLe32(optimizer.iterations.allocationSweeps);
    bytes.appendLe32(optimizer.iterations.postRaSweeps);
    bytes.appendLe32(optimizer.iterations.prePrologueSweeps);
    bytes.appendLe32(optimizer.iterations.branchThreadRounds);
    bytes.appendLe32(optimizer.iterations.inductionVariableRounds);
    bytes.appendLe32(optimizer.iterations.loopInvariantRounds);
    bytes.appendLe32(optimizer.iterations.sinkToUseRounds);
    bytes.appendLe32(optimizer.iterations.registerJoinRounds);
    bytes.appendLe32(optimizer.iterations.postRaHoistLevels);
    bytes.appendLe32(optimizer.unroll.memoryBytes);
    bytes.appendLe32(optimizer.unroll.maxTrips);
    bytes.appendLe32(optimizer.unroll.maxWideTableTrips);
    bytes.appendLe32(optimizer.unroll.maxBodyInstructions);
    bytes.appendLe32(optimizer.unroll.maxTotalInstructions);
    bytes.appendLe32(optimizer.unroll.maxOrdinaryBodyInstructions);
    bytes.appendLe32(optimizer.unroll.maxOrdinaryTotalInstructions);
    bytes.appendLe32(optimizer.unroll.maxBranchedTotalInstructions);
    bytes.appendLe32(optimizer.unroll.maxNestedTotalInstructions);
    bytes.appendLe32(optimizer.unroll.maxPartialBodyInstructions);
    bytes.appendLe32(optimizer.unroll.partialFactor);
    bytes.appendLe32(optimizer.unroll.initializerLookback);
    bytes.appendLe32(optimizer.unroll.sumInitializerLookback);
    bytes.appendLe32(optimizer.vectorization.maxPlanInstructions);
    bytes.appendLe32(optimizer.vectorization.maxTreeDepth);
    bytes.appendLe32(optimizer.vectorization.maxPromotedPerLoop);
}

SWC_END_NAMESPACE();
