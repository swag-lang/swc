#include "pch.h"
#include "Main/CompilerInstance.h"
#include "Backend/Native/NativeArtifactBuilder.h"
#include "Backend/ABI/ABICall.h"
#include "Backend/Native/NativeBackendBuilder.h"
#include "Backend/Native/NativeNames.h"
#include "Backend/Native/NativeRDataCollector.h"
#include "Backend/Runtime.h"
#include "Backend/RuntimeName.h"
#include "Compiler/Sema/Symbol/Symbol.Function.h"
#include "Compiler/Sema/Symbol/Symbol.Variable.h"
#include "Main/Command/CommandLineParser.h"
#include "Main/FileSystem.h"
#include "Main/Global.h"
#include "Support/Os/Os.h"
#include "Support/Report/Assert.h"
#include "Support/Report/ScopedTimedLog.h"
#include "Support/Thread/JobManager.h"
#if SWC_HAS_VALIDATE_NATIVE
#include "Backend/Native/NativeValidate.h"
#endif

SWC_BEGIN_NAMESPACE();

class NativeStartupBuildJob final : public Job
{
public:
    NativeStartupBuildJob(const TaskContext& ctx, const NativeArtifactBuilder& artifactBuilder) :
        Job(ctx, JobKind::NativeArtifact),
        artifactBuilder_(&artifactBuilder)
    {
    }

    JobResult exec() override
    {
        ctx().state().setNone();
        SWC_ASSERT(artifactBuilder_ != nullptr);
        result_.store(artifactBuilder_->buildStartup(ctx()), std::memory_order_release);
        return JobResult::Done;
    }

    Result result() const noexcept
    {
        return result_.load(std::memory_order_acquire);
    }

private:
    const NativeArtifactBuilder* artifactBuilder_ = nullptr;
    std::atomic<Result>          result_          = Result::Continue;
};

namespace
{
    MicroReg nextVirtualIntReg(uint32_t& nextIndex)
    {
        return MicroReg::virtualIntReg(nextIndex++);
    }

    enum class RuntimeHookStage : uint64_t
    {
        Sync          = 0,
        Init          = 1,
        PreMain       = 2,
        Drop          = 3,
        DynamicLoad   = 4,
        DynamicUnload = 5,
    };

    constexpr uint32_t K_RUNTIME_HOOK_INIT_DONE             = 1u << 0;
    constexpr uint32_t K_RUNTIME_HOOK_PREMAIN_DONE          = 1u << 1;
    constexpr uint32_t K_RUNTIME_HOOK_DROP_DONE             = 1u << 2;
    constexpr uint32_t K_RUNTIME_HOOK_PREMAIN_COMPILER_DONE = 1u << 3;
    constexpr uint32_t K_RUNTIME_HOOK_STATIC_OWNER          = 1u << 4;

    uint32_t runtimeHookStageDoneMask(const RuntimeHookStage stage)
    {
        switch (stage)
        {
            case RuntimeHookStage::Init:
                return K_RUNTIME_HOOK_INIT_DONE;
            case RuntimeHookStage::PreMain:
                return K_RUNTIME_HOOK_PREMAIN_DONE;
            case RuntimeHookStage::Drop:
                return K_RUNTIME_HOOK_DROP_DONE;
        }

        SWC_UNREACHABLE();
    }

    // Values a runtime hook receives and passes down unchanged to its own dependencies, so that a
    // whole artifact graph shares one TLS context slot and one process command line.
    struct RuntimeHookArgs
    {
        MicroReg tlsIdPlusOne;
        MicroReg runtimeFlags;
        MicroReg processArgs;
    };

    void emitRuntimeDependencyHookCall(MicroBuilder& builder, const NativeRuntimeDependency& dependency, const RuntimeHookStage stage, const RuntimeHookArgs& hookArgs, uint32_t& nextVirtualIntRegIndex)
    {
        SWC_ASSERT(dependency.hookSymbol != nullptr);
        if (!dependency.hookSymbol)
            return;

        const MicroReg stageReg = nextVirtualIntReg(nextVirtualIntRegIndex);
        builder.emitLoadRegImm(stageReg, ApInt(static_cast<uint64_t>(stage), 64), MicroOpBits::B64);

        ABICall::PreparedArg directArg;
        directArg.kind    = ABICall::PreparedArgKind::Direct;
        directArg.numBits = 64;

        SmallVector<ABICall::PreparedArg> preparedArgs;
        directArg.srcReg = stageReg;
        preparedArgs.push_back(directArg);
        directArg.srcReg = hookArgs.tlsIdPlusOne;
        preparedArgs.push_back(directArg);
        directArg.srcReg = hookArgs.runtimeFlags;
        preparedArgs.push_back(directArg);
        directArg.srcReg = hookArgs.processArgs;
        preparedArgs.push_back(directArg);

        const CallConvKind          callConvKind = dependency.hookSymbol->callConvKind();
        const ABICall::PreparedCall preparedCall = ABICall::prepareArgs(builder, callConvKind, preparedArgs.span());
        ABICall::callExtern(builder, callConvKind, dependency.hookSymbol, preparedCall);
    }

    void emitRuntimeDependencyHookCalls(MicroBuilder& builder, const NativeBackendBuilder& nativeBuilder, std::span<const uint32_t> dependencyOrder, const RuntimeHookStage stage, const RuntimeHookArgs& hookArgs, uint32_t& nextVirtualIntRegIndex)
    {
        for (const uint32_t dependencyIndex : dependencyOrder)
        {
            SWC_ASSERT(dependencyIndex < nativeBuilder.runtimeDependencies.size());
            if (dependencyIndex >= nativeBuilder.runtimeDependencies.size())
                continue;

            emitRuntimeDependencyHookCall(builder, nativeBuilder.runtimeDependencies[dependencyIndex], stage, hookArgs, nextVirtualIntRegIndex);
        }
    }

