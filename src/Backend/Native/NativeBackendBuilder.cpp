#include "pch.h"
#include "Backend/Native/NativeBackendBuilder.h"
#include "Backend/Native/NativeArtifactBuilder.h"
#include "Backend/Native/NativeLinker.h"
#include "Backend/Native/NativeObjFileWriter.h"
#include "Backend/Native/NativeObjJob.h"
#include "Compiler/CodeGen/Core/CodeGenJob.h"
#include "Main/Global.h"
#include "Support/Math/Hash.h"
#include "Support/Memory/Heap.h"
#include "Support/Report/ScopedTimedAction.h"
#include "Compiler/Core/SourceFile.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    template<typename T, typename MAKE_KEY>
    void sortAndUnique(std::vector<T*>& values, const MAKE_KEY& makeKey)
    {
        values.erase(std::remove(values.begin(), values.end(), nullptr), values.end());
        std::ranges::sort(values, [&](const T* lhs, const T* rhs) {
            if (lhs == rhs)
                return false;

            const Utf8 lhsKey = makeKey(*lhs);
            const Utf8 rhsKey = makeKey(*rhs);
            if (lhsKey != rhsKey)
                return lhsKey < rhsKey;
            return lhs < rhs;
        });

        values.erase(std::unique(values.begin(), values.end()), values.end());
    }

    bool isCompilerFunction(const SymbolFunction& symbol)
    {
        return symbol.decl() && symbol.decl()->id() == AstNodeId::CompilerFunc;
    }

    Utf8 makeFunctionSortKey(const NativeBackendBuilder& builder, const SymbolFunction& symbol)
    {
        Utf8 key;
        if (const SourceFile* file = builder.compiler().srcView(symbol.srcViewRef()).file())
            key += Utf8(file->path());

        key += "|";
        key += std::to_string(symbol.tokRef().get());
        key += "|";
        key += symbol.getFullScopedName(builder.ctx());
        key += "|";
        key += symbol.computeName(builder.ctx());
        return key;
    }

    Utf8 makeVariableSortKey(const NativeBackendBuilder& builder, const SymbolVariable& symbol)
    {
        Utf8 key;
        if (const SourceFile* file = builder.compiler().srcView(symbol.srcViewRef()).file())
            key += Utf8(file->path());

        key += "|";
        key += std::to_string(symbol.tokRef().get());
        key += "|";
        key += symbol.getFullScopedName(builder.ctx());
        return key;
    }

    Result checkActionResult(Result result, ScopedTimedAction& action)
    {
        if (result != Result::Continue)
            action.fail();
        return result;
    }

    bool appendCodeGenDependencies(std::vector<SymbolFunction*>& functions)
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
                if (!dep)
                    continue;
                if (dep->isForeign() || dep->isEmpty() || dep->isAttribute())
                    continue;
                if (dep->attributes().hasRtFlag(RtAttributeFlagsE::Compiler))
                    continue;
                if (!dep->isSemaCompleted())
                    continue;
                if (!seenFunctions.insert(dep).second)
                    continue;

                functions.push_back(dep);
                changed = true;
            }
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
            info.sortKey     = makeFunctionSortKey(builder, *symbol);
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
        for (SourceFile* const file : builder.compiler().files())
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
        if (Stats::get().numErrors.load(std::memory_order_relaxed) != 0)
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

