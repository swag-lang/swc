#pragma once
#include "Backend/CodeGen/Micro/MicroInstrBuilder.h"

SWC_BEGIN_NAMESPACE();

class TaskContext;
class JITExecMemory;

class JIT final
{
public:
    static void emit(TaskContext& ctx, std::span<const std::byte> linearCode, std::span<const MicroInstrCodeRelocation> relocations, JITExecMemory& outExecutableMemory);
};

SWC_END_NAMESPACE();