    // Copies the caller's process command line into this artifact's own 'Swag.processInfos().args'.
    //
    // 'Swag.processInfos()' resolves to a per-artifact slot of the zero-initialized data segment, so every
    // executable and every shared library starts with its own empty copy. Whoever owns the real
    // command line -- the startup thunk of a native run, or the compiler for a JIT run -- passes it
    // down the hook chain, and each artifact adopts it here. Without this an imported module
    // answers 'Swag.args()' from a slot nobody ever filled, and code as ordinary as 'Env.hasArg' returns
    // a different answer depending on which module it was compiled into.
    void emitAdoptProcessArgs(MicroBuilder& builder, CompilerInstance& compiler, MicroReg processArgsReg, uint32_t& nextVirtualIntRegIndex)
    {
        const MicroLabelRef skipLabel = builder.createLabel();
        builder.emitCmpRegImm(processArgsReg, ApInt(0, 64), MicroOpBits::B64);
        builder.emitJumpToLabel(MicroCond::Equal, MicroOpBits::B32, skipLabel);

        const MicroReg targetReg = nextVirtualIntReg(nextVirtualIntRegIndex);
        builder.emitLoadRegDataSegmentReloc(targetReg, DataSegmentKind::GlobalZero, compiler.nativeProcessInfosOffset() + static_cast<uint32_t>(offsetof(Runtime::ProcessInfos, args)));

        const MicroReg wordReg = nextVirtualIntReg(nextVirtualIntRegIndex);
        for (uint64_t offset = 0; offset < sizeof(Runtime::String); offset += sizeof(uint64_t))
        {
            builder.emitLoadRegMem(wordReg, processArgsReg, offset, MicroOpBits::B64);
            builder.emitLoadMemReg(targetReg, offset, wordReg, MicroOpBits::B64);
        }

        builder.placeLabel(skipLabel);
    }

    void emitLifecycleCalls(MicroBuilder& builder, const std::span<SymbolFunction* const> functions)
    {
        for (const SymbolFunction* symbol : functions)
            ABICall::callLocal(builder, symbol->callConvKind(), symbol, {});
    }

    template<typename F>
    void emitGuardedLifecycleBody(MicroBuilder& builder, const RuntimeHookStage stage, const uint32_t lifecycleStateOffset, const F& body, uint32_t& nextVirtualIntRegIndex, const uint32_t doneMaskOverride = 0)
    {
        const MicroReg lifecycleStateReg = nextVirtualIntReg(nextVirtualIntRegIndex);
        builder.emitLoadRegDataSegmentReloc(lifecycleStateReg, DataSegmentKind::GlobalZero, lifecycleStateOffset);

        const MicroReg existingStateReg = nextVirtualIntReg(nextVirtualIntRegIndex);
        builder.emitLoadRegMem(existingStateReg, lifecycleStateReg, 0, MicroOpBits::B32);

        const MicroReg maskedStateReg = nextVirtualIntReg(nextVirtualIntRegIndex);
        builder.emitLoadRegReg(maskedStateReg, existingStateReg, MicroOpBits::B32);

        const uint32_t      doneMask  = doneMaskOverride ? doneMaskOverride : runtimeHookStageDoneMask(stage);
        const MicroLabelRef skipLabel = builder.createLabel();
        builder.emitOpBinaryRegImm(maskedStateReg, ApInt(doneMask, 64), MicroOp::And, MicroOpBits::B32);
        builder.emitCmpRegImm(maskedStateReg, ApInt(0, 64), MicroOpBits::B32);
        builder.emitJumpToLabel(MicroCond::NotEqual, MicroOpBits::B32, skipLabel);

        builder.emitOpBinaryRegImm(existingStateReg, ApInt(doneMask, 64), MicroOp::Or, MicroOpBits::B32);
        builder.emitLoadMemReg(lifecycleStateReg, 0, existingStateReg, MicroOpBits::B32);

        body();

        builder.placeLabel(skipLabel);
    }

    template<typename F>
    void emitGuardedRuntimeHookStage(MicroBuilder& builder, const MicroLabelRef stageLabel, const MicroLabelRef doneLabel, const RuntimeHookStage stage, const uint32_t lifecycleStateOffset, const F& body, uint32_t& nextVirtualIntRegIndex, const uint32_t doneMaskOverride = 0)
    {
        builder.placeLabel(stageLabel);
        emitGuardedLifecycleBody(builder, stage, lifecycleStateOffset, body, nextVirtualIntRegIndex, doneMaskOverride);
        builder.emitJumpToLabel(MicroCond::Unconditional, MicroOpBits::B32, doneLabel);
    }

    void emitAddLifecycleStateMask(MicroBuilder& builder, const uint32_t lifecycleStateOffset, const uint32_t mask, uint32_t& nextVirtualIntRegIndex)
    {
        const MicroReg lifecycleStateReg = nextVirtualIntReg(nextVirtualIntRegIndex);
        builder.emitLoadRegDataSegmentReloc(lifecycleStateReg, DataSegmentKind::GlobalZero, lifecycleStateOffset);

        const MicroReg stateReg = nextVirtualIntReg(nextVirtualIntRegIndex);
        builder.emitLoadRegMem(stateReg, lifecycleStateReg, 0, MicroOpBits::B32);
        builder.emitOpBinaryRegImm(stateReg, ApInt(mask, 64), MicroOp::Or, MicroOpBits::B32);
        builder.emitLoadMemReg(lifecycleStateReg, 0, stateReg, MicroOpBits::B32);
    }
}

NativeArtifactBuilder::NativeArtifactBuilder(NativeBackendBuilder& builder) :
    builder_(&builder)
{
}

Result NativeArtifactBuilder::build() const
{
#if SWC_HAS_VALIDATE_NATIVE
    if (builder_->ctx().cmdLine().validateNative)
    {
        const NativeValidate nativeValidate(*builder_);
        nativeValidate.validate();
    }
#endif
    SWC_RESULT(buildRuntimeHook(builder_->ctx()));
    if (builder_->ctx().global().jobMgr().numWorkers() == 0)
    {
        SWC_RESULT(buildStartup(builder_->ctx()));
        SWC_RESULT(prepareDataSections());
    }
    else
    {
        SWC_RESULT(buildStartupAndDataSectionsParallel());
    }

    return partitionObjects();
}

