#pragma once

#include "Backend/CodeGen/Micro/MicroInstrBuilder.h"

SWC_BEGIN_NAMESPACE();

class TaskContext;

struct MachineCode
{
    std::vector<std::byte>                bytes;
    std::vector<MicroInstrRelocation> codeRelocations;

    void emit(TaskContext& ctx, MicroInstrBuilder& builder);
};

SWC_END_NAMESPACE();
