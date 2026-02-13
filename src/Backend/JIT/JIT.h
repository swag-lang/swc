#pragma once
#include "Backend/MachineCode/Micro/MicroInstrBuilder.h"
#include "Support/Core/Result.h"

SWC_BEGIN_NAMESPACE();

class TaskContext;
class JITExecMemory;

class JIT final
{
public:
    static Result compile(TaskContext& ctx, MicroInstrBuilder& builder, JITExecMemory& outExecutableMemory);
};

SWC_END_NAMESPACE();

