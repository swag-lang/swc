#include "pch.h"
#include "Backend/Native/NativeBackendBuilder.h"
#include "Backend/Native/NativeArtifactBuilder.h"
#include "Backend/Native/NativeLinker.h"
#include "Backend/Native/NativeObjFileWriter.h"
#include "Backend/Native/NativeObjJob.h"
#include "Backend/Native/SymbolSort.h"
#include "Compiler/CodeGen/Core/CodeGenJob.h"
#include "Compiler/Parser/Ast/Ast.h"
#include "Compiler/SourceFile.h"
#include "Main/Global.h"
#include "Main/Stats.h"
#include "Support/Core/Utf8Helper.h"
#include "Support/Math/Hash.h"
#include "Support/Memory/Heap.h"
#include "Support/Memory/MemoryProfile.h"
#include "Support/Report/Logger.h"
#include "Support/Report/ScopedTimedAction.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    constexpr uint32_t K_NATIVE_TEST_COUNT_MISMATCH_EXIT_TAG        = 0xA0000000u;
    constexpr uint32_t K_NATIVE_TEST_COUNT_MISMATCH_EXIT_VALUE_MASK = 0x0FFFFFFFu;

    bool isCompilerFunction(const SymbolFunction& symbol)
    {
        return symbol.decl() && symbol.decl()->id() == AstNodeId::CompilerFunc;
    }

    template<typename T>
    const SourceFile* sourceFileForSymbol(const NativeBackendBuilder& builder, const T& symbol)
    {
        return builder.compiler().srcView(symbol.srcViewRef()).file();
    }

    bool isNativeArtifactCompilerFunction(const TokenId tokenId)
    {
        switch (tokenId)
        {
            case TokenId::CompilerFuncTest:
            case TokenId::CompilerFuncInit:
            case TokenId::CompilerFuncDrop:
            case TokenId::CompilerFuncMain:
            case TokenId::CompilerFuncPreMain:
                return true;

            default:
                return false;
        }
    }

    bool isRuntimeArtifactFunction(const NativeBackendBuilder& builder, const SymbolFunction& symbol)
    {
        if (symbol.attributes().hasRtFlag(RtAttributeFlagsE::Macro) || symbol.attributes().hasRtFlag(RtAttributeFlagsE::Mixin))
            return false;
        if (symbol.attributes().hasRtFlag(RtAttributeFlagsE::Compiler))
            return false;

        const AstNode* const decl = symbol.decl();
        if (!decl)
            return true;

        if (decl->id() == AstNodeId::CompilerRunBlock || decl->id() == AstNodeId::CompilerRunExpr)
            return false;
        if (decl->id() != AstNodeId::CompilerFunc)
            return true;

        const TokenId tokenId = builder.compiler().srcView(symbol.srcViewRef()).token(symbol.tokRef()).id;
        return isNativeArtifactCompilerFunction(tokenId);
    }

    bool shouldPrepareFile(const SourceFile* file)
    {
        if (!file)
            return true;

        return file->ast().srcView().runsNativeArtifact();
    }

    template<typename T>
    bool shouldPrepareSymbol(const NativeBackendBuilder& builder, const T& symbol)
    {
        return shouldPrepareFile(sourceFileForSymbol(builder, symbol));
    }

    template<>
    bool shouldPrepareSymbol<SymbolFunction>(const NativeBackendBuilder& builder, const SymbolFunction& symbol)
    {
        return shouldPrepareFile(sourceFileForSymbol(builder, symbol)) && isRuntimeArtifactFunction(builder, symbol);
    }

    template<typename T>
    void filterPreparedSymbols(std::vector<T*>& values, const NativeBackendBuilder& builder)
    {
        std::erase_if(values, [&](const T* symbol) {
            return symbol == nullptr || !shouldPrepareSymbol(builder, *symbol);
        });
    }

    bool isIncludableDependency(const NativeBackendBuilder& builder, const SymbolFunction& fn)
    {
        if (fn.isForeign() || fn.isEmpty() || fn.isAttribute())
            return false;
        if (fn.attributes().hasRtFlag(RtAttributeFlagsE::Macro) || fn.attributes().hasRtFlag(RtAttributeFlagsE::Mixin))
            return false;
        return fn.isSemaCompleted() && shouldPrepareSymbol(builder, fn);
    }

    bool appendCodeGenDependencies(const NativeBackendBuilder& builder, std::vector<SymbolFunction*>& functions)
    {
        bool               changed = false;
        std::unordered_set seenFunctions(functions.begin(), functions.end());
        for (size_t idx = 0; idx < functions.size(); ++idx)
        {
            const SymbolFunction* function = functions[idx];
            SWC_ASSERT(function != nullptr);

            SmallVector<SymbolFunction*> deps;
            function->appendCallDependencies(deps);
            for (SymbolFunction* dep : deps)
            {
                if (!dep || !isIncludableDependency(builder, *dep))
                    continue;
                if (!seenFunctions.insert(dep).second)
                    continue;

                functions.push_back(dep);
                changed = true;
            }
        }

        return changed;
    }

    bool appendGlobalFunctionInitDependencies(const NativeBackendBuilder& builder, std::vector<SymbolFunction*>& functions, const std::span<SymbolVariable* const> globals)
    {
        bool               changed = false;
        std::unordered_set seenFunctions(functions.begin(), functions.end());
        for (const SymbolVariable* global : globals)
        {
            if (!global)
                continue;

            SymbolFunction* const target = global->globalFunctionInit();
            if (!target || !isIncludableDependency(builder, *target))
                continue;
            if (!seenFunctions.insert(target).second)
                continue;

            functions.push_back(target);
            changed = true;
        }

        return changed;
    }

    void rebuildFunctionInfos(NativeBackendBuilder& builder, const std::vector<SymbolFunction*>& functions)
    {
        builder.functionInfos.clear();
        builder.functionBySymbol.clear();

        for (SymbolFunction* symbol : functions)
        {
            SWC_ASSERT(symbol != nullptr);

            NativeFunctionInfo info;
            info.symbol      = symbol;
            info.machineCode = &symbol->loweredCode();
            info.sortKey     = SymbolSort::locationKey(builder.compiler(), *symbol);
            info.symbolName  = std::format("__swc_fn_{:06}_{:08x}", builder.functionInfos.size(), Math::hash(info.sortKey));
            info.debugName   = symbol->getFullScopedName(builder.ctx());
            info.exported    = symbol->isPublic() && !isCompilerFunction(*symbol);
            info.compilerFn  = isCompilerFunction(*symbol);
            builder.functionInfos.push_back(std::move(info));
        }

        for (const auto& info : builder.functionInfos)
            builder.functionBySymbol.emplace(info.symbol, &info);
    }

    Result scheduleCodeGen(NativeBackendBuilder& builder)
    {
        if (builder.functionInfos.empty())
            return Result::Continue;

        SourceFile* firstFile = nullptr;
        for (SourceFile* file : builder.compiler().files())
        {
            if (file)
            {
                firstFile = file;
                break;
            }
        }

        if (!firstFile)
            return builder.reportError(DiagnosticId::cmd_err_native_codegen_source_missing);

        Sema        baseSema(builder.ctx(), firstFile->nodePayloadContext(), false);
        JobManager& jobMgr = builder.ctx().global().jobMgr();
        for (const auto& info : builder.functionInfos)
        {
            SWC_ASSERT(info.symbol != nullptr);
            if (info.symbol->isCodeGenCompleted() || !info.symbol->loweredCode().bytes.empty())
                continue;
            if (!info.symbol->tryMarkCodeGenJobScheduled())
                continue;

            const AstNodeRef root = info.symbol->declNodeRef();
            if (root.isInvalid())
                return builder.reportError(DiagnosticId::cmd_err_native_codegen_decl_missing, Diagnostic::ARG_SYM, info.symbolName);

            auto* job = heapNew<CodeGenJob>(builder.ctx(), baseSema, *info.symbol, root);
            jobMgr.enqueue(*job, JobPriority::Normal, builder.compiler().jobClientId());
        }

        Sema::waitDone(builder.ctx(), builder.compiler().jobClientId());
        if (Stats::hasError())
            return Result::Error;

        for (const auto& info : builder.functionInfos)
        {
            if (!info.machineCode || info.machineCode->bytes.empty())
                return builder.reportError(DiagnosticId::cmd_err_native_codegen_machine_code_missing, Diagnostic::ARG_SYM, info.symbolName);
        }

        return Result::Continue;
    }
}