bool NativeBackendBuilder::tryMapRDataSourceOffset(uint32_t& outOffset, const uint32_t shardIndex, const uint32_t sourceOffset) const noexcept
{
    outOffset = 0;
    if (shardIndex >= ConstantManager::SHARD_COUNT)
        return false;

    const auto& entries = rdataAllocationMap[shardIndex];
    if (entries.empty())
        return false;

    const auto it = std::upper_bound(entries.begin(),
                                     entries.end(),
                                     sourceOffset,
                                     [](const uint32_t lhs, const NativeRDataAllocationMapEntry& rhs) { return lhs < rhs.sourceOffset; });
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
    SWC_RESULT(validateTarget());

    const NativeArtifactBuilder artifactBuilder(*this);
    NativeArtifactPaths         paths;
    artifactBuilder.queryPaths(paths);
    ScopedTimedAction buildAction(ctx_, "Build", paths.artifactPath.filename().string());

    SWC_RESULT(checkActionResult(prepare(), buildAction));

    SWC_RESULT(checkActionResult(artifactBuilder.build(), buildAction));
    SWC_RESULT(checkActionResult(writeObjects(), buildAction));

    const auto linker = NativeLinker::create(*this);
    SWC_ASSERT(linker != nullptr);
    SWC_RESULT(checkActionResult(linker->link(), buildAction));
    buildAction.success();

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

    auto functions = compiler_.nativeCodeSegment();
    sortAndUnique(testFunctions, [&](const SymbolFunction& symbol) { return makeFunctionSortKey(*this, symbol); });
    sortAndUnique(initFunctions, [&](const SymbolFunction& symbol) { return makeFunctionSortKey(*this, symbol); });
    sortAndUnique(preMainFunctions, [&](const SymbolFunction& symbol) { return makeFunctionSortKey(*this, symbol); });
    sortAndUnique(dropFunctions, [&](const SymbolFunction& symbol) { return makeFunctionSortKey(*this, symbol); });
    sortAndUnique(mainFunctions, [&](const SymbolFunction& symbol) { return makeFunctionSortKey(*this, symbol); });
    sortAndUnique(regularGlobals, [&](const SymbolVariable& symbol) { return makeVariableSortKey(*this, symbol); });

    while (true)
    {
        appendCodeGenDependencies(functions);
        sortAndUnique(functions, [&](const SymbolFunction& symbol) { return makeFunctionSortKey(*this, symbol); });
        rebuildFunctionInfos(*this, functions);
        SWC_RESULT(scheduleCodeGen(*this));

        if (!appendCodeGenDependencies(functions))
            return Result::Continue;
    }
}

Result NativeBackendBuilder::writeObject(const uint32_t objIndex)
{
    SWC_ASSERT(objIndex < objectDescriptions.size());
    const auto objectWriter = NativeObjFileWriter::create(*this);
    SWC_ASSERT(objectWriter != nullptr);
    return objectWriter->writeObjectFile(objectDescriptions[objIndex]);
}

Result NativeBackendBuilder::reportError(DiagnosticId id) const
{
    return reportError(Diagnostic::get(id));
}

Result NativeBackendBuilder::reportError(const Diagnostic& diag) const
{
    diag.report(const_cast<TaskContext&>(ctx_));
    return Result::Error;
}

Result NativeBackendBuilder::validateTarget() const
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

    JobManager& jobMgr = ctx_.global().jobMgr();
    for (uint32_t i = 0; i < objectDescriptions.size(); ++i)
    {
        auto* job = heapNew<NativeObjJob>(ctx_, *this, i);
        jobMgr.enqueue(*job, JobPriority::Normal, compiler_.jobClientId());
    }

    jobMgr.waitAll(compiler_.jobClientId());
    return objWriteFailed.load(std::memory_order_acquire) ? Result::Error : Result::Continue;
}

Result NativeBackendBuilder::runGeneratedArtifact() const
{
    ScopedTimedAction runAction(ctx_, "Run", artifactPath.filename().string());

    uint32_t       exitCode    = 0;
    const fs::path artifactDir = artifactPath.parent_path();
    const auto     result      = Os::runProcess(exitCode, artifactPath, {}, artifactDir.empty() ? buildDir : artifactDir);
    switch (result)
    {
        case Os::ProcessRunResult::Ok:
            break;
        case Os::ProcessRunResult::StartFailed:
            runAction.fail();
            return reportError(DiagnosticId::cmd_err_native_artifact_start_failed, Diagnostic::ARG_PATH, Utf8(artifactPath), Diagnostic::ARG_BECAUSE, Os::systemError());
        case Os::ProcessRunResult::WaitFailed:
            runAction.fail();
            return reportError(DiagnosticId::cmd_err_native_artifact_wait_failed, Diagnostic::ARG_PATH, Utf8(artifactPath));
        case Os::ProcessRunResult::ExitCodeFailed:
            runAction.fail();
            return reportError(DiagnosticId::cmd_err_native_artifact_exit_code_failed, Diagnostic::ARG_PATH, Utf8(artifactPath), Diagnostic::ARG_BECAUSE, Os::systemError());
    }

    if (exitCode != 0)
    {
        runAction.fail();
        return reportError(DiagnosticId::cmd_err_native_artifact_failed, Diagnostic::ARG_VALUE, exitCode);
    }
    runAction.success();
    return Result::Continue;
}

SWC_END_NAMESPACE();
