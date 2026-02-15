#pragma once
#include "Backend/CodeGen/Micro/MicroInstrBuilder.h"

SWC_BEGIN_NAMESPACE();

class TaskContext;
class JITExecMemory;

class JIT final
{
public:
    static void compile(TaskContext& ctx, MicroInstrBuilder& builder, JITExecMemory& outExecutableMemory);
};

SWC_END_NAMESPACE();
