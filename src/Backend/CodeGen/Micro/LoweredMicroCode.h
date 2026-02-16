#pragma once

#include "Backend/CodeGen/Micro/MicroInstrBuilder.h"

SWC_BEGIN_NAMESPACE();

class TaskContext;

struct LoweredMicroCode
{
    std::vector<std::byte>                bytes;
    std::vector<MicroInstrCodeRelocation> codeRelocations;
};

void lowerMicroInstructions(TaskContext& ctx, MicroInstrBuilder& builder, LoweredMicroCode& outCode);

SWC_END_NAMESPACE();
