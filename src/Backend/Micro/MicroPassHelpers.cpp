#include "pch.h"
#include "Backend/Micro/MicroPassHelpers.h"
#include "Backend/Encoder/Encoder.h"
#include "Backend/Micro/MicroPassContext.h"

SWC_BEGIN_NAMESPACE();

bool MicroPassHelpers::violatesEncoderConformance(const MicroPassContext& context, const MicroInstr& inst, const MicroInstrOperand* ops)
{
    if (!context.encoder || !ops)
        return false;

    MicroConformanceIssue issue;
    return context.encoder->queryConformanceIssue(issue, inst, ops);
}

SWC_END_NAMESPACE();
