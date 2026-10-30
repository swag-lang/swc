#include "pch.h"
#include "Backend/JIT/JIT.h"
#include "Backend/ABI/ABICall.h"
#include "Backend/ABI/ABITypeNormalize.h"
#include "Backend/ABI/CallConv.h"
#include "Backend/JIT/JITMemory.h"
#include "Backend/JIT/JITMemoryManager.h"
#include "Backend/JIT/JITPatchJob.h"
#include "Backend/Micro/MachineCode.h"
#include "Backend/Micro/MicroBuilder.h"
#include "Backend/RuntimeContext.h"
#include "Backend/RuntimeName.h"
#include "Compiler/CodeGen/Core/CodeGenJob.h"
#include "Compiler/Lexer/SourceView.h"
#include "Compiler/Parser/Ast/AstNodes.h"
#include "Compiler/Sema/Constant/ConstantManager.h"
#include "Compiler/Sema/Constant/ConstantStorageLayout.h"
#include "Compiler/Sema/Core/Sema.h"
#include "Compiler/Sema/Symbol/Symbol.Function.h"
#include "Compiler/Sema/Symbol/Symbol.Variable.h"
#include "Compiler/SourceFile.h"
#include "Main/Command/CommandLine.h"
#include "Main/CompilerInstance.h"
#include "Main/ExternalModuleManager.h"
#include "Main/Global.h"
#include "Main/Stats.h"
#include "Main/TaskContext.h"
#include "Support/Core/PointerSet.h"
#include "Support/Core/Utf8Helper.h"
#include "Support/Math/Helpers.h"
#include "Support/Os/Os.h"
#include "Support/Report/Assert.h"
#include "Support/Report/Diagnostic.h"
#include "Support/Report/HardwareException.h"

SWC_BEGIN_NAMESPACE();

// A function thunk needs a six-byte indirect jump followed by its eight-byte target
// address; pad it to sixteen bytes and keep the island naturally aligned.
constexpr uint32_t K_ISLAND_ALIGNMENT    = 8;
constexpr uint32_t K_FUNCTION_THUNK_SLOT = 16;

namespace
{
    constexpr uint32_t K_COMPILER_EXCEPTION_CODE = 666;

    using RuntimeSetupInvoker = void (*)(Runtime::RuntimeFlags);
    using RuntimeHookInvoker  = void (*)(uint64_t, uint64_t, uint64_t, const Runtime::String*);

    enum class RuntimeHookStage : uint64_t
    {
        Init    = 1,
        PreMain = 2,
    };

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

        Utf8 moduleName;
        Utf8 functionName;
    };

    struct ConstantFunctionPatch
    {
        uint32_t offset = 0;
        void*    target = nullptr;
    };

    struct JITRelocationPatchContext
    {
        // Allocate lazily: most functions reference only a few string constants.
        StampedKeySet visitedConstantAllocations;

        // Resolved addresses are non-null, so null marks a missing cache entry.
        PointerMap<SymbolFunction, void> resolvedFunctionAddresses;
    };

    struct RuntimeExceptionDiagnosticInfo
    {
        DiagnosticId       diagId          = DiagnosticId::None;
        DiagnosticSeverity severity        = DiagnosticSeverity::Error;
        JITCallErrorKind   errorKind       = JITCallErrorKind::None;
        int                exceptionAction = SWC_EXCEPTION_EXECUTE_HANDLER;
    };

    Result reportRelocationFailure(TaskContext& ctx, DiagnosticId diagId, std::string_view symbolName, const RelocationResolveFailure& failure);

    bool isSetupRuntimeFunction(TaskContext& ctx, const SymbolFunction* function)
    {
        if (!function)
            return false;

        return ctx.idMgr().runtimeFunctionKind(function->idRef()) == IdentifierManager::RuntimeFunctionKind::SetupRuntime;
    }

    bool shouldUseSharedRuntimeSetup(TaskContext& ctx, const SymbolFunction* function)
    {
        if (!function)
            return false;
        if (isSetupRuntimeFunction(ctx, function))
            return false;
        if (!function->srcViewRef().isValid())
            return true;

        return !ctx.compiler().srcView(function->srcViewRef()).isRuntimeFile();
    }

    void collectGlobalInitRelocationOffsets(const SymbolFunction& function, std::vector<uint64_t>& outOffsets)
    {
        if (function.loweredCode().bytes.empty())
            return;

        const std::vector<uint64_t>& offsets = function.globalInitRelocationOffsets();
        outOffsets.insert(outOffsets.end(), offsets.begin(), offsets.end());
    }

    // Gather offsets for the caller to sort and search, avoiding a separate
    // allocation for each offset.
    void collectJitGlobalInitRelocationOffsets(TaskContext& ctx, std::vector<uint64_t>& outOffsets)
    {
        const SymbolFunction* runFunction = ctx.state().runJitFunction;
        if (!runFunction)
            return;

        PointerSet<const SymbolFunction> seen;
        const auto                       collect = [&](const SymbolFunction* function) {
            if (!function || !seen.insert(function))
                return;

            collectGlobalInitRelocationOffsets(*function, outOffsets);
        };

        runFunction->visitJitOrder(collect);

        if (shouldUseSharedRuntimeSetup(ctx, runFunction))
        {
            const IdentifierRef setupIdRef = ctx.idMgr().runtimeFunction(IdentifierManager::RuntimeFunctionKind::SetupRuntime);
            if (const SymbolFunction* setupFn = ctx.compiler().runtimeFunctionSymbol(setupIdRef))
                setupFn->visitJitOrder(collect);
        }
    }

    bool referencesGlobalInitRange(const std::vector<uint64_t>& sortedReferencedOffsets, const uint64_t offset, const uint64_t size)
    {
        // Use one binary search per global variable instead of scanning every referenced slot.
        const uint64_t endOffset = offset + std::max<uint64_t>(size, 1);
        const auto     it        = std::ranges::lower_bound(sortedReferencedOffsets, offset);
        return it != sortedReferencedOffsets.end() && *it < endOffset;
    }

    Result synchronizeImportedRuntimeContexts(TaskContext& ctx)
    {
        if (!shouldUseSharedRuntimeSetup(ctx, ctx.state().runJitFunction))
            return Result::Continue;

        const auto& runtimeImports = ctx.compiler().nativeRuntimeImports();
        if (runtimeImports.empty())
            return Result::Continue;

        ctx.compiler().markImportedNativeExecution();

        // Constexpr evaluation can enter imported modules from several sema workers at once.
        // Their hooks own process-wide DLL lifecycle state: one worker must finish Init and
        // PreMain before another worker can observe or refresh that state.
        static std::mutex      runtimeHookMutex;
        const std::scoped_lock lock(runtimeHookMutex);

        const uint64_t tlsIdPlusOne = *CompilerInstance::runtimeContextTlsIdStorage() + 1;

        // JIT arguments live in the compiler's ProcessInfo. Share them with imported
        // modules so their separate slots yield the same Swag.args() values.
        ctx.compiler().ensureProcessInfoRunArgs();
        const Runtime::String* processArgs = &ctx.compiler().processInfo().args;
        for (const CompilerInstance::NativeRuntimeImport& runtimeImport : runtimeImports)
        {
            if (!runtimeImport.hasSharedRuntimeHook)
                continue;

            const Utf8 hookSymbolName = runtimeHookSymbolName(runtimeImport.linkModuleName.view());
            void*      hookAddress    = nullptr;
            if (!ctx.compiler().externalModuleMgr().getFunctionAddress(hookAddress, runtimeImport.linkModuleName.view(), hookSymbolName.view()))
            {
                RelocationResolveFailure failure;
                failure.kind         = RelocationResolveFailureKind::ForeignLookupFailed;
                failure.moduleName   = runtimeImport.linkModuleName;
                failure.functionName = hookSymbolName;
                return reportRelocationFailure(ctx, DiagnosticId::cmd_err_native_invalid_foreign_function_relocation, hookSymbolName.view(), failure);
            }

            // Hooks refresh TLS before their one-time lifecycle guards, keeping
            // Swag.getContext() valid inside imported DLL code.
            const auto hookInvoker = reinterpret_cast<RuntimeHookInvoker>(hookAddress);
            hookInvoker(static_cast<uint64_t>(RuntimeHookStage::Init), tlsIdPlusOne, static_cast<uint64_t>(Runtime::RuntimeFlags::FromCompiler), processArgs);
            hookInvoker(static_cast<uint64_t>(RuntimeHookStage::PreMain), tlsIdPlusOne, static_cast<uint64_t>(Runtime::RuntimeFlags::FromCompiler), processArgs);
        }

        return Result::Continue;
    }

    struct RuntimeExceptionReport
    {
        Diagnostic      diag;
        SourceCodeRange codeRange;
    };

    struct DecodedRuntimeException
    {
        const Runtime::SourceCodeLocation* location = nullptr;
        std::string_view                   message;
        Runtime::ExceptionKind             kind = Runtime::ExceptionKind::Panic;
    };

    struct JitCrashFunctionMatch
    {
        const SymbolFunction* function     = nullptr;
        const MachineCode*    machineCode  = nullptr;
        uint64_t              entryAddress = 0;
        uint32_t              codeOffset   = 0;
    };

    enum class LocalFunctionAddressKind : uint8_t
    {
        Patchable,
        Callable,
    };

    bool asciiEqualsIgnoreCase(const std::string_view left, const std::string_view right)
    {
        if (left.size() != right.size())
            return false;

        for (size_t i = 0; i < left.size(); ++i)
        {
            char leftChar  = left[i];
            char rightChar = right[i];
            if ('A' <= leftChar && leftChar <= 'Z')
                leftChar = static_cast<char>(leftChar - 'A' + 'a');
            if ('A' <= rightChar && rightChar <= 'Z')
                rightChar = static_cast<char>(rightChar - 'A' + 'a');

            if (leftChar != rightChar)
                return false;
        }

        return true;
    }

    bool isKernel32ModuleName(const std::string_view moduleName)
    {
        return asciiEqualsIgnoreCase(moduleName, "kernel32") || asciiEqualsIgnoreCase(moduleName, "kernel32.dll");
    }

    [[noreturn]] void raiseJitProcessTerminationException(const char* functionName, const uint32_t exitCode)
    {
#ifdef _WIN32
        Utf8 message = std::format("jit code attempted to terminate the compiler process by calling {}({})", functionName, exitCode);
        if (const TaskContext* ctx = TaskContext::current())
        {
            if (const SymbolFunction* function = ctx->state().runJitFunction)
                message += std::format(" while running {}", function->getFullScopedName(*ctx));
        }

        const ULONG_PTR params[] = {
            0,
            reinterpret_cast<ULONG_PTR>(message.c_str()),
            (message.size()),
            static_cast<ULONG_PTR>(Runtime::ExceptionKind::Error),
        };

        RaiseException(K_COMPILER_EXCEPTION_CODE, 0, std::size(params), params);
#else
        SWC_UNUSED(functionName);
        SWC_UNUSED(exitCode);
#endif

        SWC_UNREACHABLE();
    }

