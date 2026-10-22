#pragma once

SWC_BEGIN_NAMESPACE();

struct MicroPassContext;

namespace SlpVectorize
{
    bool foldPackedLaneSubtracts(MicroPassContext& context);
    bool packRoots(MicroPassContext& context);
    bool exposeScalarValues(MicroPassContext& context);
}

SWC_END_NAMESPACE();
