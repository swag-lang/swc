#include "pch.h"
#include "Backend/JIT/JIT.h"
#include "Backend/ABI/ABICall.h"
#include "Backend/ABI/ABITypeNormalize.h"
#include "Backend/ABI/CallConv.h"
#include "Backend/JIT/JITMemory.h"
#include "Backend/JIT/JITMemoryManager.h"
#include "Backend/Micro/MachineCode.h"
#include "Backend/Micro/MicroBuilder.h"
#include "Compiler/Lexer/SourceView.h"
#include "Compiler/Sema/Symbol/Symbol.Function.h"
#include "Main/CompilerInstance.h"
#include "Main/ExternalModuleManager.h"
#include "Main/TaskContext.h"
#include "Support/Math/Helpers.h"
#include "Support/Os/Os.h"
#include "Support/Report/Diagnostic.h"
#include "Support/Report/HardwareException.h"

SWC_BEGIN_NAMESPACE();

namespace
{
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
                const float value = *static_cast<const float*>(valuePtr);
                std::memcpy(&outArg.value, &value, sizeof(float));
                return outArg;
            }

            if (argType.numBits == 64)
            {
                const double value = *static_cast<const double*>(valuePtr);
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
                return true;

            case MicroRelocation::Kind::LocalFunctionAddress:
                return resolveLocalFunctionTargetAddress(outTargetAddress, reloc, basePtr);

            case MicroRelocation::Kind::ForeignFunctionAddress:
                return resolveForeignFunctionTargetAddress(ctx, outTargetAddress, reloc, basePtr);

            case MicroRelocation::Kind::CompilerAddress:
                outTargetAddress = reinterpret_cast<uint64_t>(ctx.compiler().dataSegmentAddress(DataSegmentKind::Compiler, static_cast<uint32_t>(reloc.targetAddress)));
                return true;

            case MicroRelocation::Kind::GlobalZeroAddress:
                outTargetAddress = reinterpret_cast<uint64_t>(ctx.compiler().dataSegmentAddress(DataSegmentKind::GlobalZero, static_cast<uint32_t>(reloc.targetAddress)));
                return true;

            case MicroRelocation::Kind::GlobalInitAddress:
                outTargetAddress = reinterpret_cast<uint64_t>(ctx.compiler().dataSegmentAddress(DataSegmentKind::GlobalInit, static_cast<uint32_t>(reloc.targetAddress)));
                return true;

            default:
                SWC_UNREACHABLE();
        }
    }

    void patchAbsolute64(ByteSpanRW writableCode, const MicroRelocation& reloc, uint64_t targetAddress)
    {
        auto*          basePtr        = reinterpret_cast<uint8_t*>(writableCode.data());
        const uint64_t patchEndOffset = static_cast<uint64_t>(reloc.codeOffset) + sizeof(uint64_t);
        SWC_ASSERT(patchEndOffset <= writableCode.size_bytes());
        std::memcpy(basePtr + reloc.codeOffset, &targetAddress, sizeof(targetAddress));
    }

    void patchRelocations(TaskContext& ctx, ByteSpanRW writableCode, std::span<const MicroRelocation> relocations)
    {
        SWC_ASSERT(!writableCode.empty());
        if (relocations.empty())
            return;

        const uint8_t* basePtr = reinterpret_cast<uint8_t*>(writableCode.data());
        SWC_ASSERT(basePtr != nullptr);

        for (const MicroRelocation& reloc : relocations)
        {
            uint64_t   targetAddress    = 0;
            const bool hasTargetAddress = resolveRelocationTargetAddress(ctx, targetAddress, reloc, basePtr);
            if (!hasTargetAddress)
            {
                if (reloc.kind == MicroRelocation::Kind::ConstantAddress)
                    continue;
                SWC_UNREACHABLE();
            }

            patchAbsolute64(writableCode, reloc, targetAddress);
        }
    }
}

