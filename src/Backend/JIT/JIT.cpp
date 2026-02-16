#include "pch.h"
#include "Backend/JIT/JIT.h"
#include "Backend/CodeGen/ABI/ABICall.h"
#include "Backend/CodeGen/ABI/ABITypeNormalize.h"
#include "Backend/CodeGen/ABI/CallConv.h"
#include "Backend/CodeGen/Micro/MachineCode.h"
#include "Backend/CodeGen/Micro/MicroInstrBuilder.h"
#include "Backend/JIT/JITExecMemory.h"
#include "Backend/JIT/JITExecMemoryManager.h"
#include "Compiler/Sema/Symbol/Symbol.Function.h"
#include "Main/CommandLine.h"
#include "Main/CompilerInstance.h"
#include "Main/TaskContext.h"
#include "Support/Math/Helpers.h"
#include "Support/Os/Os.h"
#include "Support/Report/HardwareException.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    struct ExceptionInfo
    {
        void* invoker = nullptr;
    };

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

    void appendExtraInfo(Utf8& outMsg, const TaskContext& ctx, const void* userData)
    {
        const auto& info = *static_cast<const ExceptionInfo*>(userData);
        outMsg += "  call site: jit invoker\n";
        if (ctx.cmdLine().verboseHardwareException)
            outMsg += std::format("  invoker: 0x{:016X}\n", reinterpret_cast<uintptr_t>(info.invoker));
    }

    int exceptionHandler(const TaskContext& ctx, const ExceptionInfo& info, SWC_LP_EXCEPTION_POINTERS args)
    {
        HardwareException::log(ctx, "fatal error: hardware exception during jit call!", args, appendExtraInfo, &info);
        return SWC_EXCEPTION_EXECUTE_HANDLER;
    }

    void patchCodeRelocations(ByteSpanRW writableCode, std::span<const MicroInstrRelocation> relocations)
    {
        SWC_FORCE_ASSERT(!writableCode.empty());

        if (relocations.empty())
            return;

        auto* const basePtr = reinterpret_cast<uint8_t*>(writableCode.data());
        SWC_FORCE_ASSERT(basePtr != nullptr);

        for (const auto& reloc : relocations)
        {
            auto target = reloc.targetAddress;
            if (target == 0 && reloc.targetSymbol && reloc.targetSymbol->isFunction())
            {
                auto&      targetFunction     = reloc.targetSymbol->cast<SymbolFunction>();
                const auto targetEntryAddress = targetFunction.jitEntryAddress();
                if (targetEntryAddress)
                    target = reinterpret_cast<uint64_t>(targetEntryAddress);
                else
                    target = reinterpret_cast<uint64_t>(basePtr);
            }

            if (target == 0)
                continue;
            if (target == MicroInstrRelocation::K_SELF_ADDRESS)
                target = reinterpret_cast<uint64_t>(basePtr);

            SWC_FORCE_ASSERT(reloc.kind == MicroInstrRelocation::Kind::Rel32);

            const uint64_t patchEndOffset = static_cast<uint64_t>(reloc.codeOffset) + sizeof(int32_t);
            SWC_FORCE_ASSERT(patchEndOffset <= writableCode.size_bytes());

            const auto nextAddress = reinterpret_cast<uint64_t>(basePtr + patchEndOffset);
            const auto delta       = static_cast<int64_t>(target) - static_cast<int64_t>(nextAddress);
            SWC_FORCE_ASSERT(delta >= std::numeric_limits<int32_t>::min() && delta <= std::numeric_limits<int32_t>::max());

            const int32_t disp32 = static_cast<int32_t>(delta);
            std::memcpy(basePtr + reloc.codeOffset, &disp32, sizeof(disp32));
        }
    }
}