NativeBackendBuilder::NativeBackendBuilder(CompilerInstance& compiler, const bool runArtifact) :
    ctx_(compiler),
    compiler_(compiler),
    runArtifact_(runArtifact)
{
}

TaskContext& NativeBackendBuilder::ctx()
{
    return ctx_;
}

const TaskContext& NativeBackendBuilder::ctx() const
{
    return ctx_;
}

CompilerInstance& NativeBackendBuilder::compiler()
{
    return compiler_;
}

const CompilerInstance& NativeBackendBuilder::compiler() const
{
    return compiler_;
}

uint32_t NativeBackendBuilder::expectedTestFunctionCount() const
{
    uint32_t result = 0;
    for (const SymbolFunction* function : compiler_.nativeTestFunctions())
    {
        if (!function || !shouldPrepareSymbol(*this, *function))
            continue;
        result++;
    }

    return result;
}

bool NativeBackendBuilder::tryMapRDataSourceOffset(uint32_t& outOffset, const uint32_t shardIndex, const uint32_t sourceOffset) const noexcept
{
    outOffset = 0;
    if (shardIndex >= ConstantManager::SHARD_COUNT)
        return false;

    const auto& entries = rdataAllocationMap[shardIndex];
    if (entries.empty())
        return false;

    const auto it = std::ranges::upper_bound(entries, sourceOffset, {}, &NativeRDataAllocationMapEntry::sourceOffset);
    if (it == entries.begin())
        return false;

    const auto& entry = *std::prev(it);
    if (sourceOffset < entry.sourceOffset || sourceOffset - entry.sourceOffset >= entry.size)
        return false;

    outOffset = entry.emittedOffset + (sourceOffset - entry.sourceOffset);
    return true;
}