Result NativeArtifactBuilder::buildRuntimeHook(TaskContext& ctx) const
{
    switch (builder_->compiler().buildCfg().backendKind)
    {
        case Runtime::BuildCfgBackendKind::SharedLibrary:
        case Runtime::BuildCfgBackendKind::StaticLibrary:
            break;

        default:
            return Result::Continue;
    }

    CompilerInstance& compiler                                   = builder_->compiler();
    const auto [lifecycleStateOffset, lifecycleStateStorage]     = compiler.globalZeroSegment().reserve<uint32_t>();
    const auto [dynamicReferenceOffset, dynamicReferenceStorage] = compiler.globalZeroSegment().reserve<uint32_t>();
    auto* const lifecycleStatePtr                                = reinterpret_cast<uint32_t*>(lifecycleStateStorage);
    auto* const dynamicReferencePtr                              = reinterpret_cast<uint32_t*>(dynamicReferenceStorage);
    if (lifecycleStatePtr)
        *lifecycleStatePtr = 0;
    if (dynamicReferencePtr)
        *dynamicReferencePtr = 0;

    auto machineCode = std::make_unique<MachineCode>();

    MicroBuilder builder(builder_->ctx());
    builder.setBackendBuildCfg(compiler.buildCfg().backend);
    uint32_t nextVirtualIntRegIndex = builder.nextVirtualIntRegIndexHint();

    const CallConv& callConv = CallConv::swag();
    SWC_ASSERT(callConv.intArgRegs.size() >= 4);
    if (callConv.intArgRegs.size() < 4)
        return builder_->reportError(DiagnosticId::cmd_err_native_test_entry_lower_failed);

    const MicroReg stageReg = nextVirtualIntReg(nextVirtualIntRegIndex);
    builder.emitLoadRegReg(stageReg, callConv.intArgRegs[0], MicroOpBits::B64);

    RuntimeHookArgs hookArgs;

    hookArgs.tlsIdPlusOne = nextVirtualIntReg(nextVirtualIntRegIndex);
    builder.emitLoadRegReg(hookArgs.tlsIdPlusOne, callConv.intArgRegs[1], MicroOpBits::B64);

    hookArgs.runtimeFlags = nextVirtualIntReg(nextVirtualIntRegIndex);
    builder.emitLoadRegReg(hookArgs.runtimeFlags, callConv.intArgRegs[2], MicroOpBits::B64);

    hookArgs.processArgs = nextVirtualIntReg(nextVirtualIntRegIndex);
    builder.emitLoadRegReg(hookArgs.processArgs, callConv.intArgRegs[3], MicroOpBits::B64);

    const MicroReg tlsStorageReg = nextVirtualIntReg(nextVirtualIntRegIndex);
    builder.emitLoadRegDataSegmentReloc(tlsStorageReg, DataSegmentKind::GlobalZero, compiler.nativeRuntimeContextTlsIdOffset());
    builder.emitLoadMemReg(tlsStorageReg, 0, hookArgs.tlsIdPlusOne, MicroOpBits::B64);

    emitAdoptProcessArgs(builder, compiler, hookArgs.processArgs, nextVirtualIntRegIndex);

    const MicroLabelRef syncLabel            = builder.createLabel();
    const MicroLabelRef initLabel            = builder.createLabel();
    const MicroLabelRef preMainSelectLabel   = builder.createLabel();
    const MicroLabelRef preMainRuntimeLabel  = builder.createLabel();
    const MicroLabelRef preMainCompilerLabel = builder.createLabel();
    const MicroLabelRef dropLabel            = builder.createLabel();
    const MicroLabelRef dynamicLoadLabel     = builder.createLabel();
    const MicroLabelRef dynamicUnloadLabel   = builder.createLabel();
    const MicroLabelRef doneLabel            = builder.createLabel();

    builder.emitCmpRegImm(stageReg, ApInt(static_cast<uint64_t>(RuntimeHookStage::Sync), 64), MicroOpBits::B64);
    builder.emitJumpToLabel(MicroCond::Equal, MicroOpBits::B32, syncLabel);
    builder.emitCmpRegImm(stageReg, ApInt(static_cast<uint64_t>(RuntimeHookStage::Init), 64), MicroOpBits::B64);
    builder.emitJumpToLabel(MicroCond::Equal, MicroOpBits::B32, initLabel);
    builder.emitCmpRegImm(stageReg, ApInt(static_cast<uint64_t>(RuntimeHookStage::PreMain), 64), MicroOpBits::B64);
    builder.emitJumpToLabel(MicroCond::Equal, MicroOpBits::B32, preMainSelectLabel);
    builder.emitCmpRegImm(stageReg, ApInt(static_cast<uint64_t>(RuntimeHookStage::Drop), 64), MicroOpBits::B64);
    builder.emitJumpToLabel(MicroCond::Equal, MicroOpBits::B32, dropLabel);
    builder.emitCmpRegImm(stageReg, ApInt(static_cast<uint64_t>(RuntimeHookStage::DynamicLoad), 64), MicroOpBits::B64);
    builder.emitJumpToLabel(MicroCond::Equal, MicroOpBits::B32, dynamicLoadLabel);
    builder.emitCmpRegImm(stageReg, ApInt(static_cast<uint64_t>(RuntimeHookStage::DynamicUnload), 64), MicroOpBits::B64);
    builder.emitJumpToLabel(MicroCond::Equal, MicroOpBits::B32, dynamicUnloadLabel);
    builder.emitJumpToLabel(MicroCond::Unconditional, MicroOpBits::B32, doneLabel);

    builder.placeLabel(syncLabel);
    emitRuntimeDependencyHookCalls(builder, *builder_, builder_->runtimeDependencyInitOrder, RuntimeHookStage::Sync, hookArgs, nextVirtualIntRegIndex);
    builder.emitJumpToLabel(MicroCond::Unconditional, MicroOpBits::B32, doneLabel);

    builder.placeLabel(initLabel);
    emitAddLifecycleStateMask(builder, lifecycleStateOffset, K_RUNTIME_HOOK_STATIC_OWNER, nextVirtualIntRegIndex);
    emitGuardedLifecycleBody(builder, RuntimeHookStage::Init, lifecycleStateOffset, [&] {
        emitRuntimeDependencyHookCalls(builder, *builder_, builder_->runtimeDependencyInitOrder, RuntimeHookStage::Init, hookArgs, nextVirtualIntRegIndex);
        emitLifecycleCalls(builder, builder_->initFunctions); }, nextVirtualIntRegIndex);
    builder.emitJumpToLabel(MicroCond::Unconditional, MicroOpBits::B32, doneLabel);

    builder.placeLabel(preMainSelectLabel);
    const MicroReg preMainFlagsReg = nextVirtualIntReg(nextVirtualIntRegIndex);
    builder.emitLoadRegReg(preMainFlagsReg, hookArgs.runtimeFlags, MicroOpBits::B64);
    builder.emitOpBinaryRegImm(preMainFlagsReg, ApInt(static_cast<uint64_t>(Runtime::RuntimeFlags::FromCompiler), 64), MicroOp::And, MicroOpBits::B64);
    builder.emitCmpRegImm(preMainFlagsReg, ApInt(0, 64), MicroOpBits::B64);
    builder.emitJumpToLabel(MicroCond::NotEqual, MicroOpBits::B32, preMainCompilerLabel);
    builder.emitJumpToLabel(MicroCond::Unconditional, MicroOpBits::B32, preMainRuntimeLabel);

    emitGuardedRuntimeHookStage(builder, preMainRuntimeLabel, doneLabel, RuntimeHookStage::PreMain, lifecycleStateOffset, [&] {
        emitRuntimeDependencyHookCalls(builder, *builder_, builder_->runtimeDependencyInitOrder, RuntimeHookStage::PreMain, hookArgs, nextVirtualIntRegIndex);
        emitLifecycleCalls(builder, builder_->preMainFunctions); }, nextVirtualIntRegIndex);

    emitGuardedRuntimeHookStage(builder, preMainCompilerLabel, doneLabel, RuntimeHookStage::PreMain, lifecycleStateOffset, [&] {
        emitRuntimeDependencyHookCalls(builder, *builder_, builder_->runtimeDependencyInitOrder, RuntimeHookStage::PreMain, hookArgs, nextVirtualIntRegIndex);
        emitLifecycleCalls(builder, builder_->preMainFunctions); }, nextVirtualIntRegIndex, K_RUNTIME_HOOK_PREMAIN_COMPILER_DONE);

    emitGuardedRuntimeHookStage(builder, dropLabel, doneLabel, RuntimeHookStage::Drop, lifecycleStateOffset, [&] {
        emitLifecycleCalls(builder, builder_->dropFunctions);
        emitRuntimeDependencyHookCalls(builder, *builder_, builder_->runtimeDependencyDropOrder, RuntimeHookStage::Drop, hookArgs, nextVirtualIntRegIndex); }, nextVirtualIntRegIndex);

    builder.placeLabel(dynamicLoadLabel);
    emitRuntimeDependencyHookCalls(builder, *builder_, builder_->runtimeDependencyInitOrder, RuntimeHookStage::DynamicLoad, hookArgs, nextVirtualIntRegIndex);
    {
        const MicroReg referenceReg = nextVirtualIntReg(nextVirtualIntRegIndex);
        builder.emitLoadRegDataSegmentReloc(referenceReg, DataSegmentKind::GlobalZero, dynamicReferenceOffset);
        const MicroReg countReg = nextVirtualIntReg(nextVirtualIntRegIndex);
        builder.emitLoadRegMem(countReg, referenceReg, 0, MicroOpBits::B32);
        builder.emitOpBinaryRegImm(countReg, ApInt(1, 64), MicroOp::Add, MicroOpBits::B32);
        builder.emitLoadMemReg(referenceReg, 0, countReg, MicroOpBits::B32);
    }
    emitGuardedLifecycleBody(builder, RuntimeHookStage::Init, lifecycleStateOffset, [&] { emitLifecycleCalls(builder, builder_->initFunctions); }, nextVirtualIntRegIndex);

    {
        const MicroLabelRef dynamicPreMainCompilerLabel = builder.createLabel();
        const MicroLabelRef dynamicPreMainDoneLabel     = builder.createLabel();
        const MicroReg      dynamicPreMainFlagsReg      = nextVirtualIntReg(nextVirtualIntRegIndex);
        builder.emitLoadRegReg(dynamicPreMainFlagsReg, hookArgs.runtimeFlags, MicroOpBits::B64);
        builder.emitOpBinaryRegImm(dynamicPreMainFlagsReg, ApInt(static_cast<uint64_t>(Runtime::RuntimeFlags::FromCompiler), 64), MicroOp::And, MicroOpBits::B64);
        builder.emitCmpRegImm(dynamicPreMainFlagsReg, ApInt(0, 64), MicroOpBits::B64);
        builder.emitJumpToLabel(MicroCond::NotEqual, MicroOpBits::B32, dynamicPreMainCompilerLabel);
        emitGuardedLifecycleBody(builder, RuntimeHookStage::PreMain, lifecycleStateOffset, [&] { emitLifecycleCalls(builder, builder_->preMainFunctions); }, nextVirtualIntRegIndex);
        builder.emitJumpToLabel(MicroCond::Unconditional, MicroOpBits::B32, dynamicPreMainDoneLabel);
        builder.placeLabel(dynamicPreMainCompilerLabel);
        emitGuardedLifecycleBody(builder, RuntimeHookStage::PreMain, lifecycleStateOffset, [&] { emitLifecycleCalls(builder, builder_->preMainFunctions); }, nextVirtualIntRegIndex, K_RUNTIME_HOOK_PREMAIN_COMPILER_DONE);
        builder.placeLabel(dynamicPreMainDoneLabel);
    }
    builder.emitJumpToLabel(MicroCond::Unconditional, MicroOpBits::B32, doneLabel);

    builder.placeLabel(dynamicUnloadLabel);
    {
        const MicroReg referenceReg = nextVirtualIntReg(nextVirtualIntRegIndex);
        builder.emitLoadRegDataSegmentReloc(referenceReg, DataSegmentKind::GlobalZero, dynamicReferenceOffset);
        const MicroReg countReg = nextVirtualIntReg(nextVirtualIntRegIndex);
        builder.emitLoadRegMem(countReg, referenceReg, 0, MicroOpBits::B32);

        const MicroLabelRef releaseDependenciesLabel = builder.createLabel();
        builder.emitCmpRegImm(countReg, ApInt(0, 64), MicroOpBits::B32);
        builder.emitJumpToLabel(MicroCond::Equal, MicroOpBits::B32, releaseDependenciesLabel);
        builder.emitOpBinaryRegImm(countReg, ApInt(1, 64), MicroOp::Subtract, MicroOpBits::B32);
        builder.emitLoadMemReg(referenceReg, 0, countReg, MicroOpBits::B32);
        builder.emitCmpRegImm(countReg, ApInt(0, 64), MicroOpBits::B32);
        builder.emitJumpToLabel(MicroCond::NotEqual, MicroOpBits::B32, releaseDependenciesLabel);

        const MicroReg lifecycleStateReg = nextVirtualIntReg(nextVirtualIntRegIndex);
        builder.emitLoadRegDataSegmentReloc(lifecycleStateReg, DataSegmentKind::GlobalZero, lifecycleStateOffset);
        const MicroReg staticOwnerReg = nextVirtualIntReg(nextVirtualIntRegIndex);
        builder.emitLoadRegMem(staticOwnerReg, lifecycleStateReg, 0, MicroOpBits::B32);
        builder.emitOpBinaryRegImm(staticOwnerReg, ApInt(K_RUNTIME_HOOK_STATIC_OWNER, 64), MicroOp::And, MicroOpBits::B32);
        builder.emitCmpRegImm(staticOwnerReg, ApInt(0, 64), MicroOpBits::B32);
        builder.emitJumpToLabel(MicroCond::NotEqual, MicroOpBits::B32, releaseDependenciesLabel);

        emitGuardedLifecycleBody(builder, RuntimeHookStage::Drop, lifecycleStateOffset, [&] { emitLifecycleCalls(builder, builder_->dropFunctions); }, nextVirtualIntRegIndex);

        builder.placeLabel(releaseDependenciesLabel);
    }
    emitRuntimeDependencyHookCalls(builder, *builder_, builder_->runtimeDependencyDropOrder, RuntimeHookStage::DynamicUnload, hookArgs, nextVirtualIntRegIndex);
    builder.emitJumpToLabel(MicroCond::Unconditional, MicroOpBits::B32, doneLabel);

    builder.placeLabel(doneLabel);
    builder.emitRet();

    if (machineCode->emit(ctx, builder) != Result::Continue)
        return builder_->reportError(DiagnosticId::cmd_err_native_test_entry_lower_failed);

    NativeFunctionInfo info;
    info.machineCode = machineCode.get();
    info.sortKey     = runtimeHookSymbolName(nativeArtifactScopeName(compiler).view());
    info.symbolName  = info.sortKey;
    if (compiler.buildCfg().backendKind == Runtime::BuildCfgBackendKind::SharedLibrary)
        info.exportName = K_SHARED_RUNTIME_HOOK_SYMBOL;
    info.debugName = std::format("{}::__runtimeHook", nativeArtifactScopeName(compiler));
    info.exported  = compiler.buildCfg().backendKind == Runtime::BuildCfgBackendKind::SharedLibrary;

    builder_->generatedMachineCodes.push_back(std::move(machineCode));
    builder_->functionInfos.push_back(std::move(info));
    builder_->functionBySymbol.clear();
    for (const auto& functionInfo : builder_->functionInfos)
    {
        if (functionInfo.symbol)
            builder_->functionBySymbol.emplace(functionInfo.symbol, &functionInfo);
    }
    return Result::Continue;
}

