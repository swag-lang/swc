#pragma once
#include "Support/Core/RefTypes.h"
#include "Backend/CodeGen/Micro/MicroInstrBuilder.h"

SWC_BEGIN_NAMESPACE();

class TaskContext;
class JITExecMemory;

struct FFIArgument
{
    TypeRef     typeRef  = TypeRef::invalid();
    const void* valuePtr = nullptr;
};

struct FFIReturn
{
    TypeRef typeRef  = TypeRef::invalid();
    void*   valuePtr = nullptr;
};

class FFI final
{
public:
    static void emit(TaskContext& ctx, std::span<const std::byte> linearCode, std::span<const MicroInstrCodeRelocation> relocations, JITExecMemory& outExecutableMemory);
    static void call(TaskContext& ctx, void* targetFn, std::span<const FFIArgument> args, const FFIReturn& ret);
};

SWC_END_NAMESPACE();
