#pragma once
#include "Backend/MachineCode/Encoder/CpuEncoder.h"

SWC_BEGIN_NAMESPACE();

enum class MicroOp : uint8_t
{
    OpBinaryRi,
    OpBinaryRr,
    OpBinaryMi,
    OpBinaryRm,
    OpBinaryMr,
};

struct MicroInstruction
{
    MicroOp op    = MicroOp::OpBinaryRi;
    CpuOp   cpuOp = CpuOp::ADD;
};

SWC_END_NAMESPACE();