void JIT::emit(TaskContext& ctx, JITMemory& outExecutableMemory, ByteSpan linearCode, std::span<const MicroRelocation> relocations, const std::span<const std::byte> unwindInfo)
{
    SWC_ASSERT(!linearCode.empty());
    SWC_ASSERT(linearCode.size_bytes() <= std::numeric_limits<uint32_t>::max());

    JITMemoryManager& memoryManager     = ctx.compiler().jitMemMgr();
    const uint32_t    codeSize          = Math::alignUpU32(static_cast<uint32_t>(linearCode.size_bytes()), sizeof(uint32_t));
    const bool        registerSehUnwind = ctx.compiler().buildCfg().backend.enableExceptions;
    SWC_ASSERT(!registerSehUnwind || !unwindInfo.empty());

    const uint64_t unwindSizeU64     = registerSehUnwind ? unwindInfo.size() : 0;
    const uint64_t allocationSizeU64 = static_cast<uint64_t>(codeSize) + unwindSizeU64;
    const uint32_t allocationSize    = static_cast<uint32_t>(allocationSizeU64);
    memoryManager.allocateWithCodeSize(outExecutableMemory, allocationSize, codeSize);

    ByteSpanRW writableCode;
    writableCode = asByteSpan(static_cast<std::byte*>(outExecutableMemory.entryPoint()), linearCode.size());
    std::memcpy(writableCode.data(), linearCode.data(), linearCode.size_bytes());
    patchRelocations(ctx, writableCode, relocations);

    if (registerSehUnwind)
    {
        std::byte* unwindDest = static_cast<std::byte*>(outExecutableMemory.entryPoint()) + codeSize;
        std::memcpy(unwindDest, unwindInfo.data(), unwindInfo.size());
        outExecutableMemory.unwindInfoOffset_ = codeSize;
        outExecutableMemory.unwindInfoSize_   = static_cast<uint32_t>(unwindInfo.size());
    }

    JITMemoryManager::makeExecutable(outExecutableMemory);

    if (registerSehUnwind)
        JITMemoryManager::registerUnwindInfo(outExecutableMemory);
}

Result JIT::emitAndCall(TaskContext& ctx, void* targetFn, std::span<const JITArgument> args, const JITReturn& ret)
{
    SWC_ASSERT(targetFn != nullptr);

    constexpr auto                         callConvKind = CallConvKind::Host;
    const CallConv&                        conv         = CallConv::get(callConvKind);
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
        const JITArgument&                     arg     = args[i];
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
        const JITArgument&                     arg     = args[i];
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
            uint8_t* const copyPtr   = indirectArgStorage.data() + indirectArgStorageOffset;
            std::memcpy(copyPtr, arg.valuePtr, argType.indirectSize);
            indirectValuePtr = copyPtr;
            indirectArgStorageOffset += argType.indirectSize;
        }

        packedArgs[i + packedArgBaseOffset].value   = reinterpret_cast<uint64_t>(indirectValuePtr);
        packedArgs[i + packedArgBaseOffset].isFloat = false;
        packedArgs[i + packedArgBaseOffset].numBits = 64;
    }

    MicroBuilder builder(ctx);

    void* const           retOutPtr = retType.isIndirect ? nullptr : ret.valuePtr;
    const ABICall::Return retMeta   = {
          .valuePtr   = retOutPtr,
          .isVoid     = retType.isVoid,
          .isFloat    = retType.isFloat,
          .isIndirect = retType.isIndirect,
          .numBits    = retType.numBits,
    };
    ABICall::callAddress(builder, callConvKind, reinterpret_cast<uint64_t>(targetFn), packedArgs, retMeta);
    builder.emitRet();

    MachineCode  loweredCode;
    const Result lowerResult = loweredCode.emit(ctx, builder);
    SWC_ASSERT(lowerResult == Result::Continue);

    JITMemory executableMemory;
    emit(ctx, executableMemory, asByteSpan(loweredCode.bytes), loweredCode.codeRelocations, loweredCode.unwindInfo);

    void* const invoker = executableMemory.entryPoint();
    SWC_ASSERT(invoker != nullptr);
    return call(ctx, invoker);
}

namespace
{
    constexpr uint32_t K_COMPILER_EXCEPTION_CODE = 666;

    enum class RuntimeExceptionKind : uint64_t
    {
        Panic   = 0,
        Error   = 1,
        Warning = 2,
        Assert  = 3,
    };

    std::string_view runtimeStringView(const Runtime::String& value)
    {
        if (!value.ptr || !value.length)
            return {};
        return {value.ptr, static_cast<size_t>(value.length)};
    }

    void decodeCompilerDiagnosticException(const Runtime::SourceCodeLocation*& outLocation, std::string_view& outMessage, uint64_t& outKindRaw)
    {
        Runtime::Context* runtimeContext = CompilerInstance::runtimeContextFromTls();
        SWC_ASSERT(runtimeContext != nullptr);

        outLocation         = &runtimeContext->exceptionLoc;
        auto       msgPtr   = static_cast<const char*>(runtimeContext->exceptionParams[1]);
        const auto msgCount = reinterpret_cast<uintptr_t>(runtimeContext->exceptionParams[2]);
        outKindRaw          = reinterpret_cast<uintptr_t>(runtimeContext->exceptionParams[3]);
        if (msgPtr && msgCount)
            outMessage = {msgPtr, msgCount};

        runtimeContext->exceptionParams[0] = nullptr;
        runtimeContext->exceptionParams[1] = nullptr;
        runtimeContext->exceptionParams[2] = nullptr;
        runtimeContext->exceptionParams[3] = nullptr;
    }

