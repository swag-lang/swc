#pragma once

#include "Backend/Micro/MicroBuilder.h"

SWC_BEGIN_NAMESPACE();

class TaskContext;

struct MachineCode
{
    std::vector<std::byte>       bytes;
    std::vector<MicroRelocation> codeRelocations;

    void emit(TaskContext& ctx, MicroBuilder& builder);
};

SWC_END_NAMESPACE();