Result NativeBackendBuilder::run()
{
    SWC_MEM_SCOPE("Backend/Native");
    SWC_RESULT(validateTarget());

    const NativeArtifactBuilder artifactBuilder(*this);
    NativeArtifactPaths         paths;
    artifactBuilder.queryPaths(paths);
    compiler_.setLastArtifactLabel(paths.artifactPath.filename().empty() ? Utf8(paths.artifactPath) : Utf8(paths.artifactPath.filename()));
    {
        TimedActionLog::ScopedStage stage(ctx_, TimedActionLog::Stage::Build);

        SWC_RESULT(prepare());
        stage.setStat(Utf8Helper::countWithLabel(compiler_.nativeCodeSegment().size(), "function"));
        SWC_RESULT(artifactBuilder.build());
        SWC_RESULT(writeObjects());

        const auto linker = NativeLinker::create(*this);
        SWC_ASSERT(linker != nullptr);
        SWC_RESULT(linker->link());
    }

    if (runArtifact_ && compiler_.buildCfg().backendKind == Runtime::BuildCfgBackendKind::Executable)
        SWC_RESULT(runGeneratedArtifact());

    return Result::Continue;
}

Result NativeBackendBuilder::prepare()
{
    functionInfos.clear();
    functionBySymbol.clear();
    testFunctions    = compiler_.nativeTestFunctions();
    initFunctions    = compiler_.nativeInitFunctions();
    preMainFunctions = compiler_.nativePreMainFunctions();
    dropFunctions    = compiler_.nativeDropFunctions();
    mainFunctions    = compiler_.nativeMainFunctions();
    regularGlobals   = compiler_.nativeGlobalVariables();
    filterPreparedSymbols(testFunctions, *this);
    filterPreparedSymbols(initFunctions, *this);
    filterPreparedSymbols(preMainFunctions, *this);
    filterPreparedSymbols(dropFunctions, *this);
    filterPreparedSymbols(mainFunctions, *this);
    filterPreparedSymbols(regularGlobals, *this);

    auto functions = compiler_.nativeCodeSegment();
    filterPreparedSymbols(functions, *this);
    SymbolSort::sortAndUniqueByLocation(testFunctions, compiler_);
    SymbolSort::sortAndUniqueByLocation(initFunctions, compiler_);
    SymbolSort::sortAndUniqueByLocation(preMainFunctions, compiler_);
    SymbolSort::sortAndUniqueByLocation(dropFunctions, compiler_);
    SymbolSort::sortAndUniqueByLocation(mainFunctions, compiler_);
    SymbolSort::sortAndUniqueByLocation(regularGlobals, compiler_);
    appendGlobalFunctionInitDependencies(*this, functions, regularGlobals);

    std::optional<TimedActionLog::ScopedStage> microStage;
    if (ctx_.global().logger().claimStageOnce("micro"))
    {
        microStage.emplace(ctx_, TimedActionLog::Stage::Micro);
    }

    while (true)
    {
        appendCodeGenDependencies(*this, functions);
        SymbolSort::sortAndUniqueByLocation(functions, compiler_);
        rebuildFunctionInfos(*this, functions);
        SWC_RESULT(scheduleCodeGen(*this));

        if (!appendCodeGenDependencies(*this, functions))
        {
            if (microStage)
                microStage->setStat(Utf8Helper::countWithLabel(functions.size(), "function"));
            return Result::Continue;
        }
    }
}

Result NativeBackendBuilder::writeObject(const uint32_t objIndex)
{
    SWC_ASSERT(objIndex < objectDescriptions.size());
    const auto objectWriter = NativeObjFileWriter::create(*this);
    SWC_ASSERT(objectWriter != nullptr);
    return objectWriter->writeObjectFile(objectDescriptions[objIndex]);
}

