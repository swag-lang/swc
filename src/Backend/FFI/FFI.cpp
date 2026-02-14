#include "pch.h"
#include "Backend/FFI/FFI.h"
#include "Backend/JIT/JIT.h"
#include "Backend/JIT/JITExecMemory.h"
#include "Backend/MachineCode/CallConv.h"
#include "Backend/MachineCode/Micro/MicroAbiCall.h"
#include "Backend/MachineCode/Micro/MicroInstrBuilder.h"
#include "Compiler/Sema/Type/TypeManager.h"
#include "Main/CommandLine.h"
#include "Main/Global.h"
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

    enum class FFITypeUsage : uint8_t
    {
        Argument,
        Return,
    };

    struct FFINormalizedType
    {
        bool     isVoid            = true;
        bool     isFloat           = false;
        bool     isIndirectArg     = false;
        bool     needsIndirectCopy = false;
        uint8_t  numBits           = 0;
        uint32_t indirectCopySize  = 0;
        uint32_t indirectCopyAlign = 0;
    };

    FFINormalizedType makeNormalizedType(bool isVoid, bool isFloat, uint8_t numBits)
    {
        return FFINormalizedType{.isVoid = isVoid, .isFloat = isFloat, .numBits = numBits};
    }

    FFINormalizedType makeIndirectStructType(uint32_t copySize, uint32_t copyAlign, bool needsCopy)
    {
        FFINormalizedType outType = makeNormalizedType(false, false, 64);
        outType.isIndirectArg     = true;
        outType.needsIndirectCopy = needsCopy;
        outType.indirectCopySize  = copySize;
        outType.indirectCopyAlign = copyAlign;
        return outType;
    }

    FFINormalizedType normalizeType(TaskContext& ctx, const CallConv& conv, TypeRef typeRef, FFITypeUsage usage)
    {
        SWC_ASSERT(typeRef.isValid());

        const TypeRef expanded = ctx.typeMgr().get(typeRef).unwrap(ctx, typeRef, TypeExpandE::Alias | TypeExpandE::Enum);
        SWC_ASSERT(expanded.isValid());

        const TypeInfo& ty = ctx.typeMgr().get(expanded);
        if (ty.isVoid())
            return makeNormalizedType(true, false, 0);

        if (ty.isBool())
            return makeNormalizedType(false, false, 8);

        if (ty.isCharRune())
            return makeNormalizedType(false, false, 32);

        if (ty.isInt() && ty.payloadIntBits() <= 64 && ty.payloadIntBits() != 0)
            return makeNormalizedType(false, false, static_cast<uint8_t>(ty.payloadIntBits()));

        if (ty.isFloat() && (ty.payloadFloatBits() == 32 || ty.payloadFloatBits() == 64))
            return makeNormalizedType(false, true, static_cast<uint8_t>(ty.payloadFloatBits()));

        if (ty.isPointerLike() || ty.isNull())
            return makeNormalizedType(false, false, 64);

        if (ty.isStruct())
        {
            const uint64_t rawSize = ty.sizeOf(ctx);
            SWC_ASSERT(rawSize <= std::numeric_limits<uint32_t>::max());
            const uint32_t size = static_cast<uint32_t>(rawSize);

            const auto passingKind = usage == FFITypeUsage::Argument ? conv.classifyStructArgPassing(size) : conv.classifyStructReturnPassing(size);
            if (passingKind == StructArgPassingKind::ByValue)
            {
                SWC_ASSERT(size == 1 || size == 2 || size == 4 || size == 8);
                return makeNormalizedType(false, false, static_cast<uint8_t>(size * 8));
            }

            const uint32_t align     = std::max(ty.alignOf(ctx), uint32_t{1});
            const bool     needsCopy = usage == FFITypeUsage::Argument && conv.structArgPassing.passByReferenceNeedsCopy;
            return makeIndirectStructType(size, align, needsCopy);
        }

        SWC_ASSERT(false);
        return makeNormalizedType(true, false, 0);
    }

    uint32_t alignValue(uint32_t value, uint32_t alignment)
    {
        SWC_ASSERT(alignment != 0);
        const uint32_t rem = value % alignment;
        if (!rem)
            return value;
        return value + alignment - rem;
    }

    MicroABICallArg packArgValue(const FFINormalizedType& argType, const void* valuePtr)
    {
        SWC_ASSERT(valuePtr != nullptr);
        SWC_ASSERT(!argType.isIndirectArg);

        MicroABICallArg outArg;
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
        SWC_ASSERT(userData != nullptr);
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
    const FFINormalizedType retType      = normalizeType(ctx, conv, ret.typeRef, FFITypeUsage::Return);
    SWC_ASSERT(retType.isVoid || ret.valuePtr);

    SmallVector<MicroABICallArg>   packedArgs;
    SmallVector<FFINormalizedType> normalizedArgTypes;
    uint32_t                       indirectArgStorageSize = 0;
    const bool                     hasIndirectRetArg      = retType.isIndirectArg;
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
        const FFINormalizedType argType = normalizeType(ctx, conv, arg.typeRef, FFITypeUsage::Argument);
        SWC_ASSERT(!argType.isVoid);
        normalizedArgTypes[i] = argType;

        if (argType.isIndirectArg && argType.needsIndirectCopy)
        {
            indirectArgStorageSize         = alignValue(indirectArgStorageSize, argType.indirectCopyAlign);
            const uint64_t nextStorageSize = static_cast<uint64_t>(indirectArgStorageSize) + argType.indirectCopySize;
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
        const FFINormalizedType argType = normalizedArgTypes[i];
        SWC_ASSERT(arg.valuePtr != nullptr);

        if (!argType.isIndirectArg)
        {
            packedArgs[i + packedArgBaseOffset] = packArgValue(argType, arg.valuePtr);
            continue;
        }

        const void* indirectValuePtr = arg.valuePtr;
        if (argType.needsIndirectCopy)
        {
            indirectArgStorageOffset = alignValue(indirectArgStorageOffset, argType.indirectCopyAlign);
            auto* const copyPtr      = indirectArgStorage.data() + indirectArgStorageOffset;
            std::memcpy(copyPtr, arg.valuePtr, argType.indirectCopySize);
            indirectValuePtr = copyPtr;
            indirectArgStorageOffset += argType.indirectCopySize;
        }

        packedArgs[i + packedArgBaseOffset].value   = reinterpret_cast<uint64_t>(indirectValuePtr);
        packedArgs[i + packedArgBaseOffset].isFloat = false;
        packedArgs[i + packedArgBaseOffset].numBits = 64;
    }

    MicroInstrBuilder builder(ctx);
    const auto        retOutPtr = retType.isIndirectArg ? nullptr : ret.valuePtr;
    const auto        retMeta   = MicroABICallReturn{
                 .valuePtr   = retOutPtr,
                 .isVoid     = retType.isVoid,
                 .isFloat    = retType.isFloat,
                 .isIndirect = retType.isIndirectArg,
                 .numBits    = retType.numBits,
    };
    emitMicroABICallByAddress(builder, callConvKind, reinterpret_cast<uint64_t>(targetFn), packedArgs, retMeta);
    builder.encodeRet(EncodeFlagsE::Zero);

    JITExecMemory executableMemory;
    SWC_ASSERT(JIT::compile(ctx, builder, executableMemory) == Result::Continue);

    const auto invoker = executableMemory.entryPoint<FFIInvokerFn>();
    SWC_ASSERT(invoker != nullptr);

    invokeCall(ctx, invoker);
}

SWC_END_NAMESPACE();