Result NativeArtifactBuilder::prepareOutputFolders() const
{
    NativeArtifactPaths paths;
    queryPaths(paths, static_cast<uint32_t>(builder_->objectDescriptions.size()));
    SWC_RESULT(createBuildDir(paths.buildDir));
    SWC_RESULT(createOutDir(paths.outDir));
    if (!paths.staticLibraryPath.empty())
        SWC_RESULT(createOutDir(paths.staticLibraryPath.parent_path()));
    return Result::Continue;
}

void NativeArtifactBuilder::queryPaths(NativeArtifactPaths& outPaths, const uint32_t numObjects) const
{
    outPaths.workDir.clear();
    outPaths.buildDir.clear();
    outPaths.objectPaths.clear();
    const auto buildCfgName = Utf8(builder_->compiler().buildCfg().name);
    if (!buildCfgName.empty())
        outPaths.name = FileSystem::sanitizeFileName(buildCfgName);
    else
        outPaths.name = defaultArtifactName(builder_->ctx().cmdLine());

    // The mode travels in the name, so the artifact, its PDB, and its object files
    // are all distinct from the ones another mode produces from the same sources.
    outPaths.name += artifactModeSuffix(builder_->ctx().cmdLine());

    const auto buildCfgWorkDir = Utf8(builder_->compiler().buildCfg().workDir);
    if (!buildCfgWorkDir.empty())
        outPaths.workDir = fs::path(buildCfgWorkDir.c_str());
    if (outPaths.workDir.empty())
    {
        const CommandLine&    cmdLine = builder_->ctx().cmdLine();
        std::vector<fs::path> roots;
        if (!cmdLine.modulePath.empty())
            roots.push_back(FileSystem::absolutePathNoThrow(cmdLine.modulePath.parent_path()));

        for (const fs::path& input : cmdLine.files)
        {
            fs::path root = input.parent_path();
            if (root.empty())
                root = input;

            root = FileSystem::absolutePathNoThrow(root);
            if (!root.empty())
                roots.push_back(root);
        }

        for (const fs::path& input : cmdLine.directories)
        {
            fs::path root = FileSystem::absolutePathNoThrow(input);
            if (!root.empty())
                roots.push_back(root);
        }

        fs::path sourceRoot;
        if (!roots.empty())
        {
            sourceRoot = roots.front();
            for (size_t i = 1; i < roots.size(); ++i)
            {
                fs::path commonRoot;
                auto     lhsIt = sourceRoot.begin();
                auto     rhsIt = roots[i].begin();
                while (lhsIt != sourceRoot.end() && rhsIt != roots[i].end() && *lhsIt == *rhsIt)
                {
                    commonRoot /= *lhsIt;
                    ++lhsIt;
                    ++rhsIt;
                }

                sourceRoot = std::move(commonRoot);
                if (sourceRoot.empty())
                {
                    sourceRoot = roots.front();
                    break;
                }
            }

            if (sourceRoot == sourceRoot.root_path())
                sourceRoot = roots.front();
        }

        if (sourceRoot.empty())
            sourceRoot = FileSystem::currentPathNoThrow();
        outPaths.workDir = sourceRoot / ".output" / automaticWorkDirName(outPaths.name).c_str();
    }

    outPaths.buildDir          = outPaths.workDir;
    outPaths.artifactExtension = artifactExtension();
    const auto buildCfgOutDir  = Utf8(builder_->compiler().buildCfg().outDir);
    if (!buildCfgOutDir.empty())
        outPaths.outDir = fs::path(buildCfgOutDir.c_str());
    else
        outPaths.outDir = outPaths.workDir;
    outPaths.artifactPath = outPaths.outDir / std::format("{}{}", outPaths.name, outPaths.artifactExtension);
    outPaths.pdbPath      = outPaths.outDir / std::format("{}.pdb", outPaths.name);

    // A shared library also publishes the archive built from the same objects, so that an
    // executable can link this module's code in instead of importing it from the DLL.
    const fs::path& staticLibraryOutDir = builder_->ctx().cmdLine().staticLibraryOutDir;
    if (!staticLibraryOutDir.empty() && builder_->compiler().buildCfg().backendKind == Runtime::BuildCfgBackendKind::SharedLibrary)
        outPaths.staticLibraryPath = staticLibraryOutDir / std::format("{}.lib", outPaths.name);

    if (!numObjects)
        return;

    outPaths.objectPaths.clear();
    outPaths.objectPaths.reserve(numObjects);
    const Utf8 objectExt = objectExtension();
    for (uint32_t i = 0; i < numObjects; ++i)
        outPaths.objectPaths.push_back(outPaths.buildDir / std::format("{}_{:02}{}", outPaths.name, i, objectExt).c_str());
}