Result NativeBackendBuilder::reportError(DiagnosticId id)
{
    return reportError(Diagnostic::get(id));
}

Result NativeBackendBuilder::reportError(const Diagnostic& diag)
{
    lastErrorId_ = diag.elements().empty() ? DiagnosticId::None : diag.elements().front()->id();
    diag.report(ctx_);
    return Result::Error;
}

Result NativeBackendBuilder::validateTarget()
{
    const CommandLine& commandLine = ctx_.cmdLine();
    if (commandLine.targetOs != Runtime::TargetOs::Windows)
    {
        return reportError(DiagnosticId::cmd_err_native_target_os_not_supported);
    }

    if (commandLine.targetArch != Runtime::TargetArch::X86_64)
    {
        return reportError(DiagnosticId::cmd_err_native_target_arch_not_supported);
    }

    const Runtime::BuildCfg& buildCfg = compiler_.buildCfg();
    if (buildCfg.backendKind == Runtime::BuildCfgBackendKind::None)
    {
        return reportError(DiagnosticId::cmd_err_native_backend_kind_required);
    }

    if (buildCfg.backendKind == Runtime::BuildCfgBackendKind::Executable &&
        buildCfg.backendSubKind != Runtime::BuildCfgBackendSubKind::Default &&
        buildCfg.backendSubKind != Runtime::BuildCfgBackendSubKind::Console)
    {
        return reportError(DiagnosticId::cmd_err_native_executable_subsystem_not_supported);
    }

    return Result::Continue;
}

Result NativeBackendBuilder::writeObjects()
{
    objWriteFailed.store(false, std::memory_order_release);

    const NativeArtifactBuilder artifactBuilder(*this);
    SWC_RESULT(artifactBuilder.prepareOutputFolders());

    JobManager& jobMgr = ctx_.global().jobMgr();
    for (uint32_t i = 0; i < objectDescriptions.size(); ++i)
    {
        auto* job = heapNew<NativeObjJob>(ctx_, *this, i);
        jobMgr.enqueue(*job, JobPriority::Normal, compiler_.jobClientId());
    }

    jobMgr.waitAll(compiler_.jobClientId());
    return objWriteFailed.load(std::memory_order_acquire) ? Result::Error : Result::Continue;
}

Result NativeBackendBuilder::runGeneratedArtifact()
{
    TimedActionLog::ScopedStage stage(ctx_, TimedActionLog::Stage::Run);

    uint32_t                    exitCode    = 0;
    const fs::path              artifactDir = artifactPath.parent_path();
    const Os::ProcessRunOptions options{
        .logCtx = &ctx_,
    };

    const auto result = Os::runProcess(exitCode, artifactPath, {}, artifactDir.empty() ? buildDir : artifactDir, &options);
    switch (result)
    {
        case Os::ProcessRunResult::Ok:
            break;
        case Os::ProcessRunResult::StartFailed:
            return reportError(DiagnosticId::cmd_err_native_artifact_start_failed, Diagnostic::ARG_PATH, Utf8(artifactPath), Diagnostic::ARG_BECAUSE, Os::systemError());
        case Os::ProcessRunResult::WaitFailed:
            return reportError(DiagnosticId::cmd_err_native_artifact_wait_failed, Diagnostic::ARG_PATH, Utf8(artifactPath));
        case Os::ProcessRunResult::ExitCodeFailed:
            return reportError(DiagnosticId::cmd_err_native_artifact_exit_code_failed, Diagnostic::ARG_PATH, Utf8(artifactPath), Diagnostic::ARG_BECAUSE, Os::systemError());
    }

    const uint32_t expectedTestCount = expectedTestFunctionCount();
    if (compiler_.cmdLine().command == CommandKind::Test &&
        expectedTestCount &&
        (exitCode & ~K_NATIVE_TEST_COUNT_MISMATCH_EXIT_VALUE_MASK) == K_NATIVE_TEST_COUNT_MISMATCH_EXIT_TAG)
    {
        const uint32_t actualTestCount = exitCode & K_NATIVE_TEST_COUNT_MISMATCH_EXIT_VALUE_MASK;
        return reportError(DiagnosticId::cmd_err_native_test_count_mismatch, Diagnostic::ARG_COUNT, expectedTestCount, Diagnostic::ARG_VALUE, actualTestCount);
    }

    if (exitCode != 0)
        return reportError(DiagnosticId::cmd_err_native_artifact_failed, Diagnostic::ARG_VALUE, exitCode);
    return Result::Continue;
}

SWC_END_NAMESPACE();
