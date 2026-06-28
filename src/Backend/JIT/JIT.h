#pragma once
#include <cstdint>
#include <span>

#include "Backend/ABI/CallConv.h"
#include "Backend/Micro/MicroBuilder.h"
#include "Support/Core/ByteArray.h"
#include "Support/Core/RefTypes.h"
#include "Support/Core/Result.h"

SWC_BEGIN_NAMESPACE();

class TaskContext;
class JITMemory;
class SymbolFunction;

struct JITArgument
{
    TypeRef     typeRef  = TypeRef::invalid();
    const void* valuePtr = nullptr;
};

struct JITReturn
{
    TypeRef typeRef  = TypeRef::invalid();
    void*   valuePtr = nullptr;
};

enum class JITCallErrorKind : uint8_t
{
    None,
    HardwareException,
};

enum class JITRuntimeSetupMode : uint8_t
{
    FromCompiler,
    None,
};

class JIT final
{
public:
    static void   prepare(TaskContext& ctx, JITMemory& outExecutableMemory, const ByteArray& linearCode, const ByteArray& unwindInfo);
    static Result patch(TaskContext& ctx, const JITMemory& executableMemory, std::span<const MicroRelocation> relocations, const SymbolFunction* ownerFunction = nullptr);
    static Result patchGlobalFunctionVariables(TaskContext& ctx);
    static void   finalize(JITMemory& executableMemory);
    static Result emit(TaskContext& ctx, JITMemory& outExecutableMemory, const ByteArray& linearCode, std::span<const MicroRelocation> relocations, const ByteArray& unwindInfo, const SymbolFunction* ownerFunction = nullptr);
    static bool   resolveForeignFunctionAddress(TaskContext& ctx, void*& outFunctionAddress, const SymbolFunction& targetFunction);
    static Result emitAndCall(TaskContext& ctx, void* targetFn, std::span<const JITArgument> args, const JITReturn& ret, CallConvKind callConvKind = CallConvKind::C);
    static Result call(TaskContext& ctx, void* invoker, const uint64_t* arg0 = nullptr, JITCallErrorKind* outErrorKind = nullptr, JITRuntimeSetupMode setupMode = JITRuntimeSetupMode::FromCompiler);
};

SWC_END_NAMESPACE();
