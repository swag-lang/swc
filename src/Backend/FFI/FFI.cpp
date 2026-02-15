#include "pch.h"
#include "Backend/FFI/FFI.h"
#include "Backend/JIT/JIT.h"
#include "Backend/JIT/JITExecMemory.h"
#include "Backend/CodeGen/ABI/ABICall.h"
#include "Backend/CodeGen/ABI/ABITypeNormalize.h"
#include "Backend/CodeGen/ABI/CallConv.h"
#include "Backend/CodeGen/Micro/MicroInstrBuilder.h"
#include "Main/CommandLine.h"
#include "Main/TaskContext.h"
#include "Support/Os/Os.h"
#include "Support/Report/HardwareException.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    using FFIInvokerFn = void (*)();

    struct FFIExceptionInfo
    {
        FFIInvokerFn invoker = nullptr;
    };

    uint32_t alignValue(uint32_t value, uint32_t alignment)
    {
        SWC_ASSERT(alignment != 0);
        const uint32_t rem = value % alignment;
        if (!rem)
            return value;
        return value + alignment - rem;
    }

    ABICall::Arg packArgValue(const ABITypeNormalize::NormalizedType& argType, const void* valuePtr)
    {
        SWC_ASSERT(valuePtr != nullptr);
        SWC_ASSERT(!argType.isIndirect);

        ABICall::Arg outArg;
        outArg.isFloat = argType.isFloat;
        outArg.numBits = argType.numBits;

        if (argType.isFloat)
        {
            if (argType.numBits == 32)
            {
                const auto value = *static_cast<const float*>(valuePtr);
                std::memcpy(&outArg.value, &value, sizeof(float));
                return outArg;
            }

            if (argType.numBits == 64)
            {
                const auto value = *static_cast<const double*>(valuePtr);
                std::memcpy(&outArg.value, &value, sizeof(double));
                return outArg;
            }

            SWC_ASSERT(false);
            return outArg;
        }

        switch (argType.numBits)
        {
            case 8:
                outArg.value = *static_cast<const uint8_t*>(valuePtr);
                return outArg;
            case 16:
                outArg.value = *static_cast<const uint16_t*>(valuePtr);
                return outArg;
            case 32:
                outArg.value = *static_cast<const uint32_t*>(valuePtr);
                return outArg;
            case 64:
                std::memcpy(&outArg.value, valuePtr, sizeof(uint64_t));
                return outArg;
            default:
                SWC_ASSERT(false);
                return outArg;
        }
    }

    void appendFfiExtraInfo(Utf8& outMsg, const TaskContext& ctx, const void* userData)
    {
        const auto& info = *static_cast<const FFIExceptionInfo*>(userData);
        outMsg += "  call site: ffi invoker\n";
        if (ctx.cmdLine().verboseHardwareException)
            outMsg += std::format("  invoker: 0x{:016X}\n", reinterpret_cast<uintptr_t>(info.invoker));
    }

    int exceptionHandler(const TaskContext& ctx, const FFIExceptionInfo& info, SWC_LP_EXCEPTION_POINTERS args)
    {
        HardwareException::log(ctx, "fatal error: hardware exception during ffi call!", args, appendFfiExtraInfo, &info);
        Os::panicBox("hardware exception raised!");
        return SWC_EXCEPTION_EXECUTE_HANDLER;
    }

    void invokeCall(TaskContext& ctx, FFIInvokerFn invoker)
    {
        const FFIExceptionInfo info{.invoker = invoker};
        SWC_TRY
        {
            invoker();
        }
        SWC_EXCEPT(exceptionHandler(ctx, info, SWC_GET_EXCEPTION_INFOS()))
        {
        }
    }
}