#ifdef _WIN32
    // Windows can invoke FLS callbacks after their CompilerInstance is gone.
    // Track slots so the instance can release them while callback code is alive.
    struct JitFiberSlot
    {
        DWORD                  slot     = FLS_OUT_OF_INDEXES;
        PFLS_CALLBACK_FUNCTION callback = nullptr;
    };

    std::mutex& jitFiberSlotsMutex()
    {
        static std::mutex mutex;
        return mutex;
    }

    std::vector<JitFiberSlot>& jitFiberSlots()
    {
        static std::vector<JitFiberSlot> slots;
        return slots;
    }

    DWORD WINAPI jitTrackedFlsAlloc(const PFLS_CALLBACK_FUNCTION callback)
    {
        const DWORD slot = FlsAlloc(callback);
        if (slot != FLS_OUT_OF_INDEXES && callback)
        {
            const std::scoped_lock lock(jitFiberSlotsMutex());
            jitFiberSlots().push_back({.slot = slot, .callback = callback});
        }

        return slot;
    }

    BOOL WINAPI jitTrackedFlsFree(const DWORD slot)
    {
        {
            const std::scoped_lock lock(jitFiberSlotsMutex());
            std::erase_if(jitFiberSlots(), [slot](const JitFiberSlot& entry) { return entry.slot == slot; });
        }

        return FlsFree(slot);
    }

    [[noreturn]]
    void WINAPI jitBlockedExitProcess(const UINT exitCode)
    {
        raiseJitProcessTerminationException("ExitProcess", exitCode);
    }

    BOOL WINAPI jitBlockedTerminateProcess(HANDLE processHandle, const UINT exitCode)
    {
        // Allow terminating other processes, but never the compiler or a handle
        // whose process identity cannot be resolved.
        const DWORD targetProcessId = GetProcessId(processHandle);
        if (targetProcessId != 0 && targetProcessId != GetCurrentProcessId())
            return TerminateProcess(processHandle, exitCode);

        raiseJitProcessTerminationException("TerminateProcess", exitCode);
    }
