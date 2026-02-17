#pragma once

#include "Backend/CodeGen/Micro/MicroBuilder.h"

SWC_BEGIN_NAMESPACE();

class TaskContext;

struct MachineCode
{
    std::vector<std::byte>       bytes;
    std::vector<MicroRelocation> codeRelocations;

    void emit(TaskContext& ctx, MicroInstrBuilder& builder);
};

SWC_END_NAMESPACE();