Utf8 NativeArtifactBuilder::artifactExtension() const
{
    switch (builder_->ctx().cmdLine().targetOs)
    {
        case Runtime::TargetOs::Windows:
            switch (builder_->compiler().buildCfg().backendKind)
            {
                case Runtime::BuildCfgBackendKind::Executable:
                    return ".exe";
                case Runtime::BuildCfgBackendKind::SharedLibrary:
                    return ".dll";
                case Runtime::BuildCfgBackendKind::StaticLibrary:
                    return ".lib";
                case Runtime::BuildCfgBackendKind::Export:
                case Runtime::BuildCfgBackendKind::None:
                    break;
            }

            break;
    }

    SWC_UNREACHABLE();
}

Utf8 NativeArtifactBuilder::objectExtension() const
{
    switch (builder_->ctx().cmdLine().targetOs)
    {
        case Runtime::TargetOs::Windows:
            return ".obj";
    }

    SWC_UNREACHABLE();
}

Result NativeArtifactBuilder::createOutDir(const fs::path& outDir) const
{
    std::error_code ec;
    fs::create_directories(outDir, ec);
    if (ec)
        return builder_->reportError(DiagnosticId::cmd_err_native_work_dir_create_failed, Diagnostic::ARG_PATH, Utf8(outDir), Diagnostic::ARG_BECAUSE, ec.message());
    return Result::Continue;
}