void FFI::call(TaskContext& ctx, void* targetFn, std::span<const FFIArgument> args, const FFIReturn& ret)
{
    SWC_ASSERT(targetFn != nullptr);

    constexpr auto          callConvKind = CallConvKind::Host;
    const auto&             conv         = CallConv::get(callConvKind);
    const ABITypeNormalize::NormalizedType retType = ABITypeNormalize::normalize(ctx, conv, ret.typeRef, ABITypeNormalize::Usage::Return);
    SWC_ASSERT(retType.isVoid || ret.valuePtr);

    SmallVector<ABICall::Arg>              packedArgs;
    SmallVector<ABITypeNormalize::NormalizedType> normalizedArgTypes;
    uint32_t                       indirectArgStorageSize = 0;
    const bool                     hasIndirectRetArg      = retType.isIndirect;
    const uint32_t                 packedArgBaseOffset    = hasIndirectRetArg ? 1u : 0u;
    packedArgs.resize(args.size() + packedArgBaseOffset);
    normalizedArgTypes.resize(args.size());

    if (hasIndirectRetArg)
    {
        packedArgs[0].value   = reinterpret_cast<uint64_t>(ret.valuePtr);
        packedArgs[0].isFloat = false;
        packedArgs[0].numBits = 64;
    }

    const auto numArgs = static_cast<uint32_t>(args.size());
    for (uint32_t i = 0; i < numArgs; ++i)
    {
        const auto&             arg     = args[i];
        const ABITypeNormalize::NormalizedType argType = ABITypeNormalize::normalize(ctx, conv, arg.typeRef, ABITypeNormalize::Usage::Argument);
        SWC_ASSERT(!argType.isVoid);
        normalizedArgTypes[i] = argType;

        if (argType.isIndirect && argType.needsIndirectCopy)
        {
            indirectArgStorageSize         = alignValue(indirectArgStorageSize, argType.indirectAlign);
            const uint64_t nextStorageSize = static_cast<uint64_t>(indirectArgStorageSize) + argType.indirectSize;
            SWC_ASSERT(nextStorageSize <= std::numeric_limits<uint32_t>::max());
            indirectArgStorageSize = static_cast<uint32_t>(nextStorageSize);
        }
    }

    SmallVector<uint8_t> indirectArgStorage;
    if (indirectArgStorageSize)
        indirectArgStorage.resize(indirectArgStorageSize);

    uint32_t indirectArgStorageOffset = 0;
    for (uint32_t i = 0; i < numArgs; ++i)
    {
        const auto&             arg     = args[i];
        const ABITypeNormalize::NormalizedType argType = normalizedArgTypes[i];
        SWC_ASSERT(arg.valuePtr != nullptr);

        if (!argType.isIndirect)
        {
            packedArgs[i + packedArgBaseOffset] = packArgValue(argType, arg.valuePtr);
            continue;
        }

        const void* indirectValuePtr = arg.valuePtr;
        if (argType.needsIndirectCopy)
        {
            indirectArgStorageOffset = alignValue(indirectArgStorageOffset, argType.indirectAlign);
            auto* const copyPtr      = indirectArgStorage.data() + indirectArgStorageOffset;
            std::memcpy(copyPtr, arg.valuePtr, argType.indirectSize);
            indirectValuePtr = copyPtr;
            indirectArgStorageOffset += argType.indirectSize;
        }

        packedArgs[i + packedArgBaseOffset].value   = reinterpret_cast<uint64_t>(indirectValuePtr);
        packedArgs[i + packedArgBaseOffset].isFloat = false;
        packedArgs[i + packedArgBaseOffset].numBits = 64;
    }

    MicroInstrBuilder builder(ctx);
    const auto        retOutPtr = retType.isIndirect ? nullptr : ret.valuePtr;
    const auto        retMeta   = ABICall::Return{
                 .valuePtr   = retOutPtr,
                 .isVoid     = retType.isVoid,
                 .isFloat    = retType.isFloat,
                 .isIndirect = retType.isIndirect,
                 .numBits    = retType.numBits,
    };
    ABICall::callByAddress(builder, callConvKind, reinterpret_cast<uint64_t>(targetFn), packedArgs, retMeta);
    builder.encodeRet(EncodeFlagsE::Zero);

    JITExecMemory executableMemory;
    SWC_ASSERT(JIT::compile(ctx, builder, executableMemory) == Result::Continue);

    const auto invoker = executableMemory.entryPoint<FFIInvokerFn>();
    SWC_ASSERT(invoker != nullptr);

    invokeCall(ctx, invoker);
}

SWC_END_NAMESPACE();