void JIT::emit(TaskContext& ctx, JITExecMemory& outExecutableMemory, ByteSpan linearCode, std::span<const MicroInstrRelocation> relocations)
{
    SWC_FORCE_ASSERT(!linearCode.empty());
    SWC_FORCE_ASSERT(linearCode.size_bytes() <= std::numeric_limits<uint32_t>::max());

    auto&                memoryManager = ctx.compiler().jitMemMgr();
    const auto           codeSize      = static_cast<uint32_t>(linearCode.size_bytes());
    ByteSpanRW writableCode;

    SWC_FORCE_ASSERT(memoryManager.allocate(outExecutableMemory, codeSize));
    writableCode = asByteSpan(static_cast<std::byte*>(outExecutableMemory.entryPoint()), linearCode.size());
    std::memcpy(writableCode.data(), linearCode.data(), linearCode.size_bytes());
    patchCodeRelocations(writableCode, relocations);
    SWC_FORCE_ASSERT(memoryManager.makeExecutable(outExecutableMemory));
}

void JIT::emitAndCall(TaskContext& ctx, void* targetFn, std::span<const JITArgument> args, const JITReturn& ret)
{
    SWC_ASSERT(targetFn != nullptr);

    constexpr auto                         callConvKind = CallConvKind::Host;
    const auto&                            conv         = CallConv::get(callConvKind);
    const ABITypeNormalize::NormalizedType retType      = ABITypeNormalize::normalize(ctx, conv, ret.typeRef, ABITypeNormalize::Usage::Return);
    SWC_ASSERT(retType.isVoid || ret.valuePtr);

    SmallVector<ABICall::Arg>                     packedArgs;
    SmallVector<ABITypeNormalize::NormalizedType> normalizedArgTypes;
    uint32_t                                      indirectArgStorageSize = 0;
    const bool                                    hasIndirectRetArg      = retType.isIndirect;
    const uint32_t                                packedArgBaseOffset    = hasIndirectRetArg ? 1u : 0u;

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
        const auto&                            arg     = args[i];
        const ABITypeNormalize::NormalizedType argType = ABITypeNormalize::normalize(ctx, conv, arg.typeRef, ABITypeNormalize::Usage::Argument);
        SWC_ASSERT(!argType.isVoid);
        normalizedArgTypes[i] = argType;

        if (argType.isIndirect && argType.needsIndirectCopy)
        {
            indirectArgStorageSize         = Math::alignUpU32(indirectArgStorageSize, argType.indirectAlign);
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
        const auto&                            arg     = args[i];
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
            indirectArgStorageOffset = Math::alignUpU32(indirectArgStorageOffset, argType.indirectAlign);
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

    const auto retOutPtr = retType.isIndirect ? nullptr : ret.valuePtr;
    const auto retMeta   = ABICall::Return{
          .valuePtr   = retOutPtr,
          .isVoid     = retType.isVoid,
          .isFloat    = retType.isFloat,
          .isIndirect = retType.isIndirect,
          .numBits    = retType.numBits,
    };
    ABICall::callByAddress(builder, callConvKind, reinterpret_cast<uint64_t>(targetFn), packedArgs, retMeta);
    builder.encodeRet();

    MachineCode loweredCode;
    loweredCode.emit(ctx, builder);

    JITExecMemory executableMemory;
    emit(ctx, executableMemory, asByteSpan(loweredCode.bytes), loweredCode.codeRelocations);

    const auto invoker = executableMemory.entryPoint();
    SWC_ASSERT(invoker != nullptr);
    (void) call(ctx, invoker);
}

Result JIT::call(TaskContext& ctx, void* invoker, const uint64_t* arg0)
{
    SWC_ASSERT(invoker != nullptr);
    const ExceptionInfo info{.invoker = invoker};
    bool                hasException = false;

    SWC_TRY
    {
        if (arg0)
        {
            using InvokerVoidU64    = void (*)(uint64_t);
            const auto typedInvoker = reinterpret_cast<InvokerVoidU64>(invoker);
            typedInvoker(*arg0);
        }
        else
        {
            using InvokerFn         = void (*)();
            const auto typedInvoker = reinterpret_cast<InvokerFn>(invoker);
            typedInvoker();
        }
    }
    SWC_EXCEPT(exceptionHandler(ctx, info, SWC_GET_EXCEPTION_INFOS()))
    {
        hasException = true;
    }

    return hasException ? Result::Error : Result::Continue;
}

SWC_END_NAMESPACE();
