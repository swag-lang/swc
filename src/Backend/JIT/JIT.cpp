#include "pch.h"
#include "Backend/JIT/JIT.h"
#include "Backend/CodeGen/ABI/ABICall.h"
#include "Backend/CodeGen/ABI/ABITypeNormalize.h"
#include "Backend/CodeGen/ABI/CallConv.h"
#include "Backend/CodeGen/Micro/MachineCode.h"
#include "Backend/CodeGen/Micro/MicroBuilder.h"
#include "Backend/JIT/JITMemory.h"
#include "Backend/JIT/JITMemoryManager.h"
#include "Compiler/Sema/Symbol/Symbol.Function.h"
#include "Main/CommandLine.h"
#include "Main/CompilerInstance.h"
#include "Main/ExternalModuleManager.h"
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

    bool resolveLocalFunctionTargetAddress(uint64_t& outTargetAddress, const MicroRelocation& reloc, const uint8_t* basePtr)
    {
        outTargetAddress = reloc.targetAddress;
        if (outTargetAddress == MicroRelocation::K_SELF_ADDRESS)
        {
            outTargetAddress = reinterpret_cast<uint64_t>(basePtr);
            return true;
        }

        if (outTargetAddress != 0)
            return true;

        Symbol* const targetSymbol = reloc.targetSymbol;
        if (!targetSymbol || !targetSymbol->isFunction())
            return false;

        const SymbolFunction& targetFunction = targetSymbol->cast<SymbolFunction>();
        void* const           entryAddress   = targetFunction.jitEntryAddress();
        if (!entryAddress)
            return false;

        outTargetAddress = reinterpret_cast<uint64_t>(entryAddress);
        return outTargetAddress != 0;
    }

    bool resolveForeignFunctionTargetAddress(TaskContext& ctx, uint64_t& outTargetAddress, const MicroRelocation& reloc, const uint8_t* basePtr)
    {
        outTargetAddress = reloc.targetAddress;
        if (outTargetAddress == MicroRelocation::K_SELF_ADDRESS)
        {
            outTargetAddress = reinterpret_cast<uint64_t>(basePtr);
            return true;
        }

        if (outTargetAddress != 0)
            return true;

        Symbol* const targetSymbol = reloc.targetSymbol;
        if (!targetSymbol || !targetSymbol->isFunction())
            return false;

        const SymbolFunction& targetFunction = targetSymbol->cast<SymbolFunction>();
        if (!targetFunction.isForeign())
            return false;

        const std::string_view moduleName = targetFunction.foreignModuleName();
        if (moduleName.empty())
            return false;

        const Utf8 functionName = targetFunction.resolveForeignFunctionName(ctx);
        if (functionName.empty())
            return false;

        void* functionAddress = nullptr;
        if (!ctx.compiler().externalModuleMgr().getFunctionAddress(functionAddress, moduleName, functionName))
            return false;

        outTargetAddress = reinterpret_cast<uint64_t>(functionAddress);
        return outTargetAddress != 0;
    }

    bool resolveRelocationTargetAddress(TaskContext& ctx, uint64_t& outTargetAddress, const MicroRelocation& reloc, const uint8_t* basePtr)
    {
        switch (reloc.kind)
        {
            case MicroRelocation::Kind::ConstantAddress:
                outTargetAddress = reloc.targetAddress;
                if (outTargetAddress == MicroRelocation::K_SELF_ADDRESS)
                    outTargetAddress = reinterpret_cast<uint64_t>(basePtr);
                return true;

            case MicroRelocation::Kind::LocalFunctionAddress:
                return resolveLocalFunctionTargetAddress(outTargetAddress, reloc, basePtr);

            case MicroRelocation::Kind::ForeignFunctionAddress:
                return resolveForeignFunctionTargetAddress(ctx, outTargetAddress, reloc, basePtr);

            default:
                SWC_FORCE_ASSERT(false);
                return false;
        }
    }

    void patchAbsolute64(ByteSpanRW writableCode, const MicroRelocation& reloc, uint64_t targetAddress)
    {
        const auto     basePtr        = reinterpret_cast<uint8_t*>(writableCode.data());
        const uint64_t patchEndOffset = static_cast<uint64_t>(reloc.codeOffset) + sizeof(uint64_t);
        SWC_FORCE_ASSERT(patchEndOffset <= writableCode.size_bytes());
        std::memcpy(basePtr + reloc.codeOffset, &targetAddress, sizeof(targetAddress));
    }

    void patchRelocations(TaskContext& ctx, ByteSpanRW writableCode, std::span<const MicroRelocation> relocations)
    {
        SWC_FORCE_ASSERT(!writableCode.empty());

        if (relocations.empty())
            return;

        const uint8_t* basePtr = reinterpret_cast<uint8_t*>(writableCode.data());
        SWC_FORCE_ASSERT(basePtr != nullptr);

        for (const auto& reloc : relocations)
        {
            uint64_t   targetAddress    = 0;
            const bool hasTargetAddress = resolveRelocationTargetAddress(ctx, targetAddress, reloc, basePtr);
            if (!hasTargetAddress)
            {
                if (reloc.kind == MicroRelocation::Kind::ConstantAddress)
                    continue;
                SWC_FORCE_ASSERT(false);
            }
            patchAbsolute64(writableCode, reloc, targetAddress);
        }
    }
}

void JIT::emit(TaskContext& ctx, JITMemory& outExecutableMemory, ByteSpan linearCode, std::span<const MicroRelocation> relocations)
{
    SWC_FORCE_ASSERT(!linearCode.empty());
    SWC_FORCE_ASSERT(linearCode.size_bytes() <= std::numeric_limits<uint32_t>::max());

    auto&      memoryManager = ctx.compiler().jitMemMgr();
    const auto codeSize      = static_cast<uint32_t>(linearCode.size_bytes());
    ByteSpanRW writableCode;

    SWC_FORCE_ASSERT(memoryManager.allocate(outExecutableMemory, codeSize));
    writableCode = asByteSpan(static_cast<std::byte*>(outExecutableMemory.entryPoint()), linearCode.size());
    std::memcpy(writableCode.data(), linearCode.data(), linearCode.size_bytes());
    patchRelocations(ctx, writableCode, relocations);
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

    MicroBuilder builder(ctx);

    const auto retOutPtr = retType.isIndirect ? nullptr : ret.valuePtr;
    const auto retMeta   = ABICall::Return{
          .valuePtr   = retOutPtr,
          .isVoid     = retType.isVoid,
          .isFloat    = retType.isFloat,
          .isIndirect = retType.isIndirect,
          .numBits    = retType.numBits,
    };
    ABICall::callAddress(builder, callConvKind, reinterpret_cast<uint64_t>(targetFn), packedArgs, retMeta);
    builder.encodeRet();

    MachineCode loweredCode;
    loweredCode.emit(ctx, builder);

    JITMemory executableMemory;
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