#endif

    void* guardedForeignFunctionAddress(const std::string_view moduleName, const std::string_view functionName, void* functionAddress)
    {
#ifdef _WIN32
        if (isKernel32ModuleName(moduleName))
        {
            if (asciiEqualsIgnoreCase(functionName, "ExitProcess"))
                return reinterpret_cast<void*>(&jitBlockedExitProcess);
            if (asciiEqualsIgnoreCase(functionName, "TerminateProcess"))
                return reinterpret_cast<void*>(&jitBlockedTerminateProcess);
            if (asciiEqualsIgnoreCase(functionName, "FlsAlloc"))
                return reinterpret_cast<void*>(&jitTrackedFlsAlloc);
            if (asciiEqualsIgnoreCase(functionName, "FlsFree"))
                return reinterpret_cast<void*>(&jitTrackedFlsFree);
        }
#else
        SWC_UNUSED(moduleName);
        SWC_UNUSED(functionName);
#endif

        return functionAddress;
    }

    bool tryResolveForeignFunctionAddress(TaskContext& ctx, void*& outFunctionAddress, const SymbolFunction& targetFunction, RelocationResolveFailure* outFailure, JITRelocationPatchContext* patchContext = nullptr)
    {
        outFunctionAddress = nullptr;
        if (!targetFunction.isForeign())
        {
            if (outFailure)
            {
                outFailure->kind         = RelocationResolveFailureKind::TargetFunctionNotForeign;
                outFailure->targetSymbol = &targetFunction;
            }

            return false;
        }

        if (patchContext)
        {
            if (void* cached = patchContext->resolvedFunctionAddresses.find(&targetFunction))
            {
                outFunctionAddress = cached;
                return true;
            }
        }

        // The foreign module names the artifact to load ('ucrtbase' for system foreigns,
        // the origin module for imported interfaces); an imported module maps to the link
        // artifact dependency resolution selected for it.
        const Utf8             originModule = targetFunction.resolveForeignModuleName(ctx);
        const std::string_view moduleName   = ctx.compiler().runtimeImportLinkName(originModule.view());
        if (moduleName.empty())
        {
            if (outFailure)
            {
                outFailure->kind         = RelocationResolveFailureKind::ForeignModuleMissing;
                outFailure->targetSymbol = &targetFunction;
            }

            return false;
        }

        const Utf8 functionName = targetFunction.resolveForeignFunctionName(ctx);
        if (functionName.empty())
        {
            if (outFailure)
            {
                outFailure->kind         = RelocationResolveFailureKind::ForeignFunctionMissing;
                outFailure->targetSymbol = &targetFunction;
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
                outFailure->targetSymbol = &targetFunction;
                outFailure->moduleName   = Utf8(moduleName);
                outFailure->functionName = functionName;
            }

            return false;
        }

        outFunctionAddress = guardedForeignFunctionAddress(moduleName, functionName, functionAddress);
        if (!outFunctionAddress)
            return false;

        if (patchContext)
            patchContext->resolvedFunctionAddresses.set(&targetFunction, outFunctionAddress);

        return true;
    }

    Utf8 relocationSymbolName(const TaskContext& ctx, const Symbol* symbol)
    {
        if (!symbol)
            return {};

        return symbol->getFullScopedName(ctx);
    }

    DiagnosticId relocationDiagnosticId(const bool isForeign)
    {
        return isForeign ? DiagnosticId::cmd_err_native_invalid_foreign_function_relocation : DiagnosticId::cmd_err_native_invalid_local_function_relocation;
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

        SWC_ASSERT(numBits == 32 || numBits == 64);
        const uint64_t addr = reinterpret_cast<uint64_t>(ptr);

        if (numBits == 32)
        {
            uint32_t v32 = 0;
            if (tryReadHostValue(ptr, v32))
            {
                out += std::format("{} = [0x{:016X}] -> 0x{:08X}\n", label, addr, v32);
                return;
            }
        }
        else
        {
            uint64_t v64 = 0;
            if (tryReadHostValue(ptr, v64))
            {
                out += std::format("{} = [0x{:016X}] -> 0x{:016X}\n", label, addr, v64);
                return;
            }
        }

        out += std::format("{} = [0x{:016X}] -> <unreadable>\n", label, addr);
    }

    template<auto StateMember, auto OwnerMember>
    __forceinline auto fallbackWaitRef(const TaskContext& ctx, const SymbolFunction* ownerFunction)
    {
        using Ref = std::remove_cvref_t<decltype(ctx.state().*StateMember)>;
        if ((ctx.state().*StateMember).isValid())
            return ctx.state().*StateMember;
        if (ownerFunction)
            return (ownerFunction->*OwnerMember)();

        return Ref::invalid();
    }

    const SymbolFunction* waitOwnerFunction(const TaskContext& ctx, const SymbolFunction* ownerFunction, const SymbolFunction& targetFunction)
    {
        if (ownerFunction)
            return ownerFunction;
        if (ctx.state().runJitFunction)
            return ctx.state().runJitFunction;

        return &targetFunction;
    }

    TaskStateKind waitTaskKind(const LocalFunctionAddressKind addressKind)
    {
        switch (addressKind)
        {
            case LocalFunctionAddressKind::Patchable:
                return TaskStateKind::SemaWaitSymJitPrepared;

            case LocalFunctionAddressKind::Callable:
                return TaskStateKind::SemaWaitSymJitCompleted;
        }

        SWC_UNREACHABLE();
    }

    bool waiterIsJitWait(const TaskStateKind waitKind)
    {
        return waitKind == TaskStateKind::SemaWaitSymJitPrepared ||
               waitKind == TaskStateKind::SemaWaitSymJitPatched ||
               waitKind == TaskStateKind::SemaWaitSymJitCompleted;
    }

    bool hasLocalFunctionAddress(const SymbolFunction& targetFunction, const LocalFunctionAddressKind addressKind)
    {
        switch (addressKind)
        {
            case LocalFunctionAddressKind::Patchable:
                return targetFunction.jitWorkAddress() != nullptr;

            case LocalFunctionAddressKind::Callable:
                return targetFunction.jitEntryAddress() != nullptr;
        }

        SWC_UNREACHABLE();
    }

    void* localFunctionAddress(const SymbolFunction& targetFunction, const LocalFunctionAddressKind addressKind)
    {
        switch (addressKind)
        {
            case LocalFunctionAddressKind::Patchable:
                if (void* patchAddress = targetFunction.jitPatchAddress())
                    return patchAddress;

                return targetFunction.jitWorkAddress();

            case LocalFunctionAddressKind::Callable:
                return targetFunction.jitEntryAddress();
        }

        SWC_UNREACHABLE();
    }

    void setWaitFunctionTaskState(TaskContext& ctx, const TaskStateKind waitKind, const SymbolFunction* ownerFunction, const SymbolFunction& targetFunction, const bool useTargetFallback)
    {
        ownerFunction = waitOwnerFunction(ctx, ownerFunction, targetFunction);

        TaskState& wait   = ctx.state();
        wait.kind         = waitKind;
        wait.nodeRef      = fallbackWaitRef<&TaskState::nodeRef, &SymbolFunction::declNodeRef>(ctx, ownerFunction);
        wait.codeRef      = fallbackWaitRef<&TaskState::codeRef, &SymbolFunction::codeRefIfDeclared>(ctx, ownerFunction);
        wait.symbol       = &targetFunction;
        wait.waiterSymbol = ownerFunction;
        if (waiterIsJitWait(waitKind) && wait.waiterSymbol == &targetFunction)
            wait.waiterSymbol = nullptr;

        if (!useTargetFallback)
            return;

        if (wait.nodeRef.isInvalid())
            wait.nodeRef = targetFunction.declNodeRef();
        if (!wait.codeRef.isValid())
            wait.codeRef = targetFunction.codeRefIfDeclared();
    }

    void setWaitCodeGenCompleted(TaskContext& ctx, const SymbolFunction* ownerFunction, const SymbolFunction& targetFunction)
    {
        setWaitFunctionTaskState(ctx, TaskStateKind::SemaWaitSymCodeGenCompleted, ownerFunction, targetFunction, false);
    }

    void setWaitLocalFunctionAddress(TaskContext& ctx, const SymbolFunction* ownerFunction, const SymbolFunction& targetFunction, const LocalFunctionAddressKind addressKind)
    {
        setWaitFunctionTaskState(ctx, waitTaskKind(addressKind), ownerFunction, targetFunction, true);
    }

    Result ensureLocalFunctionCodeGenCompleted(TaskContext& ctx, SymbolFunction& targetFunction, const SymbolFunction* ownerFunction)
    {
        if (targetFunction.isCodeGenCompleted())
            return Result::Continue;
        if (targetFunction.isIgnored())
            return Result::Error;

        const SourceFile* targetFile = ctx.compiler().sourceViewFile(targetFunction);
        if (!targetFile)
            return Result::Error;

        Sema baseSema(ctx, ctx.compiler().file(targetFile->ref()).nodePayloadContext(), false);
        if (targetFunction.tryMarkCodeGenJobScheduled())
        {
            const AstNodeRef declRoot = targetFunction.declNodeRef();
            if (declRoot.isInvalid())
                return Result::Error;

            auto* job = ctx.compiler().makeJob<CodeGenJob>(ctx, baseSema, targetFunction, declRoot);
            ctx.compiler().global().jobMgr().enqueue(*job, JobPriority::Normal, ctx.compiler().jobClientId());
        }

        // Re-check only after codegen reaches a completed state. Pre-solved
        // progress is too early because dependencies can still expand.
        setWaitCodeGenCompleted(ctx, ownerFunction, targetFunction);
        return Result::Pause;
    }

    Result ensureLocalFunctionAddressReady(TaskContext& ctx, SymbolFunction& targetFunction, const SymbolFunction* ownerFunction, const LocalFunctionAddressKind addressKind)
    {
        if (hasLocalFunctionAddress(targetFunction, addressKind))
            return Result::Continue;

        const Result codeGenResult = ensureLocalFunctionCodeGenCompleted(ctx, targetFunction, ownerFunction);
        if (codeGenResult != Result::Continue)
            return codeGenResult;

        if (targetFunction.loweredCode().bytes.empty())
            return Result::Error;

        JITPatchJob::schedule(ctx, targetFunction);
        if (hasLocalFunctionAddress(targetFunction, addressKind))
            return Result::Continue;

        setWaitLocalFunctionAddress(ctx, ownerFunction, targetFunction, addressKind);
        return Result::Pause;
    }

    ABICall::Arg packArgValue(const ABITypeNormalize::NormalizedType& argType, const void* valuePtr)
    {
        SWC_ASSERT(valuePtr != nullptr);
        SWC_ASSERT(!argType.isIndirect);
        SWC_ASSERT(argType.numBits == 8 || argType.numBits == 16 || argType.numBits == 32 || argType.numBits == 64 || (argType.numBits == 128 && argType.isFloat));

        // A 128-bit packed value fills the two contiguous quads of the slot.
        static_assert(offsetof(ABICall::Arg, valueHi) == offsetof(ABICall::Arg, value) + sizeof(uint64_t));

        ABICall::Arg outArg;
        outArg.isFloat = argType.isFloat;
        outArg.numBits = argType.numBits;
        outArg.value   = 0;
        std::memcpy(&outArg.value, valuePtr, argType.numBits / 8);
        return outArg;
    }

    bool tryResolveDirectRelocationTargetAddress(uint64_t& outTargetAddress, const MicroRelocation& reloc, const uint8_t* basePtr)
    {
        outTargetAddress = reloc.targetAddress;
        if (outTargetAddress == MicroRelocation::K_SELF_ADDRESS)
        {
            outTargetAddress = reinterpret_cast<uint64_t>(basePtr);
            return true;
        }

        return outTargetAddress != 0;
    }

    bool tryResolveRelocationTargetFunction(SymbolFunction*& outTargetFunction, const MicroRelocation& reloc, RelocationResolveFailure* outFailure)
    {
        outTargetFunction    = nullptr;
        Symbol* targetSymbol = reloc.targetSymbol;
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

        outTargetFunction = &targetSymbol->cast<SymbolFunction>();
        return true;
    }

    Result resolveLocalFunctionSymbolTargetAddress(TaskContext& ctx, uint64_t& outTargetAddress, SymbolFunction& targetFunction, const SymbolFunction* ownerFunction, const LocalFunctionAddressKind addressKind, RelocationResolveFailure* outFailure, JITRelocationPatchContext* patchContext)
    {
        outTargetAddress = 0;
        if (patchContext)
        {
            if (void* cached = patchContext->resolvedFunctionAddresses.find(&targetFunction))
            {
                outTargetAddress = reinterpret_cast<uint64_t>(cached);
                return Result::Continue;
            }
        }

        const Result prepareResult = ensureLocalFunctionAddressReady(ctx, targetFunction, ownerFunction, addressKind);
        if (prepareResult != Result::Continue)
        {
            if (prepareResult == Result::Error && outFailure)
            {
                outFailure->kind         = RelocationResolveFailureKind::LocalTargetUnavailable;
                outFailure->targetSymbol = &targetFunction;
            }

            return prepareResult;
        }

        void* targetAddress = localFunctionAddress(targetFunction, addressKind);
        if (!targetAddress)
        {
            if (outFailure)
            {
                outFailure->kind         = RelocationResolveFailureKind::LocalTargetUnavailable;
                outFailure->targetSymbol = &targetFunction;
            }

            return Result::Error;
        }

        outTargetAddress = reinterpret_cast<uint64_t>(targetAddress);
        if (patchContext)
            patchContext->resolvedFunctionAddresses.set(&targetFunction, targetAddress);

        return outTargetAddress != 0 ? Result::Continue : Result::Error;
    }

    Result resolveFunctionSymbolTargetAddress(TaskContext& ctx, uint64_t& outTargetAddress, SymbolFunction& targetFunction, const SymbolFunction* ownerFunction, const LocalFunctionAddressKind addressKind, RelocationResolveFailure* outFailure, JITRelocationPatchContext* patchContext)
    {
        if (targetFunction.isForeign())
        {
            void* functionAddress = nullptr;
            if (!tryResolveForeignFunctionAddress(ctx, functionAddress, targetFunction, outFailure, patchContext))
                return Result::Error;

            outTargetAddress = reinterpret_cast<uint64_t>(functionAddress);
            return outTargetAddress != 0 ? Result::Continue : Result::Error;
        }

        return resolveLocalFunctionSymbolTargetAddress(ctx, outTargetAddress, targetFunction, ownerFunction, addressKind, outFailure, patchContext);
    }

    Result resolveLocalFunctionTargetAddress(TaskContext& ctx, uint64_t& outTargetAddress, const MicroRelocation& reloc, const uint8_t* basePtr, const SymbolFunction* ownerFunction, RelocationResolveFailure* outFailure, JITRelocationPatchContext* patchContext)
    {
        if (tryResolveDirectRelocationTargetAddress(outTargetAddress, reloc, basePtr))
            return Result::Continue;

        // Resolve the owner's address from the code being patched, avoiding a
        // copy of its relocation list with self-address markers on every patch.
        if (ownerFunction && reloc.targetSymbol == ownerFunction)
        {
            outTargetAddress = reinterpret_cast<uint64_t>(basePtr);
            return Result::Continue;
        }

        SymbolFunction* targetFunction = nullptr;
        if (!tryResolveRelocationTargetFunction(targetFunction, reloc, outFailure))
            return Result::Error;

        return resolveLocalFunctionSymbolTargetAddress(ctx, outTargetAddress, *targetFunction, ownerFunction, LocalFunctionAddressKind::Patchable, outFailure, patchContext);
    }

    bool resolveForeignFunctionTargetAddress(TaskContext& ctx, uint64_t& outTargetAddress, const MicroRelocation& reloc, const uint8_t* basePtr, RelocationResolveFailure* outFailure, JITRelocationPatchContext* patchContext)
    {
        if (tryResolveDirectRelocationTargetAddress(outTargetAddress, reloc, basePtr))
            return true;

        SymbolFunction* targetFunction = nullptr;
        if (!tryResolveRelocationTargetFunction(targetFunction, reloc, outFailure))
            return false;

        void* functionAddress = nullptr;
        if (!tryResolveForeignFunctionAddress(ctx, functionAddress, *targetFunction, outFailure, patchContext))
            return false;

        outTargetAddress = reinterpret_cast<uint64_t>(functionAddress);
        return outTargetAddress != 0;
    }

    Result resolveRelocationTargetAddress(TaskContext& ctx, uint64_t& outTargetAddress, const MicroRelocation& reloc, const uint8_t* basePtr, const SymbolFunction* ownerFunction, RelocationResolveFailure* outFailure, JITRelocationPatchContext* patchContext)
    {
        switch (reloc.kind)
        {
            case MicroRelocation::Kind::ConstantAddress:
            {
                // Private island copies use payload bytes without exposing the source's
                // identity. Its stable load address avoids recovering an allocation
                // that later payload appends may have moved.
                if (reloc.requiresConstantCopy())
                {
                    if (!reloc.hasConstantSource() || reloc.targetAddress == 0)
                        return Result::Error;

                    outTargetAddress = reloc.targetAddress;
                    return Result::Continue;
                }

                // Resolve segment-backed constants from their canonical source at
                // patch time, matching native lowering rather than the raw target.
                if (reloc.hasConstantSource())
                {
                    if (reloc.constantShard >= ConstantStorageLayout::SHARD_COUNT)
                        return Result::Error;

                    const auto* storage = ctx.compiler().cstMgr().shardDataSegment(reloc.constantShard).ptr<std::byte>(reloc.constantOffset);
                    if (!storage)
                        return Result::Error;

                    outTargetAddress = reinterpret_cast<uint64_t>(storage);
                    return Result::Continue;
                }

                outTargetAddress = reloc.targetAddress;
                return Result::Continue;
            }

            case MicroRelocation::Kind::LocalFunctionAddress:
                return resolveLocalFunctionTargetAddress(ctx, outTargetAddress, reloc, basePtr, ownerFunction, outFailure, patchContext);

            case MicroRelocation::Kind::ForeignFunctionAddress:
                return resolveForeignFunctionTargetAddress(ctx, outTargetAddress, reloc, basePtr, outFailure, patchContext) ? Result::Continue : Result::Error;

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

    Result reportRelocationFailure(TaskContext& ctx, DiagnosticId diagId, std::string_view symbolName, const RelocationResolveFailure& failure)
    {
        Diagnostic diag = Diagnostic::get(diagId);
        diag.addArgument(Diagnostic::ARG_SYM, symbolName);
        addRelocationFailureNotes(diag, ctx, failure);
        diag.report(ctx);
        return Result::Error;
    }

    RuntimeExceptionDiagnosticInfo runtimeExceptionDiagnosticInfo(Runtime::ExceptionKind kind)
    {
        switch (kind)
        {
            case Runtime::ExceptionKind::Panic:
                return {.diagId = DiagnosticId::sema_err_compiler_panic, .severity = DiagnosticSeverity::Error, .errorKind = JITCallErrorKind::HardwareException, .exceptionAction = SWC_EXCEPTION_EXECUTE_HANDLER};

            case Runtime::ExceptionKind::Error:
                return {.diagId = DiagnosticId::sema_err_compiler_error, .severity = DiagnosticSeverity::Error, .errorKind = JITCallErrorKind::HardwareException, .exceptionAction = SWC_EXCEPTION_EXECUTE_HANDLER};

            case Runtime::ExceptionKind::Warning:
                return {.diagId = DiagnosticId::sema_warn_compiler_warning, .severity = DiagnosticSeverity::Warning, .errorKind = JITCallErrorKind::None, .exceptionAction = SWC_EXCEPTION_CONTINUE_EXECUTION};

            case Runtime::ExceptionKind::Assert:
                return {.diagId = DiagnosticId::sema_err_assert_failed, .severity = DiagnosticSeverity::Error, .errorKind = JITCallErrorKind::HardwareException, .exceptionAction = SWC_EXCEPTION_EXECUTE_HANDLER};

            case Runtime::ExceptionKind::Safety:
                return {.diagId = DiagnosticId::safety_err_runtime, .severity = DiagnosticSeverity::Error, .errorKind = JITCallErrorKind::HardwareException, .exceptionAction = SWC_EXCEPTION_EXECUTE_HANDLER};

            default:
                SWC_UNREACHABLE();
        }
    }

    RuntimeExceptionReport buildRuntimeExceptionDiagnostic(TaskContext& ctx, const RuntimeExceptionDiagnosticInfo& info, const Runtime::SourceCodeLocation* location)
    {
        RuntimeExceptionReport                   report;
        CompilerInstance::ResolvedSourceLocation resolvedLocation;
        const bool                               hasResolvedLocation = location && ctx.compiler().tryResolveSourceLocation(ctx, resolvedLocation, *location);

        report.diag = Diagnostic::get(info.diagId, hasResolvedLocation && resolvedLocation.sourceFile ? resolvedLocation.sourceFile->ref() : FileRef::invalid());
        if (hasResolvedLocation)
        {
            report.diag.last().addSpan(resolvedLocation.codeRange, "", info.severity);
            report.codeRange = resolvedLocation.codeRange;
        }
        else if (location && location->fileName.ptr && location->fileName.length)
        {
            // Imported code may come from another compiler session with no mappable
            // source span. Keep its raw file coordinates available for the report.
            Utf8 rawLocation{std::string_view{location->fileName.ptr, location->fileName.length}};
            rawLocation += std::format(":{}:{}", location->lineStart, location->colStart);
            report.diag.addNote(DiagnosticId::sema_note_runtime_raise_location);
            report.diag.last().addArgument(Diagnostic::ARG_VALUE, rawLocation);
        }

        return report;
    }

    void patchAbsolute64(std::span<std::byte> writableCode, const MicroRelocation& reloc, uint64_t targetAddress)
    {
        auto*          basePtr        = reinterpret_cast<uint8_t*>(writableCode.data());
        const uint64_t patchEndOffset = static_cast<uint64_t>(reloc.codeOffset) + sizeof(uint64_t);
        SWC_ASSERT(patchEndOffset <= writableCode.size_bytes());
        std::memcpy(basePtr + reloc.codeOffset, &targetAddress, sizeof(targetAddress));
    }

    // Mutable globals must retain their canonical storage. The proximity arena
    // keeps direct RIP-relative displacements within signed 32-bit reach.
    bool tryPatchRelative32Direct(std::span<std::byte> writableCode, const MicroRelocation& reloc, uint64_t targetAddress)
    {
        auto* basePtr = reinterpret_cast<uint8_t*>(writableCode.data());

        const uint64_t patchEndOffset = static_cast<uint64_t>(reloc.codeOffset) + sizeof(uint32_t);
        SWC_ASSERT(patchEndOffset <= writableCode.size_bytes());
        SWC_ASSERT(reloc.relativeEndOffset >= patchEndOffset);

        const int64_t distance = static_cast<int64_t>(targetAddress) - static_cast<int64_t>(reinterpret_cast<uint64_t>(basePtr) + reloc.relativeEndOffset);
        if (distance < std::numeric_limits<int32_t>::min() || distance > std::numeric_limits<int32_t>::max())
            return false;

        const auto displacement = static_cast<int32_t>(distance);
        std::memcpy(basePtr + reloc.codeOffset, &displacement, sizeof(displacement));
        return true;
    }

    uint32_t reserveConstantIsland(uint32_t& islandOffset, const uint32_t size)
    {
        constexpr uint32_t ALIGNMENT = 16;
        islandOffset                 = Math::alignUpU32(islandOffset, ALIGNMENT);
        const uint32_t result        = islandOffset;
        islandOffset += Math::alignUpU32(size, ALIGNMENT);
        return result;
    }

    bool patchRelative32Function(std::span<std::byte> writableCode, const MicroRelocation& reloc, uint64_t targetAddress, uint32_t islandSlotOffset)
    {
        if (tryPatchRelative32Direct(writableCode, reloc, targetAddress))
            return true;

        auto*          basePtr = reinterpret_cast<uint8_t*>(writableCode.data());
        const uint64_t slotEnd = static_cast<uint64_t>(islandSlotOffset) + K_FUNCTION_THUNK_SLOT;
        SWC_ASSERT(slotEnd <= writableCode.size_bytes());

        // jmp qword ptr [rip+0]
        static constexpr std::array<uint8_t, 6> JUMP_THUNK = {0xFF, 0x25, 0x00, 0x00, 0x00, 0x00};
        std::memcpy(basePtr + islandSlotOffset, JUMP_THUNK.data(), JUMP_THUNK.size());
        std::memcpy(basePtr + islandSlotOffset + JUMP_THUNK.size(), &targetAddress, sizeof(targetAddress));

        const uint64_t thunkAddress = reinterpret_cast<uint64_t>(basePtr + islandSlotOffset);
        return tryPatchRelative32Direct(writableCode, reloc, thunkAddress);
    }

    bool isOptionalFunctionRelocationReady(const SymbolFunction& targetFunction)
    {
        if (targetFunction.isForeign())
            return true;
        if (targetFunction.isCodeGenCompleted())
            return true;
        return targetFunction.jitWorkAddress() || targetFunction.jitPatchAddress() || targetFunction.jitEntryAddress();
    }

    bool shouldLeaveOptionalFunctionRelocationUnresolved(const DataSegmentRelocation& relocation, const SymbolFunction& targetFunction)
    {
        if (!relocation.allowUnresolvedFunction)
            return false;
        if (targetFunction.hasExtraFlag(SymbolFunctionFlagsE::LazyBodyRunning))
            return true;

        return !isOptionalFunctionRelocationReady(targetFunction);
    }

    // 'outDataOnly' reports whether the allocation's whole constant graph holds no function
    // pointer, which is what lets the next function naming it skip the walk.
    Result patchConstantFunctionRelocationsRec(TaskContext& ctx, JITRelocationPatchContext& patchContext, const SymbolFunction* ownerFunction, const uint32_t shardIndex, const uint32_t sourceOffset, bool* outDataOnly = nullptr)
    {
        if (outDataOnly)
            *outDataOnly = false;

        DataSegment&                             segment = ctx.compiler().cstMgr().shardDataSegment(shardIndex);
        const ConstantManager::WalkedAllocation* walked  = ctx.compiler().cstMgr().walkedAllocation(shardIndex, sourceOffset);
        if (!walked)
            return Result::Continue;

        const DataSegmentAllocation allocation = walked->allocation;

        // Data-only graphs need no patching until relocations change. Read the
        // version before walking so a concurrent addition invalidates this result.
        const uint64_t relocationVersions = ctx.compiler().cstMgr().relocationVersionSum();
        if (walked->dataOnlyRelocationVersions == relocationVersions)
        {
            if (outDataOnly)
                *outDataOnly = true;
            return Result::Continue;
        }

        // Walk nested constant graphs once per allocation to patch function pointers
        // without cycles. The high bit makes even shard 0, offset 0 a nonzero key;
        // zero marks a free slot.
        const uint64_t visitKey = 1ULL << 63 | static_cast<uint64_t>(shardIndex) << 32 | allocation.offset;
        if (!patchContext.visitedConstantAllocations.insert(visitKey))
            return Result::Continue;

        // Keep an inline copy per recursion level: nested lookups can replace
        // entries in the worker's table.
        SmallVector<ConstantFunctionPatch>          patches;
        const SmallVector<DataSegmentRelocation, 4> relocations = walked->relocations;
        bool                                        dataOnly    = true;
        for (const DataSegmentRelocation& relocation : relocations)
        {
            if (relocation.kind == DataSegmentRelocationKind::DataSegmentOffset)
            {
                const uint32_t targetShardIndex = relocation.targetShardIndex == INVALID_REF ? shardIndex : relocation.targetShardIndex;
                bool           childDataOnly    = false;
                SWC_RESULT(patchConstantFunctionRelocationsRec(ctx, patchContext, ownerFunction, targetShardIndex, relocation.targetOffset, &childDataOnly));
                dataOnly = dataOnly && childDataOnly;
                continue;
            }

            SWC_ASSERT(relocation.kind == DataSegmentRelocationKind::FunctionSymbol);
            dataOnly = false;
            SWC_ASSERT(relocation.targetSymbol != nullptr);
            if (!relocation.targetSymbol)
                return Result::Error;

            SymbolFunction& targetFunction = *const_cast<SymbolFunction*>(relocation.targetSymbol);
            if (shouldLeaveOptionalFunctionRelocationUnresolved(relocation, targetFunction))
            {
                ctx.compiler().registerDeferredJitConstantFunction(targetFunction, {.shardIndex = shardIndex, .offset = relocation.offset});
                continue;
            }

            uint64_t                 targetAddress = 0;
            RelocationResolveFailure failure;

            const Result resolveResult = resolveFunctionSymbolTargetAddress(ctx, targetAddress, targetFunction, ownerFunction, LocalFunctionAddressKind::Patchable, &failure, &patchContext);

            if (resolveResult == Result::Pause)
                return Result::Pause;
            if (resolveResult != Result::Continue)
            {
                if (relocation.allowUnresolvedFunction && failure.kind == RelocationResolveFailureKind::LocalTargetUnavailable)
                {
                    ctx.compiler().registerDeferredJitConstantFunction(targetFunction, {.shardIndex = shardIndex, .offset = relocation.offset});
                    continue;
                }

                return reportRelocationFailure(ctx, relocationDiagnosticId(targetFunction.isForeign()), "<jit-constant>", failure);
            }

            patches.push_back({.offset = relocation.offset, .target = reinterpret_cast<void*>(targetAddress)});
        }

        if (!patches.empty())
        {
            const std::scoped_lock lock(segment.allocationMutex(allocation.offset));
            for (const ConstantFunctionPatch& patch : patches)
            {
                auto** storage = segment.ptr<void*>(patch.offset);
                SWC_ASSERT(storage != nullptr);
                *storage = patch.target;
            }
        }

        // The slot is this worker's and is reassigned only by a lookup of the same offset, which
        // the nested walks above never make for an allocation already visited.
        if (dataOnly)
            walked->dataOnlyRelocationVersions = relocationVersions;
        if (outDataOnly)
            *outDataOnly = dataOnly;

        return Result::Continue;
    }

    Result patchConstantFunctionRelocations(TaskContext& ctx, JITRelocationPatchContext& patchContext, const SymbolFunction* ownerFunction, const MicroRelocation& relocation, const void* ptr)
    {
        if (!ptr)
            return Result::Continue;

        // Address relocations have just resolved this exact source. Recovering it
        // from the pointer repeats the shard lookup. Island copies still name a
        // separate payload, so keep resolving their actual source address.
        if (relocation.hasConstantSource() && !relocation.requiresConstantCopy())
            return patchConstantFunctionRelocationsRec(ctx, patchContext, ownerFunction, relocation.constantShard, relocation.constantOffset);

        DataSegmentRef sourceRef;
        if (!ctx.compiler().cstMgr().resolveConstantDataSegmentRef(sourceRef, relocation.constantRef, ptr))
            return Result::Continue;

        return patchConstantFunctionRelocationsRec(ctx, patchContext, ownerFunction, sourceRef.shardIndex, sourceRef.offset);
    }

    Result patchRelocations(TaskContext& ctx, const SymbolFunction* ownerFunction, std::span<std::byte> writableCode, std::span<const MicroRelocation> relocations, uint32_t islandBase)
    {
        SWC_ASSERT(!writableCode.empty());
        if (relocations.empty())
            return Result::Continue;

        // Allocate island slots in the order measured by prepare(), avoiding a
        // stored slot offset in each relocation.
        uint32_t islandOffset = islandBase;

        const uint8_t* basePtr = reinterpret_cast<uint8_t*>(writableCode.data());
        SWC_ASSERT(basePtr != nullptr);

        // Share resolution caches across one function's relocations to avoid
        // repeated local-function preparation and foreign lookups.
        JITRelocationPatchContext patchContext;

        for (const MicroRelocation& reloc : relocations)
        {
            uint64_t                 targetAddress = 0;
            RelocationResolveFailure failure;

            const Result resolveResult = resolveRelocationTargetAddress(ctx, targetAddress, reloc, basePtr, ownerFunction, &failure, &patchContext);

            if (resolveResult == Result::Pause)
                return Result::Pause;
            if (resolveResult != Result::Continue)
            {
                if (reloc.kind == MicroRelocation::Kind::ConstantAddress)
                    return Result::Error;

                const bool isForeign = reloc.kind == MicroRelocation::Kind::ForeignFunctionAddress;
                if (ownerFunction)
                    return reportRelocationFailure(ctx, relocationDiagnosticId(isForeign), ownerFunction->getFullScopedName(ctx), failure);
                return reportRelocationFailure(ctx, relocationDiagnosticId(isForeign), "<jit>", failure);
            }

            if (reloc.kind == MicroRelocation::Kind::ConstantAddress)
                SWC_RESULT(patchConstantFunctionRelocations(ctx, patchContext, ownerFunction, reloc, reinterpret_cast<const void*>(targetAddress)));

            if (reloc.form == MicroRelocation::Form::Relative32)
            {
                if (reloc.kind == MicroRelocation::Kind::ConstantAddress ||
                    reloc.kind == MicroRelocation::Kind::GlobalZeroAddress ||
                    reloc.kind == MicroRelocation::Kind::GlobalInitAddress)
                {
                    if (reloc.requiresConstantCopy())
                    {
                        if (reloc.kind != MicroRelocation::Kind::ConstantAddress || !reloc.hasConstantSource())
                            return Result::Error;

                        const uint32_t copyOffset = reserveConstantIsland(islandOffset, reloc.constantCopySize);
                        if (static_cast<uint64_t>(copyOffset) + reloc.constantCopySize > writableCode.size_bytes())
                            return Result::Error;

                        auto* const copy = const_cast<std::byte*>(reinterpret_cast<const std::byte*>(basePtr)) + copyOffset;
                        std::memcpy(copy, reinterpret_cast<const void*>(targetAddress), reloc.constantCopySize);
                        if (!tryPatchRelative32Direct(writableCode, reloc, reinterpret_cast<uint64_t>(copy)))
                            return Result::Error;

                        continue;
                    }

                    // Identity-bearing pointers must target real segment storage, where
                    // nested relocations are patched in place. The proximity arena
                    // keeps these targets reachable without island copies.
                    if (!tryPatchRelative32Direct(writableCode, reloc, targetAddress))
                        return Result::Error;

                    continue;
                }

                if (reloc.kind == MicroRelocation::Kind::LocalFunctionAddress || reloc.kind == MicroRelocation::Kind::ForeignFunctionAddress)
                {
                    if (!patchRelative32Function(writableCode, reloc, targetAddress, islandOffset))
                        return Result::Error;

                    islandOffset += K_FUNCTION_THUNK_SLOT;
                    continue;
                }

                SWC_UNREACHABLE();
            }

            patchAbsolute64(writableCode, reloc, targetAddress);
        }

        return Result::Continue;
    }
}

void JIT::prepare(TaskContext& ctx, JITMemory& outExecutableMemory, const ByteArray& linearCode, const ByteArray& unwindInfo, const std::span<const MicroRelocation> relocations)
{
    prepare(ctx.compiler().jitMemMgr(), outExecutableMemory, linearCode, unwindInfo, relocations);
}

void JIT::prepare(JITMemoryManager& memoryManager, JITMemory& outExecutableMemory, const ByteArray& linearCode, const ByteArray& unwindInfo, const std::span<const MicroRelocation> relocations)
{
    SWC_ASSERT(!linearCode.empty());
    SWC_ASSERT(linearCode.size() <= std::numeric_limits<uint32_t>::max());

    // Allocate writable memory first. Relocations and optional unwind bytes are patched
    // before finalize() flips the page permissions and registers SEH metadata.
    const uint32_t codeSize          = Math::alignUpU32(static_cast<uint32_t>(linearCode.size()), sizeof(uint32_t));
    const bool     registerSehUnwind = !unwindInfo.empty();

    // Calls reserve nearby fallback thunks for targets outside rel32 reach.
    // Fixed-payload reads may also use nearby copies; address materializations
    // retain their canonical segment storage.
    uint32_t islandSize = 0;
    for (const MicroRelocation& relocation : relocations)
    {
        if (relocation.form != MicroRelocation::Form::Relative32)
            continue;

        if (relocation.requiresConstantCopy())
        {
            SWC_ASSERT(relocation.kind == MicroRelocation::Kind::ConstantAddress && relocation.hasConstantSource());
            reserveConstantIsland(islandSize, relocation.constantCopySize);
            continue;
        }

        // Arena-resident constants and globals patch straight to their storage.
        if (relocation.kind == MicroRelocation::Kind::ConstantAddress ||
            relocation.kind == MicroRelocation::Kind::GlobalZeroAddress ||
            relocation.kind == MicroRelocation::Kind::GlobalInitAddress)
            continue;

        SWC_ASSERT(relocation.kind == MicroRelocation::Kind::LocalFunctionAddress || relocation.kind == MicroRelocation::Kind::ForeignFunctionAddress);
        islandSize += K_FUNCTION_THUNK_SLOT;
    }

    const uint64_t unwindSizeU64     = registerSehUnwind ? unwindInfo.size() : 0;
    const uint64_t islandBaseU64     = Math::alignUpU64(static_cast<uint64_t>(codeSize) + unwindSizeU64, K_ISLAND_ALIGNMENT);
    const uint64_t islandSizeU64     = islandSize;
    const uint64_t allocationSizeU64 = islandSize ? islandBaseU64 + islandSizeU64 : static_cast<uint64_t>(codeSize) + unwindSizeU64;
    const uint32_t allocationSize    = static_cast<uint32_t>(allocationSizeU64);

    memoryManager.allocateWithCodeSize(outExecutableMemory, allocationSize, codeSize);

    if (islandSize)
    {
        outExecutableMemory.constantIslandOffset_ = static_cast<uint32_t>(islandBaseU64);
        outExecutableMemory.constantIslandSize_   = static_cast<uint32_t>(islandSizeU64);
    }

    std::span<std::byte> writableCode;
    writableCode = {static_cast<std::byte*>(outExecutableMemory.entryPoint()), linearCode.size()};
    std::memcpy(writableCode.data(), linearCode.data(), linearCode.size());

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

    // Expose all committed bytes, including storage beyond the initial code and
    // island extents. Later relocations can reserve fixed payloads beyond the
    // layout measured during preparation; the allocator commits full pages.
    const uint32_t  patchableSize = executableMemory.allocationSize_;
    const std::span writableCode{static_cast<std::byte*>(executableMemory.entryPoint()), patchableSize};
    return patchRelocations(ctx, ownerFunction, writableCode, relocations, executableMemory.constantIslandOffset_);
}

Result JIT::patchGlobalFunctionVariables(TaskContext& ctx)
{
    const auto globals = ctx.compiler().nativeGlobalFunctionVariablesSnapshot();
    if (globals.empty())
        return Result::Continue;

    const TaskScopedContext   scopedContext(ctx);
    JITRelocationPatchContext patchContext;

    const bool            patchReferencedGlobalsOnly = ctx.state().runJitFunction != nullptr;
    std::vector<uint64_t> sortedReferencedGlobalInitOffsets;

    // During a #run, patch only global-init slots referenced by the active JIT call graph.
    // Full native/JIT preparation still patches the complete snapshot.
    if (patchReferencedGlobalsOnly)
    {
        collectJitGlobalInitRelocationOffsets(ctx, sortedReferencedGlobalInitOffsets);
        if (sortedReferencedGlobalInitOffsets.empty())
            return Result::Continue;

        std::ranges::sort(sortedReferencedGlobalInitOffsets);
        const auto duplicates = std::ranges::unique(sortedReferencedGlobalInitOffsets);
        sortedReferencedGlobalInitOffsets.erase(duplicates.begin(), duplicates.end());
    }

    // Let the address cache grow with resolved functions instead of sizing it
    // for every global in the module.
    for (const SymbolVariable* symVar : globals)
    {
        SWC_ASSERT(symVar != nullptr);

        if (patchReferencedGlobalsOnly &&
            !referencesGlobalInitRange(sortedReferencedGlobalInitOffsets, symVar->offset(), sizeof(uint64_t)))
            continue;

        SWC_ASSERT(symVar->hasGlobalStorage());
        SWC_ASSERT(symVar->globalStorageKind() == DataSegmentKind::GlobalInit);

        SymbolFunction* targetFunction = symVar->globalFunctionInit();
        SWC_ASSERT(targetFunction != nullptr);

        const TypeInfo& storageType = ctx.typeMgr().get(symVar->typeRef());
        const uint64_t  storageSize = storageType.sizeOf(ctx);
        SWC_ASSERT(storageSize == sizeof(uint64_t));

        uint64_t                 targetAddress = 0;
        RelocationResolveFailure failure;

        const Result resolveResult = resolveFunctionSymbolTargetAddress(ctx, targetAddress, *targetFunction, nullptr, LocalFunctionAddressKind::Callable, &failure, &patchContext);

        if (resolveResult == Result::Pause)
            return Result::Pause;
        if (resolveResult != Result::Continue)
        {
            return reportRelocationFailure(ctx, relocationDiagnosticId(targetFunction->isForeign()), symVar->getFullScopedName(ctx), failure);
        }

        auto* storage = reinterpret_cast<uint64_t*>(ctx.compiler().dataSegmentAddress(DataSegmentKind::GlobalInit, symVar->offset()));
        SWC_ASSERT(storage != nullptr);
        *storage = targetAddress;
    }

    return Result::Continue;
}

void JIT::finalize(JITMemory& executableMemory)
{
    // Keep permission changes last: after this point the code buffer is executable and
    // should no longer be mutated except through the explicit patching APIs.
    JITMemoryManager::makeExecutable(executableMemory);
    JITMemoryManager::registerUnwindInfo(executableMemory);
}

Result JIT::emit(TaskContext& ctx, JITMemory& outExecutableMemory, const ByteArray& linearCode, std::span<const MicroRelocation> relocations, const ByteArray& unwindInfo, const SymbolFunction* ownerFunction)
{
    const TaskScopedContext scopedContext(ctx);
    prepare(ctx, outExecutableMemory, linearCode, unwindInfo, relocations);
    SWC_RESULT(patch(ctx, outExecutableMemory, relocations, ownerFunction));
    finalize(outExecutableMemory);
    return Result::Continue;
}

bool JIT::resolveForeignFunctionAddress(TaskContext& ctx, void*& outFunctionAddress, const SymbolFunction& targetFunction)
{
    const TaskScopedContext scopedContext(ctx);
    return tryResolveForeignFunctionAddress(ctx, outFunctionAddress, targetFunction, nullptr);
}

void* JIT::getNativeInterfaceAdapter(TaskContext& ctx, void* targetFn, const uint32_t numArgs)
{
    SWC_ASSERT(targetFn != nullptr);
    SWC_ASSERT(numArgs <= 2);

    struct Adapter
    {
        void*     targetFn = nullptr;
        uint32_t  numArgs  = 0;
        JITMemory memory;
    };

    struct AdapterCache
    {
        std::mutex           mutex;
        JITMemoryManager     memoryManager;
        std::vector<Adapter> entries;
    };

    // Imported DLL globals can retain runtime allocator interfaces after their CompilerInstance
    // is destroyed. Keep both the executable pages and their unwind registrations process-owned;
    // entries are destroyed before the manager releases those pages.
    static AdapterCache    cache;
    const std::scoped_lock lock(cache.mutex);
    for (const auto& entry : cache.entries)
    {
        if (entry.targetFn == targetFn && entry.numArgs == numArgs)
            return entry.memory.entryPoint();
    }

    const TaskScopedContext scopedContext(ctx);
    const CallConv&         incomingConv = CallConv::get(CallConvKind::Swag);
    const CallConv&         nativeConv   = CallConv::get(CallConvKind::C);
    for (uint32_t i = 0; i < numArgs; ++i)
        SWC_ASSERT(incomingConv.intArgRegs[i] == nativeConv.intArgRegs[i]);
    SWC_ASSERT(incomingConv.intReturn == nativeConv.intReturn);

    // These callbacks share the incoming integer lanes, but Swag callers do not reserve the
    // native ABI's shadow space. An explicit native call owns that space independently of the
    // caller's optimized frame. The pointer result stays in the common return register.
    MicroBuilder builder(ctx);

    // These process-owned bridges outlive compiler instances and configuration changes.
    // Optimize them independently of the configuration of their first caller.
    Runtime::BuildCfgBackend backendCfg{};
    backendCfg.optimLevel = Runtime::BuildCfgBackendOptimLevel::O1;
    builder.setBackendBuildCfg(backendCfg);
    builder.setRetUsesAbiRegs(true, false);

    const MicroReg targetReg = MicroReg::virtualIntReg(1);
    builder.emitLoadRegPtrImm(targetReg, reinterpret_cast<uint64_t>(targetFn));

    const ABICall::PreparedCall preparedCall = {
        .numPreparedArgs = numArgs,
        .intArgMask      = static_cast<uint8_t>((1u << numArgs) - 1u),
    };
    ABICall::callReg(builder, CallConvKind::C, targetReg, preparedCall);
    builder.emitRet();

    MachineCode loweredCode;
    SWC_INTERNAL_CHECK(loweredCode.emit(ctx, builder) == Result::Continue);
    SWC_ASSERT(loweredCode.codeRelocations.empty());

    JITMemory executableMemory;
    prepare(cache.memoryManager, executableMemory, loweredCode.bytes, loweredCode.unwindInfo, {});
    finalize(executableMemory);

    void* const entryPoint = executableMemory.entryPoint();
    cache.entries.push_back({targetFn, numArgs, std::move(executableMemory)});
    return entryPoint;
}

Result JIT::emitAndCall(TaskContext& ctx, void* targetFn, std::span<const JITArgument> args, const JITReturn& ret, CallConvKind callConvKind)
{
    const TaskScopedContext scopedContext(ctx);
    SWC_ASSERT(targetFn != nullptr);

    const CallConv&                        conv    = CallConv::get(callConvKind);
    const ABITypeNormalize::NormalizedType retType = ABITypeNormalize::normalize(ctx, conv, ctx.typeMgr().get(ret.typeRef), ABITypeNormalize::Usage::Return);
    SWC_ASSERT(retType.isVoid || ret.valuePtr);

    struct IndirectArgCopy
    {
        uint32_t argIndex;
        uint32_t storageOffset;
        uint32_t size;
    };

    SmallVector<ABICall::Arg>    packedArgs;
    SmallVector<IndirectArgCopy> indirectArgCopies;
    uint32_t                     indirectArgStorageSize = 0;
    const bool                   hasIndirectRetArg      = retType.isIndirect;
    const uint32_t               packedArgBaseOffset    = hasIndirectRetArg ? 1u : 0u;
    const bool                   directReturn           = !retType.isVoid && !retType.isIndirect;

    packedArgs.resize(args.size() + packedArgBaseOffset);

    SmallVector<uint16_t> signature;
    signature.reserve(packedArgs.size() + 1);
    signature.push_back(directReturn ? static_cast<uint16_t>(retType.numBits | (retType.isFloat ? 0x100 : 0)) : 0);

    if (hasIndirectRetArg)
    {
        packedArgs[0].value   = reinterpret_cast<uint64_t>(ret.valuePtr);
        packedArgs[0].isFloat = false;
        packedArgs[0].numBits = 64;
        signature.push_back(64);
    }

    const auto numArgs = static_cast<uint32_t>(args.size());
    for (uint32_t i = 0; i < numArgs; ++i)
    {
        const JITArgument&                     arg     = args[i];
        const ABITypeNormalize::NormalizedType argType = ABITypeNormalize::normalize(ctx, conv, ctx.typeMgr().get(arg.typeRef), ABITypeNormalize::Usage::Argument);
        SWC_ASSERT(!argType.isVoid);
        SWC_ASSERT(arg.valuePtr != nullptr);

        if (!argType.isIndirect)
        {
            packedArgs[i + packedArgBaseOffset] = packArgValue(argType, arg.valuePtr);
            signature.push_back(argType.isFloat ? static_cast<uint16_t>(argType.numBits | 0x100) : 64);
            continue;
        }

        if (argType.needsIndirectCopy)
        {
            indirectArgStorageSize         = Math::alignUpU32(indirectArgStorageSize, argType.indirectAlign);
            const uint64_t nextStorageSize = static_cast<uint64_t>(indirectArgStorageSize) + argType.indirectSize;
            SWC_ASSERT(nextStorageSize <= std::numeric_limits<uint32_t>::max());

            if (indirectArgCopies.empty())
                indirectArgCopies.reserve(args.size());
            indirectArgCopies.push_back({i, indirectArgStorageSize, argType.indirectSize});
            indirectArgStorageSize = static_cast<uint32_t>(nextStorageSize);
        }
        else
        {
            packedArgs[i + packedArgBaseOffset].value = reinterpret_cast<uint64_t>(arg.valuePtr);
        }

        packedArgs[i + packedArgBaseOffset].isFloat = false;
        packedArgs[i + packedArgBaseOffset].numBits = 64;
        signature.push_back(64);
    }

    SmallVector<uint8_t> indirectArgStorage;
    if (indirectArgStorageSize)
        indirectArgStorage.resize(indirectArgStorageSize);

    // Only copied arguments must wait until the complete storage area has a stable address.
    for (const IndirectArgCopy& copy : indirectArgCopies)
    {
        uint8_t* copyPtr = indirectArgStorage.data() + copy.storageOffset;
        std::memcpy(copyPtr, args[copy.argIndex].valuePtr, copy.size);
        packedArgs[copy.argIndex + packedArgBaseOffset].value = reinterpret_cast<uint64_t>(copyPtr);
    }

    struct CallFrame
    {
        void*               target;
        const ABICall::Arg* arguments;
        void*               result;
    };

    struct Invoker
    {
        CallConvKind callConv;
        bool         unwind;
        bool         debugInfo;

        SmallVector<uint16_t> signature;
        JITMemory             memory;
    };

    struct InvokerCache
    {
        JITMemoryManager     memoryManager;
        std::vector<Invoker> entries;
    };

    // The wrapper depends only on the ABI shape. All addresses and values arrive in a
    // per-call frame, including during recursive calls. Own its pages independently of any
    // CompilerInstance, and unregister unwind records before releasing those pages.
    thread_local InvokerCache cache;

    const auto& backend = ctx.compiler().buildCfg().backend;
    const bool  unwind  = ctx.compiler().cmdLine().targetOs == Runtime::TargetOs::Windows || backend.enableExceptions || backend.debugInfo;

    void* invoker = nullptr;
    for (const auto& entry : cache.entries)
    {
        if (entry.callConv == callConvKind && entry.unwind == unwind && entry.debugInfo == backend.debugInfo && entry.signature == signature)
        {
            invoker = entry.memory.entryPoint();
            break;
        }
    }

    if (!invoker)
    {
        MicroBuilder builder(ctx);

        const MicroReg frameReg  = MicroReg::virtualIntReg(1);
        const MicroReg argsReg   = MicroReg::virtualIntReg(2);
        const MicroReg targetReg = MicroReg::virtualIntReg(3);
        const MicroReg resultReg = MicroReg::virtualIntReg(4);

        builder.emitLoadRegReg(frameReg, CallConv::get(CallConvKind::C).intArgRegs[0], MicroOpBits::B64);
        builder.emitLoadRegMem(argsReg, frameReg, offsetof(CallFrame, arguments), MicroOpBits::B64);
        builder.emitLoadRegMem(targetReg, frameReg, offsetof(CallFrame, target), MicroOpBits::B64);
        if (directReturn)
            builder.emitLoadRegMem(resultReg, frameReg, offsetof(CallFrame, result), MicroOpBits::B64);

        SmallVector<ABICall::PreparedArg> preparedArgs;
        preparedArgs.reserve(packedArgs.size());
        for (uint32_t i = 0; i < packedArgs.size(); ++i)
        {
            const auto&    arg     = packedArgs[i];
            const uint8_t  numBits = arg.isFloat ? arg.numBits : 64;
            const MicroReg argReg  = arg.isFloat ? MicroReg::virtualFloatReg(i + 5) : MicroReg::virtualIntReg(i + 5);
            builder.emitLoadRegMem(argReg, argsReg, i * sizeof(ABICall::Arg), microOpBitsFromBitWidth(numBits));
            preparedArgs.push_back({.srcReg = argReg, .isFloat = arg.isFloat, .numBits = numBits});
        }

        const auto preparedCall = ABICall::prepareArgs(builder, callConvKind, preparedArgs);
        ABICall::callReg(builder, callConvKind, targetReg, preparedCall);
        if (directReturn)
            ABICall::storeReturnRegsToReturnBuffer(builder, callConvKind, resultReg, retType);
        builder.setRetUsesAbiRegs(false, false);
        builder.emitRet();

        MachineCode loweredCode;
        SWC_RESULT(loweredCode.emit(ctx, builder));
        SWC_ASSERT(loweredCode.codeRelocations.empty());

        JITMemory executableMemory;
        prepare(cache.memoryManager, executableMemory, loweredCode.bytes, loweredCode.unwindInfo, {});
        finalize(executableMemory);

        invoker = executableMemory.entryPoint();
        cache.entries.push_back({callConvKind, unwind, backend.debugInfo, std::move(signature), std::move(executableMemory)});
    }

    const CallFrame frame        = {targetFn, packedArgs.data(), ret.valuePtr};
    const uint64_t  frameAddress = reinterpret_cast<uint64_t>(&frame);
    return call(ctx, invoker, &frameAddress);
}

namespace
{
    std::string_view extractAssertConditionTextFromText(const SourceCodeRange& range)
    {
        if (!range.srcView || !range.len)
            return {};

        const std::string_view text = Utf8Helper::trim(range.srcView->codeView(range.offset, range.len));
        if (!text.starts_with("Swag.assert"))
            return {};

        const size_t openParen = text.find('(');
        if (openParen == std::string_view::npos || openParen + 1 >= text.size())
            return {};

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
            const auto   tokenStart = srcView.tokenByteStart(token);
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
            const auto   tokenStart = srcView.tokenByteStart(token);
            if (tokenStart >= rangeEnd)
                break;

            if (token.id == TokenId::SymLeftParen)
            {
                openParenRef = TokenRef(i);
                depth        = 1;

                for (uint32_t j = i + 1; j < tokens.size(); ++j)
                {
                    const Token& nestedToken = tokens[j];
                    const auto   nestedStart = srcView.tokenByteStart(nestedToken);
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
        const auto   openOffset = srcView.tokenByteStart(openParen) + openParen.byteLength;
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

    void decodeCompilerDiagnosticException(const void* platformExceptionPointers, DecodedRuntimeException& outException)
    {
        Runtime::Context* runtimeContext = CompilerInstance::runtimeContextFromTls();

#ifdef _WIN32
        // Compiler-side diagnostics are raised with RaiseException and already carry
        // the full payload in the SEH record. Prefer that transport so we keep the
        // exact location and message even if the runtime context layout changes.
        const auto* args   = static_cast<const EXCEPTION_POINTERS*>(platformExceptionPointers);
        const auto* record = args ? args->ExceptionRecord : nullptr;
        if (record && record->NumberParameters >= 4)
        {
            outException.location = reinterpret_cast<const Runtime::SourceCodeLocation*>(record->ExceptionInformation[0]);
            auto       msgPtr     = reinterpret_cast<const char*>(record->ExceptionInformation[1]);
            const auto msgCount   = static_cast<uint64_t>(record->ExceptionInformation[2]);
            outException.kind     = static_cast<Runtime::ExceptionKind>(record->ExceptionInformation[3]);
            if (msgPtr && msgCount)
                outException.message = {msgPtr, static_cast<size_t>(msgCount)};
        }
#endif

        if (!outException.location && runtimeContext)
            outException.location = &runtimeContext->exceptionLoc;

        if (outException.message.empty() && runtimeContext)
        {
            auto       msgPtr   = static_cast<const char*>(runtimeContext->exceptionParams[1]);
            const auto msgCount = reinterpret_cast<uintptr_t>(runtimeContext->exceptionParams[2]);
            outException.kind   = static_cast<Runtime::ExceptionKind>(reinterpret_cast<uintptr_t>(runtimeContext->exceptionParams[3]));
            if (msgPtr && msgCount)
                outException.message = {msgPtr, msgCount};
        }

        if (runtimeContext)
        {
            runtimeContext->exceptionParams[0] = nullptr;
            runtimeContext->exceptionParams[1] = nullptr;
            runtimeContext->exceptionParams[2] = nullptr;
            runtimeContext->exceptionParams[3] = nullptr;
        }
    }

    bool tryReportRuntimeException(TaskContext& ctx, const uint32_t exceptionCode, const void* platformExceptionPointers, JITCallErrorKind* outErrorKind, int& outExceptionAction)
    {
        if (exceptionCode != K_COMPILER_EXCEPTION_CODE)
            return false;

        DecodedRuntimeException decodedException;
        decodeCompilerDiagnosticException(platformExceptionPointers, decodedException);

        const RuntimeExceptionDiagnosticInfo info = runtimeExceptionDiagnosticInfo(decodedException.kind);
        *outErrorKind                             = info.errorKind;
        outExceptionAction                        = info.exceptionAction;

        RuntimeExceptionReport report = buildRuntimeExceptionDiagnostic(ctx, info, decodedException.location);

        Utf8 diagMessage = decodedException.message;
        if (decodedException.kind == Runtime::ExceptionKind::Assert)
        {
            if (diagMessage.empty())
                diagMessage = formatAssertDiagnosticMessage(extractAssertConditionText(report.codeRange));
            else
                diagMessage = formatAssertDiagnosticMessage(diagMessage);
        }

        if (!diagMessage.empty())
            report.diag.addArgument(Diagnostic::ARG_BECAUSE, diagMessage);

        report.diag.report(ctx);
        return true;
    }

    bool tryMatchJitFunctionAtRip(const SymbolFunction& function, uint64_t rip, JitCrashFunctionMatch& outMatch)
    {
        outMatch = {};

        const void* entryPtr = function.jitEntryAddress();
        if (!entryPtr)
            return false;

        const auto& code = function.loweredCode();
        if (code.bytes.empty())
            return false;

        const uint64_t entryAddress = reinterpret_cast<uint64_t>(entryPtr);
        const uint64_t codeEnd      = entryAddress + code.bytes.size();
        if (rip < entryAddress || rip >= codeEnd)
            return false;

        outMatch.function     = &function;
        outMatch.machineCode  = &code;
        outMatch.entryAddress = entryAddress;
        outMatch.codeOffset   = static_cast<uint32_t>(rip - entryAddress);
        return true;
    }

    bool tryResolveJitCrashFunction(const TaskContext& ctx, uint64_t rip, JitCrashFunctionMatch& outMatch)
    {
        outMatch = {};

        if (const SymbolFunction* currentFn = ctx.state().runJitFunction)
        {
            if (tryMatchJitFunctionAtRip(*currentFn, rip, outMatch))
                return true;
        }

        const auto preparedFunctions = ctx.compiler().jitPreparedFunctionsSnapshot();
        for (const SymbolFunction* function : preparedFunctions)
        {
            if (!function)
                continue;
            if (tryMatchJitFunctionAtRip(*function, rip, outMatch))
                return true;
        }

        return false;
    }

    bool tryResolveJitCrashSourceMatch(const TaskContext& ctx, const JitCrashFunctionMatch& functionMatch, MachineCode::ResolvedDebugSourceRange& outSourceMatch)
    {
        outSourceMatch = {};
        if (!functionMatch.machineCode)
            return false;

        return functionMatch.machineCode->tryResolveDebugSourceRangeAtOffset(ctx, outSourceMatch, functionMatch.codeOffset);
    }

    void appendCurrentJitFunctionContext(Utf8& out, const TaskContext& ctx)
    {
        const SymbolFunction* currentFn = ctx.state().runJitFunction;
        if (!currentFn)
            return;

        out += std::format("jit current function: {}\n", currentFn->getFullScopedName(ctx));
        out += std::format("jit current entry: 0x{:016X}\n", reinterpret_cast<uint64_t>(currentFn->jitEntryAddress()));
        out += std::format("jit current size: 0x{:X}\n", currentFn->loweredCode().bytes.size());
    }

    void appendJitByteDump(Utf8& out, const MachineCode& code, uint32_t codeOffset)
    {
        const uint32_t dumpStart = codeOffset > 8 ? codeOffset - 8 : 0;
        const uint32_t dumpEnd   = std::min<uint32_t>(static_cast<uint32_t>(code.bytes.size()), codeOffset + 8);

        out += "jit bytes:";
        for (uint32_t i = dumpStart; i < dumpEnd; ++i)
        {
            if (i == codeOffset)
                out += " |";
            out += std::format(" {:02X}", static_cast<uint8_t>(code.bytes[i]));
        }

        if (dumpEnd == codeOffset)
            out += " |";
        out += "\n";
    }

#ifdef _WIN32
    void appendJitStackSnapshot(Utf8& out, const CONTEXT& context)
    {
        out += "jit stack snapshot:\n";
        appendHostValue(out, "  [rsp+0x88]  x", reinterpret_cast<const void*>(context.Rsp + 0x88), 32);
        appendHostValue(out, "  [rsp+0x94]  y", reinterpret_cast<const void*>(context.Rsp + 0x94), 32);
        appendHostValue(out, "  [rsp+0x98]  dir", reinterpret_cast<const void*>(context.Rsp + 0x98), 32);
        appendHostValue(out, "  [rsp+0xB4]  startIndex", reinterpret_cast<const void*>(context.Rsp + 0xB4), 32);
        appendHostValue(out, "  [rsp+0x120] seenStates", reinterpret_cast<const void*>(context.Rsp + 0x120), 64);
        appendHostValue(out, "  [rsp+0x128] trace", reinterpret_cast<const void*>(context.Rsp + 0x128), 64);
        appendHostValue(out, "  [rsp+0x138] stateIndexAddr", reinterpret_cast<const void*>(context.Rsp + 0x138), 64);
        appendHostValue(out, "  [rsp+0xD8]  stateIndex", reinterpret_cast<const void*>(context.Rsp + 0xD8), 32);
        appendHostValue(out, "  [r13+0x0]   grid.width", reinterpret_cast<const void*>(context.R13 + 0x0), 32);
        appendHostValue(out, "  [r13+0x4]   grid.height", reinterpret_cast<const void*>(context.R13 + 0x4), 32);
        appendHostValue(out, "  [r13+0x8]   grid.startX", reinterpret_cast<const void*>(context.R13 + 0x8), 32);
        appendHostValue(out, "  [r13+0xC]   grid.startY", reinterpret_cast<const void*>(context.R13 + 0xC), 32);
        appendHostValue(out, "  [r13+0x10]  grid.cells", reinterpret_cast<const void*>(context.R13 + 0x10), 64);
    }
#endif

    Utf8 formatJitCrashContext(const TaskContext& ctx, const void* platformExceptionPointers)
    {
#ifdef _WIN32
        const auto* args    = static_cast<const EXCEPTION_POINTERS*>(platformExceptionPointers);
        const auto* context = args ? args->ContextRecord : nullptr;
        if (!context)
            return {};

        const uint64_t        rip = context->Rip;
        JitCrashFunctionMatch functionMatch;
        Utf8                  out;
        if (!tryResolveJitCrashFunction(ctx, rip, functionMatch))
        {
            appendCurrentJitFunctionContext(out, ctx);
            out += std::format("jit offset: unresolved (rip=0x{:016X})\n", rip);
            return out;
        }

        out += std::format("jit function: {}\n", functionMatch.function->getFullScopedName(ctx));
        out += std::format("jit entry: 0x{:016X}\n", functionMatch.entryAddress);
        out += std::format("jit offset: 0x{:X}\n", functionMatch.codeOffset);

        MachineCode::ResolvedDebugSourceRange sourceMatch;
        if (tryResolveJitCrashSourceMatch(ctx, functionMatch, sourceMatch))
        {
            if (sourceMatch.source.sourceFile)
                out += std::format("jit source: {}:{}:{}\n", sourceMatch.source.sourceFile->path().string(), sourceMatch.source.codeRange.line, sourceMatch.source.codeRange.column);

            SWC_ASSERT(sourceMatch.debugRange != nullptr);
            out += std::format("jit source span: [0x{:X}, 0x{:X})\n", sourceMatch.debugRange->codeStartOffset, sourceMatch.debugRange->codeEndOffset);
        }

        appendJitByteDump(out, *functionMatch.machineCode, functionMatch.codeOffset);
        appendJitStackSnapshot(out, *context);
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
        if (tryReportRuntimeException(ctx, exceptionCode, platformExceptionPointers, &outErrorKind, compilerDiagAction))
            return compilerDiagAction;

        if (!exceptionCode)
            outErrorKind = JITCallErrorKind::None;
        else
            outErrorKind = JITCallErrorKind::HardwareException;

        const Utf8 extraInfo = formatJitCrashContext(ctx, platformExceptionPointers);
        HardwareException::log(ctx, "fatal error: hardware exception during JIT call", platformExceptionPointers, extraInfo);
        Stats::addError();
        return SWC_EXCEPTION_EXECUTE_HANDLER;
    }

    Result ensureJitRuntimeSetup(TaskContext& ctx, RuntimeSetupInvoker& outSetupInvoker)
    {
        outSetupInvoker = nullptr;
        ctx.compiler().initPerThreadRuntimeContextForJit();
        if (!shouldUseSharedRuntimeSetup(ctx, ctx.state().runJitFunction))
            return Result::Continue;

        const IdentifierRef setupIdRef = ctx.idMgr().runtimeFunction(IdentifierManager::RuntimeFunctionKind::SetupRuntime);
        SymbolFunction*     setupFn    = ctx.compiler().runtimeFunctionSymbol(setupIdRef);
        SWC_ASSERT(setupFn != nullptr && setupFn->isSemaCompleted());
        if (!setupFn || !setupFn->isSemaCompleted())
            return Result::Error;

        SWC_RESULT(ensureLocalFunctionAddressReady(ctx, *setupFn, nullptr, LocalFunctionAddressKind::Callable));
        SWC_ASSERT(setupFn->jitEntryAddress() != nullptr);
        outSetupInvoker = reinterpret_cast<RuntimeSetupInvoker>(setupFn->jitEntryAddress());
        return Result::Continue;
    }
}

Result JIT::call(TaskContext& ctx, void* invoker, const uint64_t* arg0, JITCallErrorKind* outErrorKind, const JITRuntimeSetupMode setupMode)
{
    const TaskContext* savedContext = TaskContext::setCurrent(&ctx);
    SWC_ASSERT(invoker != nullptr);

    RuntimeSetupInvoker setupInvoker = nullptr;
    if (setupMode == JITRuntimeSetupMode::FromCompiler)
    {
        const Result setupResult = ensureJitRuntimeSetup(ctx, setupInvoker);
        if (setupResult != Result::Continue)
        {
            TaskContext::setCurrent(savedContext);
            return setupResult;
        }
    }
    else
    {
        ctx.compiler().initPerThreadRuntimeContextForJit();

        // Populate the effective command line at program entry; doing it during
        // codegen would also expose it to compile-time #run.
        ctx.compiler().ensureProcessInfoRunArgs();
    }

    bool hasException = false;
    auto callError    = JITCallErrorKind::None;
    auto callResult   = Result::Continue;

    SWC_TRY
    {
        if (setupInvoker)
            setupInvoker(Runtime::RuntimeFlags::FromCompiler);

        callResult = setupMode == JITRuntimeSetupMode::FromCompiler ? synchronizeImportedRuntimeContexts(ctx) : Result::Continue;
        if (callResult == Result::Continue)
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
    }
    SWC_EXCEPT(exceptionHandler(ctx, SWC_GET_EXCEPTION_INFOS(), callError))
    {
        hasException = true;
    }

    if (outErrorKind)
        *outErrorKind = hasException ? callError : JITCallErrorKind::None;

    if (callResult != Result::Continue)
    {
        TaskContext::setCurrent(savedContext);
        return callResult;
    }

    TaskContext::setCurrent(savedContext);
    return hasException ? Result::Error : Result::Continue;
}

void JIT::releaseThreadStorage(const std::function<bool(const void*)>& ownsCallback)
{
#ifdef _WIN32
    std::vector<DWORD> released;
    {
        const std::scoped_lock lock(jitFiberSlotsMutex());
        std::erase_if(jitFiberSlots(), [&](const JitFiberSlot& entry) {
            if (!ownsCallback(reinterpret_cast<const void*>(entry.callback)))
                return false;

            released.push_back(entry.slot);
            return true;
        });
    }

    // Freeing a slot runs its callback for every thread still holding a value in it, here, while
    // the code and the data the callback reaches are still alive.
    for (const DWORD slot : released)
        FlsFree(slot);
#else
    SWC_UNUSED(ownsCallback);
#endif
}

SWC_END_NAMESPACE();