    bool tryReportRuntimeException(TaskContext& ctx, const uint32_t exceptionCode, JITCallErrorKind* outErrorKind, int& outExceptionAction)
    {
        if (exceptionCode != K_COMPILER_EXCEPTION_CODE)
            return false;

        const Runtime::SourceCodeLocation* location = nullptr;
        std::string_view                   message;
        uint64_t                           kindRaw = 0;
        decodeCompilerDiagnosticException(location, message, kindRaw);

        const auto kind = static_cast<RuntimeExceptionKind>(kindRaw);

        DiagnosticId       diagId;
        DiagnosticSeverity severity;
        switch (kind)
        {
            case RuntimeExceptionKind::Panic:
                diagId             = DiagnosticId::sema_err_compiler_panic;
                severity           = DiagnosticSeverity::Error;
                *outErrorKind      = JITCallErrorKind::HardwareException;
                outExceptionAction = SWC_EXCEPTION_EXECUTE_HANDLER;
                break;
            case RuntimeExceptionKind::Error:
                diagId             = DiagnosticId::sema_err_compiler_error;
                severity           = DiagnosticSeverity::Error;
                *outErrorKind      = JITCallErrorKind::HardwareException;
                outExceptionAction = SWC_EXCEPTION_EXECUTE_HANDLER;
                break;
            case RuntimeExceptionKind::Warning:
                diagId             = DiagnosticId::sema_warn_compiler_warning;
                severity           = DiagnosticSeverity::Warning;
                *outErrorKind      = JITCallErrorKind::None;
                outExceptionAction = SWC_EXCEPTION_CONTINUE_EXECUTION;
                break;
            case RuntimeExceptionKind::Assert:
                diagId             = DiagnosticId::sema_err_assert_failed;
                severity           = DiagnosticSeverity::Error;
                *outErrorKind      = JITCallErrorKind::HardwareException;
                outExceptionAction = SWC_EXCEPTION_EXECUTE_HANDLER;
                break;
            default:
                SWC_UNREACHABLE();
        }

        SourceCodeRange range;
        FileRef         fileRef = FileRef::invalid();
        if (location)
        {
            const std::string_view  locationFileName = runtimeStringView(location->fileName);
            const SourceView* const srcView          = ctx.compiler().findSourceViewByFileName(locationFileName);
            if (srcView)
            {
                fileRef = srcView->fileRef();
                srcView->codeRangeFromRuntimeLocation(ctx, *location, range);
            }
        }

        Diagnostic diag = Diagnostic::get(diagId, fileRef);
        if (range.srcView)
            diag.last().addSpan(range, "", severity);

        Utf8 diagMessage = message;
        if (!diagMessage.empty())
            diag.addArgument(Diagnostic::ARG_BECAUSE, diagMessage);

        diag.report(ctx);
        return true;
    }

    int exceptionHandler(TaskContext& ctx, const void* platformExceptionPointers, JITCallErrorKind& outErrorKind)
    {
        uint32_t    exceptionCode    = 0;
        const void* exceptionAddress = nullptr;
        Os::decodeHostException(exceptionCode, exceptionAddress, platformExceptionPointers);
        SWC_UNUSED(exceptionAddress);

        int compilerDiagAction = SWC_EXCEPTION_EXECUTE_HANDLER;
        if (tryReportRuntimeException(ctx, exceptionCode, &outErrorKind, compilerDiagAction))
            return compilerDiagAction;

        if (!exceptionCode)
            outErrorKind = JITCallErrorKind::None;
        else
            outErrorKind = JITCallErrorKind::HardwareException;

        HardwareException::log(ctx, "fatal error: hardware exception during jit call!", platformExceptionPointers);
        Stats::get().numErrors.fetch_add(1);

        return SWC_EXCEPTION_EXECUTE_HANDLER;
    }
}

Result JIT::call(TaskContext& ctx, void* invoker, const uint64_t* arg0, JITCallErrorKind* outErrorKind)
{
    SWC_ASSERT(invoker != nullptr);
    ctx.compiler().initPerThreadRuntimeContextForJit();

    bool hasException = false;
    auto callError    = JITCallErrorKind::None;

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
    SWC_EXCEPT(exceptionHandler(ctx, SWC_GET_EXCEPTION_INFOS(), callError))
    {
        hasException = true;
    }

    if (outErrorKind)
        *outErrorKind = hasException ? callError : JITCallErrorKind::None;

    return hasException ? Result::Error : Result::Continue;
}

SWC_END_NAMESPACE();
