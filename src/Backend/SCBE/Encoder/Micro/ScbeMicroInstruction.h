#pragma once
#include "Backend/SCBE/Encoder/ScbeCpu.h"

SWC_BEGIN_NAMESPACE();

enum class ScbeMicroOp : uint8_t
{
    OpBinaryRI,
    OpBinaryRR,
    OpBinaryMI,
    OpBinaryRM,
    OpBinaryMR,
};

struct ScbeMicroInstruction
{
    ScbeMicroOp op    = ScbeMicroOp::OpBinaryRI;
    CpuOp       cpuOp = CpuOp::ADD;
};

SWC_END_NAMESPACE();