Utf8 NativeArtifactBuilder::automaticWorkDirName(const Utf8& name) const
{
    const CommandLine& cmdLine = builder_->ctx().cmdLine();
    Utf8               key;

    key += std::format("cmd={};os={};arch={};backend={};sub={};name={};", static_cast<int>(cmdLine.command), static_cast<int>(cmdLine.targetOs), static_cast<int>(cmdLine.targetArch), static_cast<int>(builder_->compiler().buildCfg().backendKind), static_cast<int>(builder_->compiler().buildCfg().backendSubKind), name);

    if (!cmdLine.modulePath.empty())
    {
        key += "module=";
        key += Utf8(cmdLine.modulePath);
        key += ";";
    }

    for (const fs::path& file : cmdLine.files)
    {
        key += "file=";
        key += Utf8(file);
        key += ";";
    }

    for (const fs::path& directory : cmdLine.directories)
    {
        key += "directory=";
        key += Utf8(directory);
        key += ";";
    }

    for (const fs::path& file : cmdLine.importApiFiles)
    {
        key += "import-api-file=";
        key += Utf8(file);
        key += ";";
    }

    for (const fs::path& directory : cmdLine.importApiDirs)
    {
        key += "import-api-dir=";
        key += Utf8(directory);
        key += ";";
    }

    // Keep the auto-generated work dir deterministic for a given command line so cleanup
    // and incremental native builds operate in the same location.
    const uint32_t hash = static_cast<uint32_t>(std::hash<std::string_view>{}(key.view()));
    return std::format("{}_{:08x}", FileSystem::sanitizeFileName(name), hash);
}

Result NativeArtifactBuilder::createBuildDir(const fs::path& buildDir) const
{
    std::error_code ec;
    fs::create_directories(buildDir, ec);
    if (ec)
        return builder_->reportError(DiagnosticId::cmd_err_native_work_dir_create_failed, Diagnostic::ARG_PATH, Utf8(buildDir), Diagnostic::ARG_BECAUSE, ec.message());
    return Result::Continue;
}

Result NativeArtifactBuilder::prepareDataSections() const
{
    resetDataSections();

    NativeRDataCollector collector(*builder_);
    SWC_RESULT(collector.collectStartupRoots());
    SWC_RESULT(prepareDataSectionsWithoutStartup(collector));
    return finishDataSections(collector);
}

Result NativeArtifactBuilder::buildStartupAndDataSectionsParallel() const
{
    resetDataSections();

    JobManager&          jobMgr     = builder_->ctx().global().jobMgr();
    auto*                startupJob = builder_->compiler().makeJob<NativeStartupBuildJob>(builder_->ctx(), *this);
    NativeRDataCollector collector(*builder_);
    const JobClientId    clientId = builder_->compiler().jobClientId();
    jobMgr.enqueue(*startupJob, JobPriority::Normal, clientId);

    const Result dataResult = prepareDataSectionsWithoutStartup(collector);
    jobMgr.waitAll(clientId);

    SWC_RESULT(startupJob->result());
    SWC_RESULT(dataResult);
    SWC_RESULT(collector.collectStartupRoots());
    return finishDataSections(collector);
}

void NativeArtifactBuilder::resetDataSections() const
{
    builder_->mergedRData.name            = ".rdata";
    builder_->mergedRData.characteristics = IMAGE_SCN_CNT_INITIALIZED_DATA | IMAGE_SCN_MEM_READ | IMAGE_SCN_ALIGN_16BYTES;
    builder_->mergedData.name             = ".data";
    builder_->mergedData.characteristics  = IMAGE_SCN_CNT_INITIALIZED_DATA | IMAGE_SCN_MEM_READ | IMAGE_SCN_MEM_WRITE | IMAGE_SCN_ALIGN_16BYTES;
    builder_->mergedBss.name              = ".bss";
    builder_->mergedBss.characteristics   = IMAGE_SCN_CNT_UNINITIALIZED_DATA | IMAGE_SCN_MEM_READ | IMAGE_SCN_MEM_WRITE | IMAGE_SCN_ALIGN_16BYTES;

    CompilerInstance& compiler = builder_->compiler();

    builder_->mergedRData.bytes.clear();
    builder_->mergedRData.relocations.clear();
    builder_->mergedData.bytes.clear();
    builder_->mergedData.relocations.clear();
    builder_->mergedBss.bssSize = compiler.globalZeroSegment().extentSize();
    builder_->mergedBss.bss     = builder_->mergedBss.bssSize != 0;
    for (auto& mappings : builder_->rdataAllocationMap)
        mappings.clear();
}

Result NativeArtifactBuilder::prepareDataSectionsWithoutStartup(NativeRDataCollector& rdataCollector) const
{
    // Emitted function code is the source of truth for native constant roots.
    // Startup roots are collected after startup lowering has completed.
    SWC_RESULT(rdataCollector.collectFunctionRoots());

    CompilerInstance& compiler = builder_->compiler();
    const uint32_t    dataSize = compiler.globalInitSegment().extentSize();
    if (dataSize)
    {
        builder_->mergedData.bytes.resize(dataSize);
        compiler.globalInitSegment().copyToPreserveOffsets(std::span{builder_->mergedData.bytes.data(), dataSize});

        const std::vector<DataSegmentRelocation> relocations = compiler.globalInitSegment().copyRelocations();
        for (const auto& relocation : relocations)
        {
            NativeSectionRelocation record;
            record.offset = relocation.offset;
            if (relocation.kind == DataSegmentRelocationKind::DataSegmentOffset)
            {
                record.symbolName = nativeScopedSectionBaseSymbol(builder_->compiler(), K_DATA_BASE_SYMBOL);
                record.addend     = relocation.targetOffset;
            }
            else
            {
                SWC_ASSERT(relocation.kind == DataSegmentRelocationKind::FunctionSymbol);
                SWC_RESULT(builder_->resolveFunctionSymbolName(record.symbolName, relocation.targetSymbol));
                record.addend = 0;
            }

            builder_->mergedData.relocations.push_back(record);
        }

        for (const SymbolVariable* symbol : builder_->regularGlobals)
        {
            if (!symbol)
                continue;
            if (!symbol->hasGlobalStorage())
                continue;
            if (symbol->globalStorageKind() != DataSegmentKind::GlobalInit)
                continue;

            const SymbolFunction* targetFunction = symbol->globalFunctionInit();
            if (!targetFunction)
                continue;

            const uint64_t storageSize = builder_->ctx().typeMgr().get(symbol->typeRef()).sizeOf(builder_->ctx());
            SWC_ASSERT(storageSize == sizeof(uint64_t));

            NativeSectionRelocation record;
            record.offset = symbol->offset();
            SWC_RESULT(builder_->resolveFunctionSymbolName(record.symbolName, targetFunction));
            record.addend = 0;
            builder_->mergedData.relocations.push_back(record);
        }
    }

    return Result::Continue;
}

