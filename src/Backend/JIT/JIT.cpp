#include "pch.h"
#include "Backend/JIT/JIT.h"
#include "Backend/ABI/ABICall.h"
#include "Backend/ABI/ABITypeNormalize.h"
#include "Backend/ABI/CallConv.h"
#include "Backend/JIT/JITMemory.h"
#include "Backend/JIT/JITMemoryManager.h"
#include "Backend/Micro/MachineCode.h"
#include "Backend/Micro/MicroBuilder.h"
#include "Compiler/CodeGen/Core/CodeGenJob.h"
#include "Compiler/Lexer/SourceView.h"
#include "Compiler/Sema/Constant/ConstantManager.h"
#include "Compiler/Sema/Core/Sema.h"
#include "Compiler/Sema/Symbol/Symbol.Function.h"
#include "Compiler/Sema/Symbol/Symbol.Variable.h"
#include "Compiler/SourceFile.h"
#include "Main/CompilerInstance.h"
#include "Main/ExternalModuleManager.h"
#include "Main/Global.h"
#include "Main/Stats.h"
#include "Main/TaskContext.h"
#include "Support/Core/Utf8Helper.h"
#include "Support/Math/Helpers.h"
#include "Support/Memory/Heap.h"
#include "Support/Os/Os.h"
#include "Support/Report/Diagnostic.h"
#include "Support/Report/HardwareException.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    enum class RelocationResolveFailureKind : uint8_t
    {
        None,
        TargetSymbolMissing,
        TargetSymbolNotFunction,
        LocalTargetUnavailable,
        TargetFunctionNotForeign,
        ForeignModuleMissing,
        ForeignFunctionMissing,
        ForeignLookupFailed,
    };

    struct RelocationResolveFailure
    {
        RelocationResolveFailureKind kind         = RelocationResolveFailureKind::None;
        const Symbol*                targetSymbol = nullptr;
        Utf8                         moduleName;
        Utf8                         functionName;
    };

    Utf8 relocationSymbolName(const TaskContext& ctx, const Symbol* symbol)
    {
        if (!symbol)
            return {};

        return symbol->getFullScopedName(ctx);
    }

    template<typename T>
    bool tryReadHostValue(const void* ptr, T& outValue)
    {
        SWC_TRY
        {
            std::memcpy(&outValue, ptr, sizeof(T));
            return true;
        }
        SWC_EXCEPT(SWC_EXCEPTION_EXECUTE_HANDLER)
        {
            return false;
        }
    }

    void appendHostValue(Utf8& out, std::string_view label, const void* ptr, const uint32_t numBits)
    {
        if (!ptr)
        {
            out += std::format("{} = <null>\n", label);
            return;
        }

        switch (numBits)
        {
            case 32:
            {
                uint32_t value = 0;
                if (tryReadHostValue(ptr, value))
                    out += std::format("{} = [0x{:016X}] -> 0x{:08X}\n", label, reinterpret_cast<uint64_t>(ptr), value);
                else
                    out += std::format("{} = [0x{:016X}] -> <unreadable>\n", label, reinterpret_cast<uint64_t>(ptr));
                return;
            }

            case 64:
            {
                uint64_t value = 0;
                if (tryReadHostValue(ptr, value))
                    out += std::format("{} = [0x{:016X}] -> 0x{:016X}\n", label, reinterpret_cast<uint64_t>(ptr), value);
                else
                    out += std::format("{} = [0x{:016X}] -> <unreadable>\n", label, reinterpret_cast<uint64_t>(ptr));
                return;
            }

            default:
                SWC_UNREACHABLE();
        }
    }

    AstNodeRef fallbackWaitNodeRef(const TaskContext& ctx, const SymbolFunction* ownerFunction)
    {
        if (ctx.state().nodeRef.isValid())
            return ctx.state().nodeRef;
        if (ownerFunction)
            return ownerFunction->declNodeRef();
        return AstNodeRef::invalid();
    }

    SourceCodeRef fallbackWaitCodeRef(const TaskContext& ctx, const SymbolFunction* ownerFunction)
    {
        if (ctx.state().codeRef.isValid())
            return ctx.state().codeRef;
        if (ownerFunction)
            return ownerFunction->codeRef();
        return SourceCodeRef::invalid();
    }

    void setWaitCodeGenCompleted(TaskContext& ctx, const SymbolFunction* ownerFunction, const SymbolFunction& targetFunction)
    {
        if (!ownerFunction)
            return;

        TaskState& wait   = ctx.state();
        wait.kind         = TaskStateKind::SemaWaitSymCodeGenCompleted;
        wait.nodeRef      = fallbackWaitNodeRef(ctx, ownerFunction);
        wait.codeRef      = fallbackWaitCodeRef(ctx, ownerFunction);
        wait.symbol       = &targetFunction;
        wait.waiterSymbol = ownerFunction;
    }

    Result ensureLocalFunctionTargetPrepared(TaskContext& ctx, SymbolFunction& targetFunction, const SymbolFunction* ownerFunction)
    {
        if (targetFunction.jitPatchAddress())
            return Result::Continue;

        if (!targetFunction.isCodeGenCompleted())
        {
            if (targetFunction.isIgnored())
                return Result::Error;

            const SourceView& targetSrcView = ctx.compiler().srcView(targetFunction.srcViewRef());
            const FileRef     fileRef       = targetSrcView.fileRef();
            if (!fileRef.isValid())
                return Result::Error;

            SourceFile& targetFile = ctx.compiler().file(fileRef);
            Sema        baseSema(ctx, targetFile.nodePayloadContext(), false);
            if (targetFunction.tryMarkCodeGenJobScheduled())
            {
                const AstNodeRef declRoot = targetFunction.declNodeRef();
                if (declRoot.isInvalid())
                    return Result::Error;

                auto* job = heapNew<CodeGenJob>(ctx, baseSema, targetFunction, declRoot);
                ctx.compiler().global().jobMgr().enqueue(*job, JobPriority::Normal, ctx.compiler().jobClientId());
            }

            // Re-check only after codegen reaches a completed state. Pre-solved
            // progress is too early because dependencies can still expand.
            setWaitCodeGenCompleted(ctx, ownerFunction, targetFunction);
            return Result::Pause;
        }

        if (targetFunction.loweredCode().bytes.empty())
            return Result::Error;

        SWC_RESULT(targetFunction.jit(ctx));
        return targetFunction.jitPatchAddress() ? Result::Continue : Result::Error;
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

            SWC_UNREACHABLE();
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
                SWC_UNREACHABLE();
                return outArg;
        }
    }

    Result resolveLocalFunctionTargetAddress(TaskContext& ctx, uint64_t& outTargetAddress, const MicroRelocation& reloc, const uint8_t* basePtr, const SymbolFunction* ownerFunction, RelocationResolveFailure* outFailure)
    {
        outTargetAddress = reloc.targetAddress;
        if (outTargetAddress == MicroRelocation::K_SELF_ADDRESS)
        {
            outTargetAddress = reinterpret_cast<uint64_t>(basePtr);
            return Result::Continue;
        }

        if (outTargetAddress != 0)
            return Result::Continue;

        Symbol* const targetSymbol = reloc.targetSymbol;
        if (!targetSymbol)
        {
            if (outFailure)
                outFailure->kind = RelocationResolveFailureKind::TargetSymbolMissing;
            return Result::Error;
        }

        if (!targetSymbol->isFunction())
        {
            if (outFailure)
            {
                outFailure->kind         = RelocationResolveFailureKind::TargetSymbolNotFunction;
                outFailure->targetSymbol = targetSymbol;
            }

            return Result::Error;
        }

        auto& targetFunction = targetSymbol->cast<SymbolFunction>();
        void* entryAddress   = targetFunction.jitPatchAddress();
        if (!entryAddress)
        {
            const Result prepareResult = ensureLocalFunctionTargetPrepared(ctx, targetFunction, ownerFunction);
            if (prepareResult != Result::Continue)
            {
                if (prepareResult == Result::Error && outFailure)
                {
                    outFailure->kind         = RelocationResolveFailureKind::LocalTargetUnavailable;
                    outFailure->targetSymbol = targetSymbol;
                }
                return prepareResult;
            }

            entryAddress = targetFunction.jitPatchAddress();
        }

        if (!entryAddress)
        {
            if (outFailure)
            {
                outFailure->kind         = RelocationResolveFailureKind::LocalTargetUnavailable;
                outFailure->targetSymbol = targetSymbol;
            }

            return Result::Error;
        }

        outTargetAddress = reinterpret_cast<uint64_t>(entryAddress);
        return outTargetAddress != 0 ? Result::Continue : Result::Error;
    }

    bool resolveForeignFunctionTargetAddress(TaskContext& ctx, uint64_t& outTargetAddress, const MicroRelocation& reloc, const uint8_t* basePtr, RelocationResolveFailure* outFailure)
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
        if (!targetSymbol)
        {
            if (outFailure)
                outFailure->kind = RelocationResolveFailureKind::TargetSymbolMissing;
            return false;
        }

        if (!targetSymbol->isFunction())
        {
            if (outFailure)
            {
                outFailure->kind         = RelocationResolveFailureKind::TargetSymbolNotFunction;
                outFailure->targetSymbol = targetSymbol;
            }

            return false;
        }

        const SymbolFunction& targetFunction = targetSymbol->cast<SymbolFunction>();
        if (!targetFunction.isForeign())
        {
            if (outFailure)
            {
                outFailure->kind         = RelocationResolveFailureKind::TargetFunctionNotForeign;
                outFailure->targetSymbol = targetSymbol;
            }

            return false;
        }

        const std::string_view moduleName = targetFunction.foreignModuleName();
        if (moduleName.empty())
        {
            if (outFailure)
            {
                outFailure->kind         = RelocationResolveFailureKind::ForeignModuleMissing;
                outFailure->targetSymbol = targetSymbol;
            }

            return false;
        }

        const Utf8 functionName = targetFunction.resolveForeignFunctionName(ctx);
        if (functionName.empty())
        {
            if (outFailure)
            {
                outFailure->kind         = RelocationResolveFailureKind::ForeignFunctionMissing;
                outFailure->targetSymbol = targetSymbol;
                outFailure->moduleName   = Utf8(moduleName);
            }

            return false;
        }

        void* functionAddress = nullptr;
        if (!ctx.compiler().externalModuleMgr().getFunctionAddress(functionAddress, moduleName, functionName))
        {
            if (outFailure)
            {
                outFailure->kind         = RelocationResolveFailureKind::ForeignLookupFailed;
                outFailure->targetSymbol = targetSymbol;
                outFailure->moduleName   = Utf8(moduleName);
                outFailure->functionName = functionName;
            }

            return false;
        }

        outTargetAddress = reinterpret_cast<uint64_t>(functionAddress);
        return outTargetAddress != 0;
    }

    Result resolveRelocationTargetAddress(TaskContext& ctx, uint64_t& outTargetAddress, const MicroRelocation& reloc, const uint8_t* basePtr, const SymbolFunction* ownerFunction, RelocationResolveFailure* outFailure)
    {
        switch (reloc.kind)
        {
            case MicroRelocation::Kind::ConstantAddress:
                outTargetAddress = reloc.targetAddress;
                return Result::Continue;

            case MicroRelocation::Kind::LocalFunctionAddress:
                return resolveLocalFunctionTargetAddress(ctx, outTargetAddress, reloc, basePtr, ownerFunction, outFailure);

            case MicroRelocation::Kind::ForeignFunctionAddress:
                return resolveForeignFunctionTargetAddress(ctx, outTargetAddress, reloc, basePtr, outFailure) ? Result::Continue : Result::Error;

            case MicroRelocation::Kind::CompilerAddress:
                outTargetAddress = reinterpret_cast<uint64_t>(ctx.compiler().dataSegmentAddress(DataSegmentKind::Compiler, static_cast<uint32_t>(reloc.targetAddress)));
                return Result::Continue;

            case MicroRelocation::Kind::GlobalZeroAddress:
                outTargetAddress = reinterpret_cast<uint64_t>(ctx.compiler().dataSegmentAddress(DataSegmentKind::GlobalZero, static_cast<uint32_t>(reloc.targetAddress)));
                return Result::Continue;

            case MicroRelocation::Kind::GlobalInitAddress:
                outTargetAddress = reinterpret_cast<uint64_t>(ctx.compiler().dataSegmentAddress(DataSegmentKind::GlobalInit, static_cast<uint32_t>(reloc.targetAddress)));
                return Result::Continue;

            default:
                SWC_UNREACHABLE();
        }
    }

    void addRelocationFailureNotes(Diagnostic& diag, const TaskContext& ctx, const RelocationResolveFailure& failure)
    {
        switch (failure.kind)
        {
            case RelocationResolveFailureKind::None:
                break;

            case RelocationResolveFailureKind::TargetSymbolMissing:
                diag.addNote(DiagnosticId::cmd_note_relocation_target_symbol_missing);
                break;

            case RelocationResolveFailureKind::TargetSymbolNotFunction:
                diag.addNote(DiagnosticId::cmd_note_relocation_target_symbol_not_function);
                diag.last().addArgument(Diagnostic::ARG_TARGET, relocationSymbolName(ctx, failure.targetSymbol));
                break;

            case RelocationResolveFailureKind::LocalTargetUnavailable:
                diag.addNote(DiagnosticId::cmd_note_relocation_local_target_unavailable);
                diag.last().addArgument(Diagnostic::ARG_TARGET, relocationSymbolName(ctx, failure.targetSymbol));
                break;

            case RelocationResolveFailureKind::TargetFunctionNotForeign:
                diag.addNote(DiagnosticId::cmd_note_relocation_target_not_foreign);
                diag.last().addArgument(Diagnostic::ARG_TARGET, relocationSymbolName(ctx, failure.targetSymbol));
                break;

            case RelocationResolveFailureKind::ForeignModuleMissing:
                diag.addNote(DiagnosticId::cmd_note_relocation_foreign_module_missing);
                diag.last().addArgument(Diagnostic::ARG_TARGET, relocationSymbolName(ctx, failure.targetSymbol));
                break;

            case RelocationResolveFailureKind::ForeignFunctionMissing:
                diag.addNote(DiagnosticId::cmd_note_relocation_foreign_module_name);
                diag.last().addArgument(Diagnostic::ARG_VALUE, failure.moduleName);
                diag.addNote(DiagnosticId::cmd_note_relocation_foreign_function_missing);
                diag.last().addArgument(Diagnostic::ARG_TARGET, relocationSymbolName(ctx, failure.targetSymbol));
                break;

            case RelocationResolveFailureKind::ForeignLookupFailed:
                diag.addNote(DiagnosticId::cmd_note_relocation_foreign_module_name);
                diag.last().addArgument(Diagnostic::ARG_VALUE, failure.moduleName);
                diag.addNote(DiagnosticId::cmd_note_relocation_foreign_function_name);
                diag.last().addArgument(Diagnostic::ARG_TARGET, failure.functionName);
                diag.addNote(DiagnosticId::cmd_note_relocation_foreign_lookup_failed);
                break;

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

    Result patchConstantFunctionRelocationsRec(TaskContext&                  ctx,
                                               const SymbolFunction*         ownerFunction,
                                               uint32_t                      shardIndex,
                                               uint32_t                      sourceOffset,
                                               std::unordered_set<uint64_t>& visited)
    {
        DataSegment&          segment = ctx.compiler().cstMgr().shardDataSegment(shardIndex);
        DataSegmentAllocation allocation;
        if (!segment.findAllocation(allocation, sourceOffset))
            return Result::Continue;

        const uint64_t visitKey = (static_cast<uint64_t>(shardIndex) << 32) | allocation.offset;
        if (!visited.insert(visitKey).second)
            return Result::Continue;

        const auto relocations = segment.copyRelocations();
        for (const DataSegmentRelocation& relocation : relocations)
        {
            if (relocation.offset < allocation.offset)
                continue;
            if (relocation.offset - allocation.offset >= allocation.size)
                continue;

            if (relocation.kind == DataSegmentRelocationKind::DataSegmentOffset)
            {
                SWC_RESULT(patchConstantFunctionRelocationsRec(ctx, ownerFunction, shardIndex, relocation.targetOffset, visited));
                continue;
            }

            SWC_ASSERT(relocation.kind == DataSegmentRelocationKind::FunctionSymbol);
            const SymbolFunction* const targetFunction = relocation.targetSymbol;
            SWC_ASSERT(targetFunction != nullptr);

            MicroRelocation reloc;
            reloc.kind         = targetFunction->isForeign() ? MicroRelocation::Kind::ForeignFunctionAddress : MicroRelocation::Kind::LocalFunctionAddress;
            reloc.targetSymbol = const_cast<SymbolFunction*>(targetFunction);

            uint64_t                 targetAddress = 0;
            RelocationResolveFailure failure;
            const Result             resolveResult = targetFunction->isForeign() ? (resolveForeignFunctionTargetAddress(ctx, targetAddress, reloc, nullptr, &failure) ? Result::Continue : Result::Error) : resolveLocalFunctionTargetAddress(ctx, targetAddress, reloc, nullptr, ownerFunction, &failure);
            if (resolveResult == Result::Pause)
                return Result::Pause;
            if (resolveResult != Result::Continue)
            {
                const DiagnosticId diagId = targetFunction->isForeign() ? DiagnosticId::cmd_err_native_invalid_foreign_function_relocation : DiagnosticId::cmd_err_native_invalid_local_function_relocation;
                Diagnostic         diag   = Diagnostic::get(diagId);
                diag.addArgument(Diagnostic::ARG_SYM, Utf8("<jit-constant>"));
                addRelocationFailureNotes(diag, ctx, failure);
                diag.report(ctx);
                return Result::Error;
            }

            auto** storage = segment.ptr<void*>(relocation.offset);
            SWC_ASSERT(storage != nullptr);
            *storage = reinterpret_cast<void*>(targetAddress);
        }

        return Result::Continue;
    }

    Result patchConstantFunctionRelocations(TaskContext& ctx, const SymbolFunction* ownerFunction, const void* ptr)
    {
        if (!ptr)
            return Result::Continue;

        uint32_t  shardIndex = 0;
        const Ref sourceRef  = ctx.compiler().cstMgr().findDataSegmentRef(shardIndex, ptr);
        if (sourceRef == INVALID_REF)
            return Result::Continue;

        std::unordered_set<uint64_t> visited;
        return patchConstantFunctionRelocationsRec(ctx, ownerFunction, shardIndex, sourceRef, visited);
    }

    Result patchRelocations(TaskContext& ctx, const SymbolFunction* ownerFunction, ByteSpanRW writableCode, std::span<const MicroRelocation> relocations)
    {
        SWC_ASSERT(!writableCode.empty());
        if (relocations.empty())
            return Result::Continue;

        const uint8_t* basePtr = reinterpret_cast<uint8_t*>(writableCode.data());
        SWC_ASSERT(basePtr != nullptr);

        for (const MicroRelocation& reloc : relocations)
        {
            uint64_t                 targetAddress = 0;
            RelocationResolveFailure failure;
            const Result             resolveResult = resolveRelocationTargetAddress(ctx, targetAddress, reloc, basePtr, ownerFunction, &failure);
            if (resolveResult == Result::Pause)
                return Result::Pause;
            if (resolveResult != Result::Continue)
            {
                if (reloc.kind == MicroRelocation::Kind::ConstantAddress)
                    continue;

                const DiagnosticId diagId = reloc.kind == MicroRelocation::Kind::ForeignFunctionAddress ? DiagnosticId::cmd_err_native_invalid_foreign_function_relocation : DiagnosticId::cmd_err_native_invalid_local_function_relocation;
                Diagnostic         diag   = Diagnostic::get(diagId);
                if (ownerFunction)
                    diag.addArgument(Diagnostic::ARG_SYM, ownerFunction->getFullScopedName(ctx));
                else
                    diag.addArgument(Diagnostic::ARG_SYM, Utf8("<jit>"));
                addRelocationFailureNotes(diag, ctx, failure);
                diag.report(ctx);
                return Result::Error;
            }

            if (reloc.kind == MicroRelocation::Kind::ConstantAddress)
                SWC_RESULT(patchConstantFunctionRelocations(ctx, ownerFunction, reinterpret_cast<const void*>(targetAddress)));

            patchAbsolute64(writableCode, reloc, targetAddress);
        }

        return Result::Continue;
    }
}

void JIT::prepare(TaskContext& ctx, JITMemory& outExecutableMemory, const ByteSpan linearCode, const std::span<const std::byte> unwindInfo)
{
    SWC_ASSERT(!linearCode.empty());
    SWC_ASSERT(linearCode.size_bytes() <= std::numeric_limits<uint32_t>::max());

    JITMemoryManager& memoryManager     = ctx.compiler().jitMemMgr();
    const uint32_t    codeSize          = Math::alignUpU32(static_cast<uint32_t>(linearCode.size_bytes()), sizeof(uint32_t));
    const bool        registerSehUnwind = !unwindInfo.empty();

    const uint64_t unwindSizeU64     = registerSehUnwind ? unwindInfo.size() : 0;
    const uint64_t allocationSizeU64 = static_cast<uint64_t>(codeSize) + unwindSizeU64;
    const uint32_t allocationSize    = static_cast<uint32_t>(allocationSizeU64);
    memoryManager.allocateWithCodeSize(outExecutableMemory, allocationSize, codeSize);

    ByteSpanRW writableCode;
    writableCode = asByteSpan(static_cast<std::byte*>(outExecutableMemory.entryPoint()), linearCode.size());
    std::memcpy(writableCode.data(), linearCode.data(), linearCode.size_bytes());

    if (registerSehUnwind)
    {
        std::byte* unwindDest = static_cast<std::byte*>(outExecutableMemory.entryPoint()) + codeSize;
        std::memcpy(unwindDest, unwindInfo.data(), unwindInfo.size());
        outExecutableMemory.unwindInfoOffset_ = codeSize;
        outExecutableMemory.unwindInfoSize_   = static_cast<uint32_t>(unwindInfo.size());
    }
}

Result JIT::patch(TaskContext& ctx, const JITMemory& executableMemory, const std::span<const MicroRelocation> relocations, const SymbolFunction* ownerFunction)
{
    const TaskScopedContext scopedContext(ctx);
    SWC_ASSERT(!executableMemory.empty());
    const ByteSpanRW writableCode = asByteSpan(static_cast<std::byte*>(executableMemory.entryPoint()), executableMemory.size());
    return patchRelocations(ctx, ownerFunction, writableCode, relocations);
}

Result JIT::patchGlobalFunctionVariables(TaskContext& ctx)
{
    const TaskScopedContext scopedContext(ctx);
    const auto              globals = ctx.compiler().nativeGlobalVariablesSnapshot();
    for (const SymbolVariable* symVar : globals)
    {
        if (!symVar)
            continue;
        if (!symVar->hasGlobalStorage())
            continue;
        if (symVar->globalStorageKind() != DataSegmentKind::GlobalInit)
            continue;

        SymbolFunction* const targetFunction = symVar->globalFunctionInit();
        if (!targetFunction)
            continue;

        const TypeInfo& storageType = ctx.typeMgr().get(symVar->typeRef());
        SWC_ASSERT(storageType.sizeOf(ctx) == sizeof(uint64_t));

        MicroRelocation reloc;
        reloc.kind         = targetFunction->isForeign() ? MicroRelocation::Kind::ForeignFunctionAddress : MicroRelocation::Kind::LocalFunctionAddress;
        reloc.targetSymbol = targetFunction;

        uint64_t                 targetAddress = 0;
        RelocationResolveFailure failure;
        const Result             resolveResult = targetFunction->isForeign() ? (resolveForeignFunctionTargetAddress(ctx, targetAddress, reloc, nullptr, &failure) ? Result::Continue : Result::Error) : resolveLocalFunctionTargetAddress(ctx, targetAddress, reloc, nullptr, nullptr, &failure);
        if (resolveResult == Result::Pause)
            return Result::Pause;
        if (resolveResult != Result::Continue)
        {
            const DiagnosticId diagId = targetFunction->isForeign() ? DiagnosticId::cmd_err_native_invalid_foreign_function_relocation : DiagnosticId::cmd_err_native_invalid_local_function_relocation;
            Diagnostic         diag   = Diagnostic::get(diagId);
            diag.addArgument(Diagnostic::ARG_SYM, symVar->getFullScopedName(ctx));
            addRelocationFailureNotes(diag, ctx, failure);
            diag.report(ctx);
            return Result::Error;
        }

        auto* storage = reinterpret_cast<uint64_t*>(ctx.compiler().dataSegmentAddress(DataSegmentKind::GlobalInit, symVar->offset()));
        SWC_ASSERT(storage != nullptr);
        *storage = targetAddress;
    }

    return Result::Continue;
}

void JIT::finalize(JITMemory& executableMemory)
{
    JITMemoryManager::makeExecutable(executableMemory);
    JITMemoryManager::registerUnwindInfo(executableMemory);
}

Result JIT::emit(TaskContext& ctx, JITMemory& outExecutableMemory, ByteSpan linearCode, std::span<const MicroRelocation> relocations, const std::span<const std::byte> unwindInfo, const SymbolFunction* ownerFunction)
{
    const TaskScopedContext scopedContext(ctx);
    prepare(ctx, outExecutableMemory, linearCode, unwindInfo);
    SWC_RESULT(patch(ctx, outExecutableMemory, relocations, ownerFunction));
    finalize(outExecutableMemory);
    return Result::Continue;
}

Result JIT::emitAndCall(TaskContext& ctx, void* targetFn, std::span<const JITArgument> args, const JITReturn& ret)
{
    const TaskScopedContext scopedContext(ctx);
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
    SWC_RESULT(emit(ctx, executableMemory, asByteSpan(loweredCode.bytes), loweredCode.codeRelocations, loweredCode.unwindInfo));

    void* const invoker = executableMemory.entryPoint();
    SWC_ASSERT(invoker != nullptr);
    return call(ctx, invoker);
}

namespace
{
    constexpr uint32_t K_COMPILER_EXCEPTION_CODE = 666;

    std::string_view runtimeStringView(const Runtime::String& value)
    {
        if (!value.ptr || !value.length)
            return {};
        return {value.ptr, static_cast<size_t>(value.length)};
    }

    uint32_t tokenByteStart(const SourceView& srcView, const Token& token)
    {
        if (token.id == TokenId::Identifier)
            return srcView.identifiers()[token.byteStart].byteStart;
        return token.byteStart;
    }

    std::string_view extractAssertConditionTextFromText(const SourceCodeRange& range)
    {
        if (!range.srcView || !range.len)
            return {};

        const std::string_view text = Utf8Helper::trim(range.srcView->codeView(range.offset, range.len));
        if (!text.starts_with("@assert"))
            return {};

        const size_t openParen = text.find('(');
        if (openParen == std::string_view::npos || openParen + 1 >= text.size())
            return {};

        // Find the matching closing paren by tracking nesting depth
        uint32_t depth      = 1;
        size_t   closeParen = std::string_view::npos;
        for (size_t i = openParen + 1; i < text.size(); ++i)
        {
            if (text[i] == '(')
                ++depth;
            else if (text[i] == ')' && --depth == 0)
            {
                closeParen = i;
                break;
            }
        }

        const size_t condStart = openParen + 1;
        const size_t condEnd   = (closeParen != std::string_view::npos) ? closeParen : text.size();
        return Utf8Helper::trim(text.substr(condStart, condEnd - condStart));
    }

    std::string_view extractAssertConditionText(const SourceCodeRange& range)
    {
        if (!range.srcView || !range.len)
            return {};

        const SourceView&         srcView  = *range.srcView;
        const std::vector<Token>& tokens   = srcView.tokens();
        const uint32_t            rangeEnd = range.offset + range.len;

        TokenRef assertRef = TokenRef::invalid();
        for (uint32_t i = 0; i < tokens.size(); ++i)
        {
            const Token& token      = tokens[i];
            const auto   tokenStart = tokenByteStart(srcView, token);
            const auto   tokenEnd   = tokenStart + token.byteLength;
            if (tokenEnd <= range.offset)
                continue;
            if (tokenStart >= rangeEnd)
                break;
            if (token.id == TokenId::IntrinsicAssert)
            {
                assertRef = TokenRef(i);
                break;
            }
        }

        if (!assertRef.isValid())
            return extractAssertConditionTextFromText(range);

        TokenRef   openParenRef = TokenRef::invalid();
        uint32_t   depth        = 0;
        uint32_t   closeOffset  = 0;
        const auto assertIndex  = assertRef.get();

        for (uint32_t i = assertIndex + 1; i < tokens.size(); ++i)
        {
            const Token& token      = tokens[i];
            const auto   tokenStart = tokenByteStart(srcView, token);
            if (tokenStart >= rangeEnd)
                break;

            if (token.id == TokenId::SymLeftParen)
            {
                openParenRef = TokenRef(i);
                depth        = 1;
                for (uint32_t j = i + 1; j < tokens.size(); ++j)
                {
                    const Token& nestedToken = tokens[j];
                    const auto   nestedStart = tokenByteStart(srcView, nestedToken);
                    if (nestedStart >= rangeEnd)
                        break;

                    if (nestedToken.id == TokenId::SymLeftParen)
                        ++depth;
                    else if (nestedToken.id == TokenId::SymRightParen)
                    {
                        --depth;
                        if (!depth)
                        {
                            closeOffset = nestedStart;
                            break;
                        }
                    }
                }

                break;
            }
        }

        if (!openParenRef.isValid())
            return extractAssertConditionTextFromText(range);

        const Token& openParen  = srcView.token(openParenRef);
        const auto   openOffset = tokenByteStart(srcView, openParen) + openParen.byteLength;
        const auto   condEnd    = closeOffset ? closeOffset : rangeEnd;
        if (condEnd <= openOffset)
            return {};

        return Utf8Helper::trim(srcView.codeView(openOffset, condEnd - openOffset));
    }

    Utf8 formatAssertDiagnosticMessage(std::string_view message)
    {
        constexpr uint32_t kAssertMessageMaxChars = 80;

        const std::string_view trimmed = Utf8Helper::trim(message);
        if (trimmed.empty())
            return {};

        return Utf8Helper::truncate(trimmed, {.maxChars = kAssertMessageMaxChars, .mode = Utf8Helper::TruncateMode::Middle});
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

        const auto kind = static_cast<Runtime::ExceptionKind>(kindRaw);

        DiagnosticId       diagId;
        DiagnosticSeverity severity;
        switch (kind)
        {
            case Runtime::ExceptionKind::Panic:
                diagId             = DiagnosticId::sema_err_compiler_panic;
                severity           = DiagnosticSeverity::Error;
                *outErrorKind      = JITCallErrorKind::HardwareException;
                outExceptionAction = SWC_EXCEPTION_EXECUTE_HANDLER;
                break;
            case Runtime::ExceptionKind::Error:
                diagId             = DiagnosticId::sema_err_compiler_error;
                severity           = DiagnosticSeverity::Error;
                *outErrorKind      = JITCallErrorKind::HardwareException;
                outExceptionAction = SWC_EXCEPTION_EXECUTE_HANDLER;
                break;
            case Runtime::ExceptionKind::Warning:
                diagId             = DiagnosticId::sema_warn_compiler_warning;
                severity           = DiagnosticSeverity::Warning;
                *outErrorKind      = JITCallErrorKind::None;
                outExceptionAction = SWC_EXCEPTION_CONTINUE_EXECUTION;
                break;
            case Runtime::ExceptionKind::Assert:
                diagId             = DiagnosticId::sema_err_assert_failed;
                severity           = DiagnosticSeverity::Error;
                *outErrorKind      = JITCallErrorKind::HardwareException;
                outExceptionAction = SWC_EXCEPTION_EXECUTE_HANDLER;
                break;
            case Runtime::ExceptionKind::Safety:
                diagId             = DiagnosticId::safety_err_runtime;
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
        if (kind == Runtime::ExceptionKind::Assert)
        {
            if (diagMessage.empty())
                diagMessage = formatAssertDiagnosticMessage(extractAssertConditionText(range));
            else
                diagMessage = formatAssertDiagnosticMessage(diagMessage);
        }

        if (!diagMessage.empty())
            diag.addArgument(Diagnostic::ARG_BECAUSE, diagMessage);

        diag.report(ctx);
        return true;
    }

    Utf8 formatJitCrashContext(const TaskContext& ctx, const void* platformExceptionPointers)
    {
#ifdef _WIN32
        const auto* const args    = static_cast<const EXCEPTION_POINTERS*>(platformExceptionPointers);
        const auto* const context = args ? args->ContextRecord : nullptr;
        if (!context)
            return {};

        const uint64_t                     rip               = context->Rip;
        const SymbolFunction*              matchedFn         = nullptr;
        uint64_t                           matchedEntry      = 0;
        const MachineCode*                 matchedCode       = nullptr;
        const auto                         preparedFunctions = ctx.compiler().jitPreparedFunctionsSnapshot();
        std::vector<const SymbolFunction*> functions;
        functions.reserve(preparedFunctions.size() + (ctx.state().runJitFunction ? 1u : 0u));

        if (const SymbolFunction* const currentFn = ctx.state().runJitFunction)
            functions.push_back(currentFn);

        for (const SymbolFunction* function : preparedFunctions)
            functions.push_back(function);

        for (const SymbolFunction* function : functions)
        {
            if (!function)
                continue;

            const void* const entryPtr = function->jitEntryAddress();
            if (!entryPtr)
                continue;

            const auto& code = function->loweredCode();
            if (code.bytes.empty())
                continue;

            const uint64_t entryAddress = reinterpret_cast<uint64_t>(entryPtr);
            const uint64_t codeEnd      = entryAddress + code.bytes.size();
            if (rip < entryAddress || rip >= codeEnd)
                continue;

            matchedFn    = function;
            matchedEntry = entryAddress;
            matchedCode  = &code;
            break;
        }

        Utf8 out;
        if (!matchedFn || !matchedCode)
        {
            if (const SymbolFunction* const currentFn = ctx.state().runJitFunction)
            {
                out += std::format("jit current function: {}\n", currentFn->getFullScopedName(ctx));
                out += std::format("jit current entry: 0x{:016X}\n", reinterpret_cast<uint64_t>(currentFn->jitEntryAddress()));
                out += std::format("jit current size: 0x{:X}\n", currentFn->loweredCode().bytes.size());
            }
            out += std::format("jit offset: unresolved (rip=0x{:016X})\n", rip);
            return out;
        }

        const uint32_t offset = static_cast<uint32_t>(rip - matchedEntry);
        out += std::format("jit function: {}\n", matchedFn->getFullScopedName(ctx));
        out += std::format("jit entry: 0x{:016X}\n", matchedEntry);
        out += std::format("jit offset: 0x{:X}\n", offset);

        for (const auto& range : matchedCode->debugSourceRanges)
        {
            if (offset < range.codeStartOffset || offset >= range.codeEndOffset)
                continue;
            if (!range.sourceCodeRef.isValid())
                break;

            const SourceView&     srcView    = ctx.compiler().srcView(range.sourceCodeRef.srcViewRef);
            const Token&          token      = srcView.token(range.sourceCodeRef.tokRef);
            const SourceCodeRange codeRange  = token.codeRange(ctx, srcView);
            const SourceFile*     sourceFile = srcView.file();
            if (sourceFile)
                out += std::format("jit source: {}:{}:{}\n", sourceFile->path().string(), codeRange.line, codeRange.column);
            out += std::format("jit source span: [0x{:X}, 0x{:X})\n", range.codeStartOffset, range.codeEndOffset);
            break;
        }

        const uint32_t dumpStart = offset > 8 ? offset - 8 : 0;
        const uint32_t dumpEnd   = std::min<uint32_t>(static_cast<uint32_t>(matchedCode->bytes.size()), offset + 8);
        out += "jit bytes:";
        for (uint32_t i = dumpStart; i < dumpEnd; ++i)
        {
            if (i == offset)
                out += " |";
            out += std::format(" {:02X}", static_cast<uint8_t>(matchedCode->bytes[i]));
        }
        if (dumpEnd == offset)
            out += " |";
        out += "\n";

        out += "jit stack snapshot:\n";
        appendHostValue(out, "  [rsp+0x88]  x", reinterpret_cast<const void*>(context->Rsp + 0x88), 32);
        appendHostValue(out, "  [rsp+0x94]  y", reinterpret_cast<const void*>(context->Rsp + 0x94), 32);
        appendHostValue(out, "  [rsp+0x98]  dir", reinterpret_cast<const void*>(context->Rsp + 0x98), 32);
        appendHostValue(out, "  [rsp+0xB4]  startIndex", reinterpret_cast<const void*>(context->Rsp + 0xB4), 32);
        appendHostValue(out, "  [rsp+0x120] seenStates", reinterpret_cast<const void*>(context->Rsp + 0x120), 64);
        appendHostValue(out, "  [rsp+0x128] trace", reinterpret_cast<const void*>(context->Rsp + 0x128), 64);
        appendHostValue(out, "  [rsp+0x138] stateIndexAddr", reinterpret_cast<const void*>(context->Rsp + 0x138), 64);
        appendHostValue(out, "  [rsp+0xD8]  stateIndex", reinterpret_cast<const void*>(context->Rsp + 0xD8), 32);
        appendHostValue(out, "  [r13+0x0]   grid.width", reinterpret_cast<const void*>(context->R13 + 0x0), 32);
        appendHostValue(out, "  [r13+0x4]   grid.height", reinterpret_cast<const void*>(context->R13 + 0x4), 32);
        appendHostValue(out, "  [r13+0x8]   grid.startX", reinterpret_cast<const void*>(context->R13 + 0x8), 32);
        appendHostValue(out, "  [r13+0xC]   grid.startY", reinterpret_cast<const void*>(context->R13 + 0xC), 32);
        appendHostValue(out, "  [r13+0x10]  grid.cells", reinterpret_cast<const void*>(context->R13 + 0x10), 64);
        return out;
#else
        SWC_UNUSED(ctx);
        SWC_UNUSED(platformExceptionPointers);
        return {};
#endif
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

        const Utf8 extraInfo = formatJitCrashContext(ctx, platformExceptionPointers);
        HardwareException::log(ctx, "fatal error: hardware exception during jit call!", platformExceptionPointers, extraInfo);
        Stats::addError();
        Os::exit(ExitCode::HardwareException);
    }
}

Result JIT::call(TaskContext& ctx, void* invoker, const uint64_t* arg0, JITCallErrorKind* outErrorKind)
{
    const TaskContext* const savedContext = TaskContext::setCurrent(&ctx);
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

    TaskContext::setCurrent(savedContext);
    return hasException ? Result::Error : Result::Continue;
}

SWC_END_NAMESPACE();
