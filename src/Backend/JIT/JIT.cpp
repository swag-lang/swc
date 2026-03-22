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

    bool ensureLocalFunctionTargetPrepared(TaskContext& ctx, SymbolFunction& targetFunction)
    {
        if (targetFunction.jitPatchAddress())
            return true;

        if (targetFunction.loweredCode().bytes.empty())
        {
            const SourceView& targetSrcView = ctx.compiler().srcView(targetFunction.srcViewRef());
            const FileRef     fileRef       = targetSrcView.fileRef();
            if (!fileRef.isValid())
                return false;

            SourceFile& targetFile = ctx.compiler().file(fileRef);
            Sema        baseSema(ctx, targetFile.nodePayloadContext(), false);
            if (targetFunction.tryMarkCodeGenJobScheduled())
            {
                const AstNodeRef declRoot = targetFunction.declNodeRef();
                if (declRoot.isInvalid())
                    return false;

                auto* job = heapNew<CodeGenJob>(ctx, baseSema, targetFunction, declRoot);
                ctx.compiler().global().jobMgr().enqueue(*job, JobPriority::Normal, ctx.compiler().jobClientId());
            }

            Sema::waitDone(ctx, ctx.compiler().jobClientId());
            if (Stats::get().numErrors.load(std::memory_order_relaxed) != 0)
                return false;
            if (targetFunction.loweredCode().bytes.empty())
                return false;
        }

        targetFunction.jit(ctx);
        return targetFunction.jitPatchAddress() != nullptr;
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

    bool resolveLocalFunctionTargetAddress(TaskContext& ctx, uint64_t& outTargetAddress, const MicroRelocation& reloc, const uint8_t* basePtr, RelocationResolveFailure* outFailure)
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

        auto& targetFunction = targetSymbol->cast<SymbolFunction>();
        void* entryAddress   = targetFunction.jitPatchAddress();
        if (!entryAddress && ensureLocalFunctionTargetPrepared(ctx, targetFunction))
            entryAddress = targetFunction.jitPatchAddress();
        if (!entryAddress && !targetFunction.loweredCode().bytes.empty())
        {
            targetFunction.jit(ctx);
            entryAddress = targetFunction.jitPatchAddress();
        }

        if (!entryAddress)
        {
            if (outFailure)
            {
                outFailure->kind         = RelocationResolveFailureKind::LocalTargetUnavailable;
                outFailure->targetSymbol = targetSymbol;
            }

            return false;
        }

        outTargetAddress = reinterpret_cast<uint64_t>(entryAddress);
        return outTargetAddress != 0;
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

    bool resolveRelocationTargetAddress(TaskContext& ctx, uint64_t& outTargetAddress, const MicroRelocation& reloc, const uint8_t* basePtr, RelocationResolveFailure* outFailure)
    {
        switch (reloc.kind)
        {
            case MicroRelocation::Kind::ConstantAddress:
                outTargetAddress = reloc.targetAddress;
                return true;

            case MicroRelocation::Kind::LocalFunctionAddress:
                return resolveLocalFunctionTargetAddress(ctx, outTargetAddress, reloc, basePtr, outFailure);

            case MicroRelocation::Kind::ForeignFunctionAddress:
                return resolveForeignFunctionTargetAddress(ctx, outTargetAddress, reloc, basePtr, outFailure);

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

        const auto& relocations = segment.relocations();
        for (const DataSegmentRelocation& relocation : relocations)
        {
            if (relocation.offset < allocation.offset)
                continue;
            if (relocation.offset - allocation.offset >= allocation.size)
                continue;

            if (relocation.kind == DataSegmentRelocationKind::DataSegmentOffset)
            {
                SWC_RESULT(patchConstantFunctionRelocationsRec(ctx, shardIndex, relocation.targetOffset, visited));
                continue;
            }

            SWC_ASSERT(relocation.kind == DataSegmentRelocationKind::FunctionSymbol);
            SymbolFunction* const targetFunction = relocation.targetSymbol;
            SWC_ASSERT(targetFunction != nullptr);
            if (!targetFunction)
                return Result::Error;

            MicroRelocation reloc;
            reloc.kind         = targetFunction->isForeign() ? MicroRelocation::Kind::ForeignFunctionAddress : MicroRelocation::Kind::LocalFunctionAddress;
            reloc.targetSymbol = targetFunction;

            uint64_t                 targetAddress = 0;
            RelocationResolveFailure failure;
            const bool               hasTargetAddress = targetFunction->isForeign() ? resolveForeignFunctionTargetAddress(ctx, targetAddress, reloc, nullptr, &failure) : resolveLocalFunctionTargetAddress(ctx, targetAddress, reloc, nullptr, &failure);
            if (!hasTargetAddress)
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

    Result patchConstantFunctionRelocations(TaskContext& ctx, const void* ptr)
    {
        if (!ptr)
            return Result::Continue;

        uint32_t  shardIndex = 0;
        const Ref sourceRef  = ctx.compiler().cstMgr().findDataSegmentRef(shardIndex, ptr);
        if (sourceRef == INVALID_REF)
            return Result::Continue;

        std::unordered_set<uint64_t> visited;
        return patchConstantFunctionRelocationsRec(ctx, shardIndex, sourceRef, visited);
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
            const bool               hasTargetAddress = resolveRelocationTargetAddress(ctx, targetAddress, reloc, basePtr, &failure);
            if (!hasTargetAddress)
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
                SWC_RESULT(patchConstantFunctionRelocations(ctx, reinterpret_cast<const void*>(targetAddress)));

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
    SWC_ASSERT(!executableMemory.empty());
    const ByteSpanRW writableCode = asByteSpan(static_cast<std::byte*>(executableMemory.entryPoint()), executableMemory.size());
    return patchRelocations(ctx, ownerFunction, writableCode, relocations);
}

Result JIT::patchGlobalFunctionVariables(TaskContext& ctx)
{
    const auto globals = ctx.compiler().nativeGlobalVariablesSnapshot();
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
        const bool               hasTargetAddress = targetFunction->isForeign() ? resolveForeignFunctionTargetAddress(ctx, targetAddress, reloc, nullptr, &failure) : resolveLocalFunctionTargetAddress(ctx, targetAddress, reloc, nullptr, &failure);
        if (!hasTargetAddress)
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
    prepare(ctx, outExecutableMemory, linearCode, unwindInfo);
    SWC_RESULT(patch(ctx, outExecutableMemory, relocations, ownerFunction));
    finalize(outExecutableMemory);
    return Result::Continue;
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
    SWC_RESULT(emit(ctx, executableMemory, asByteSpan(loweredCode.bytes), loweredCode.codeRelocations, loweredCode.unwindInfo));

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
        Os::exit(ExitCode::HardwareException);
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