Result NativeArtifactBuilder::finishDataSections(NativeRDataCollector& rdataCollector)
{
    return rdataCollector.emitCollectedRoots();
}

Result NativeArtifactBuilder::partitionObjects() const
{
    builder_->objectDescriptions.clear();

    const size_t functionCount = builder_->functionInfos.size();
    uint32_t     maxJobs       = builder_->ctx().cmdLine().numCores;
    if (!maxJobs)
        maxJobs = std::max<uint32_t>(1, builder_->ctx().global().jobMgr().numWorkers());
    if (!maxJobs)
        maxJobs = 1;

    const uint32_t numJobs = std::max<uint32_t>(1, static_cast<uint32_t>(functionCount ? std::min<size_t>(functionCount, maxJobs) : 1));
    builder_->objectDescriptions.resize(numJobs);

    NativeArtifactPaths paths;
    queryPaths(paths, numJobs);
    builder_->buildDir     = paths.buildDir;
    builder_->artifactPath = paths.artifactPath;
    builder_->pdbPath      = paths.pdbPath;

    // Object 0 owns shared sections/startup, so the remaining objects only need code.
    for (uint32_t i = 0; i < numJobs; ++i)
    {
        builder_->objectDescriptions[i].index       = i;
        builder_->objectDescriptions[i].includeData = i == 0;
        builder_->objectDescriptions[i].objPath     = paths.objectPaths[i];
    }

    if (builder_->startup)
        builder_->objectDescriptions[0].startup = builder_->startup.get();

    for (size_t i = 0; i < builder_->functionInfos.size(); ++i)
    {
        NativeFunctionInfo& info     = builder_->functionInfos[i];
        const uint32_t      objIndex = static_cast<uint32_t>(i % numJobs);
        info.jobIndex                = objIndex;
        builder_->objectDescriptions[objIndex].functions.push_back(&info);
    }
    return Result::Continue;
}

Result NativeArtifactBuilder::partitionArchiveObjects() const
{
    builder_->objectDescriptions.clear();

    // One object per function, plus object 0 which owns the data sections and nothing else. The
    // startup thunk belongs to executables, and an executable publishes no archive.
    const size_t   functionCount = builder_->functionInfos.size();
    const uint32_t numObjects    = static_cast<uint32_t>(functionCount + 1);
    builder_->objectDescriptions.resize(numObjects);

    NativeArtifactPaths paths;
    queryPaths(paths, numObjects);

    for (uint32_t i = 0; i < numObjects; ++i)
    {
        builder_->objectDescriptions[i].index       = i;
        builder_->objectDescriptions[i].includeData = i == 0;
        builder_->objectDescriptions[i].objPath     = paths.objectPaths[i];
    }

    for (size_t i = 0; i < functionCount; ++i)
    {
        NativeFunctionInfo& info     = builder_->functionInfos[i];
        const uint32_t      objIndex = static_cast<uint32_t>(i + 1);
        info.jobIndex                = objIndex;
        builder_->objectDescriptions[objIndex].functions.push_back(&info);
    }

    return Result::Continue;
}

