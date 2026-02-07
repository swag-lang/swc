#pragma once
#include "Backend/MachineCode/Encoder/CpuEncoder.h"

SWC_BEGIN_NAMESPACE();

enum class MicroOp : uint8_t
{
    OpBinaryRI,
    OpBinaryRR,
    OpBinaryMI,
    OpBinaryRM,
    OpBinaryMR,
};

struct MicroInstruction
{
    MicroOp op    = MicroOp::OpBinaryRI;
    CpuOp       cpuOp = CpuOp::ADD;
};

SWC_END_NAMESPACE();