Result NativeArtifactBuilder::buildStartup(TaskContext& ctx) const
{
    builder_->startup.reset();

    if (builder_->compiler().buildCfg().backendKind != Runtime::BuildCfgBackendKind::Executable)
        return Result::Continue;
    // Source-driven native tests can legitimately build an executable with no user-defined
    // #main: #test and lifecycle hooks still need a startup thunk to run.
    if (builder_->mainFunctions.empty() && builder_->testFunctions.empty() && builder_->initFunctions.empty() && builder_->preMainFunctions.empty() && builder_->dropFunctions.empty())
        return builder_->reportError(DiagnosticId::cmd_err_native_main_missing);

    auto         startup = std::make_unique<NativeStartupInfo>();
    MicroBuilder builder(builder_->ctx());
    builder.setBackendBuildCfg(builder_->compiler().buildCfg().backend);
    uint32_t nextVirtualIntRegIndex = builder.nextVirtualIntRegIndexHint();

    const IdentifierRef   setupRuntimeIdRef = ctx.idMgr().runtimeFunction(IdentifierManager::RuntimeFunctionKind::SetupRuntime);
    const IdentifierRef   closeRuntimeIdRef = ctx.idMgr().runtimeFunction(IdentifierManager::RuntimeFunctionKind::CloseRuntime);
    const SymbolFunction* setupRuntimeFn    = builder_->compiler().runtimeFunctionSymbol(setupRuntimeIdRef);
    const SymbolFunction* closeRuntimeFn    = builder_->compiler().runtimeFunctionSymbol(closeRuntimeIdRef);
    SWC_ASSERT(setupRuntimeFn != nullptr);
    SWC_ASSERT(closeRuntimeFn != nullptr);
    if (!setupRuntimeFn || !closeRuntimeFn)
        return builder_->reportError(DiagnosticId::cmd_err_native_test_entry_lower_failed);

    const MicroReg runtimeFlagsReg = nextVirtualIntReg(nextVirtualIntRegIndex);
    builder.emitLoadRegImm(runtimeFlagsReg, ApInt(static_cast<uint64_t>(Runtime::RuntimeFlags::Zero), 64), MicroOpBits::B64);

    ABICall::PreparedArg runtimeFlagsArg;
    runtimeFlagsArg.srcReg  = runtimeFlagsReg;
    runtimeFlagsArg.kind    = ABICall::PreparedArgKind::Direct;
    runtimeFlagsArg.numBits = 64;

    SmallVector<ABICall::PreparedArg> setupRuntimeArgs;
    setupRuntimeArgs.push_back(runtimeFlagsArg);

    const ABICall::PreparedCall preparedSetupRuntime = ABICall::prepareArgs(builder, setupRuntimeFn->callConvKind(), setupRuntimeArgs);
    ABICall::callLocal(builder, setupRuntimeFn->callConvKind(), setupRuntimeFn, preparedSetupRuntime);

    const MicroReg tlsStorageReg = nextVirtualIntReg(nextVirtualIntRegIndex);
    builder.emitLoadRegDataSegmentReloc(tlsStorageReg, DataSegmentKind::GlobalZero, builder_->compiler().nativeRuntimeContextTlsIdOffset());

    RuntimeHookArgs hookArgs;
    hookArgs.runtimeFlags = runtimeFlagsReg;

    hookArgs.tlsIdPlusOne = nextVirtualIntReg(nextVirtualIntRegIndex);
    builder.emitLoadRegMem(hookArgs.tlsIdPlusOne, tlsStorageReg, 0, MicroOpBits::B64);

    // '__setupRuntime' has just read the real command line from the operating system into this
    // executable's own 'Swag.processInfos().args'. Hand that slot down the hook chain so every imported module
    // adopts it: 'Swag.processInfos()' is per-artifact, so without this 'Swag.args()' answers the executable and
    // comes back empty in every shared library, and the runtime's own 'swag.test' guard -- which
    // is what makes a '#test' run at all -- never sees the argument the compiler passed.
    hookArgs.processArgs = nextVirtualIntReg(nextVirtualIntRegIndex);
    builder.emitLoadRegDataSegmentReloc(hookArgs.processArgs, DataSegmentKind::GlobalZero, builder_->compiler().nativeProcessInfosOffset() + static_cast<uint32_t>(offsetof(Runtime::ProcessInfos, args)));

    // The startup thunk runs compiler-generated lifecycle hooks and then hands off
    // process termination to the runtime wrapper for the active target.
    emitRuntimeDependencyHookCalls(builder, *builder_, builder_->runtimeDependencyInitOrder, RuntimeHookStage::Init, hookArgs, nextVirtualIntRegIndex);
    emitLifecycleCalls(builder, builder_->initFunctions);
    emitRuntimeDependencyHookCalls(builder, *builder_, builder_->runtimeDependencyInitOrder, RuntimeHookStage::PreMain, hookArgs, nextVirtualIntRegIndex);
    emitLifecycleCalls(builder, builder_->preMainFunctions);

    // #test functions run through the runtime test runner: __runTest reports and
    // counts a failing test (assert/panic) without stopping the remaining ones, and
    // __testsDone prints the executed/failed tally the compiler parses back.
    if (!builder_->testFunctions.empty())
    {
        const IdentifierRef   runTestIdRef   = ctx.idMgr().runtimeFunction(IdentifierManager::RuntimeFunctionKind::RunTest);
        const IdentifierRef   testsDoneIdRef = ctx.idMgr().runtimeFunction(IdentifierManager::RuntimeFunctionKind::TestsDone);
        const SymbolFunction* runTestFn      = builder_->compiler().runtimeFunctionSymbol(runTestIdRef);
        const SymbolFunction* testsDoneFn    = builder_->compiler().runtimeFunctionSymbol(testsDoneIdRef);
        SWC_ASSERT(runTestFn != nullptr && testsDoneFn != nullptr);
        if (!runTestFn || !testsDoneFn)
            return builder_->reportError(DiagnosticId::cmd_err_native_test_entry_lower_failed);

        for (const SymbolFunction* symbol : builder_->testFunctions)
        {
            const MicroReg testFnReg = nextVirtualIntReg(nextVirtualIntRegIndex);
            builder.emitLoadRegPtrReloc(testFnReg, 0, ConstantRef::invalid(), symbol);

            const Utf8           testName    = ScopedTimedLog::formatTestLocation(ctx, *symbol);
            const ConstantRef    testNameRef = ctx.cstMgr().addConstant(ctx, ConstantValue::makeString(ctx, testName));
            const ConstantValue& testNameCst = ctx.cstMgr().get(testNameRef);
            const MicroReg       testNameReg = nextVirtualIntReg(nextVirtualIntRegIndex);
            builder.emitLoadRegPtrReloc(testNameReg, reinterpret_cast<uint64_t>(testNameCst.getString().data()), testNameRef);

            ABICall::PreparedArg testFnArg;
            testFnArg.srcReg  = testFnReg;
            testFnArg.kind    = ABICall::PreparedArgKind::Direct;
            testFnArg.numBits = 64;

            ABICall::PreparedArg testNameArg;
            testNameArg.srcReg  = testNameReg;
            testNameArg.kind    = ABICall::PreparedArgKind::Direct;
            testNameArg.numBits = 64;

            SmallVector<ABICall::PreparedArg> runTestArgs;
            runTestArgs.push_back(testFnArg);
            runTestArgs.push_back(testNameArg);

            const ABICall::PreparedCall preparedRunTest = ABICall::prepareArgs(builder, runTestFn->callConvKind(), runTestArgs);
            ABICall::callLocal(builder, runTestFn->callConvKind(), runTestFn, preparedRunTest);
        }

        const ABICall::PreparedCall preparedTestsDone = ABICall::prepareArgs(builder, testsDoneFn->callConvKind(), {});
        ABICall::callLocal(builder, testsDoneFn->callConvKind(), testsDoneFn, preparedTestsDone);
    }
    // The test command runs a module's #test functions and nothing else. Letting #main run
    // as well would start the real application at the end of a test pass, with the side
    // effects that implies: windows, shell registration, and writes to the application's own
    // data. Covering startup is a #test's job, not a side effect of testing.
    if (ctx.cmdLine().command != CommandKind::Test)
        emitLifecycleCalls(builder, builder_->mainFunctions);

    emitLifecycleCalls(builder, builder_->dropFunctions);
    emitRuntimeDependencyHookCalls(builder, *builder_, builder_->runtimeDependencyDropOrder, RuntimeHookStage::Drop, hookArgs, nextVirtualIntRegIndex);

    // Startup closes the runtime through the shared runtime wrapper so setup and
    // teardown stay aligned across native entry points.
    const ABICall::PreparedCall preparedCloseRuntime = ABICall::prepareArgs(builder, closeRuntimeFn->callConvKind(), {});
    ABICall::callLocal(builder, closeRuntimeFn->callConvKind(), closeRuntimeFn, preparedCloseRuntime);
    builder.emitRet();

    if (startup->code.emit(ctx, builder) != Result::Continue)
        return builder_->reportError(DiagnosticId::cmd_err_native_test_entry_lower_failed);

    builder_->startup = std::move(startup);
    return Result::Continue;
}

SWC_END_NAMESPACE();
