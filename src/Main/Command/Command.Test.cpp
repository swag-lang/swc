#include "pch.h"
#include "Main/Command/Command.h"
#include "Backend/JIT/JITExecManager.h"
#include "Backend/Native/NativeBackendBuilder.h"
#include "Backend/Native/SymbolSort.h"
#include "Compiler/Sema/Symbol/Symbol.Function.h"
#include "Compiler/SourceFile.h"
#include "Compiler/Verify.h"
#include "Main/Command/CommandLine.h"
#include "Main/Command/CommandLineParser.h"
#include "Main/Command/CommandRun.h"
#include "Main/CompilerInstance.h"
#include "Main/Global.h"
#include "Main/Stats.h"
#include "Support/Core/ByteArray.h"
#include "Support/Memory/MemoryProfile.h"
#include "Support/Os/Os.h"
#include "Support/Report/Assert.h"
#include "Support/Report/Diagnostic.h"
#include "Support/Report/Logger.h"
#include "Support/Report/ScopedTimedLog.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    Utf8 formatTestStageStat(const TaskContext& ctx, const ScopedTimedLog::StatsSnapshot& deltaSnapshot)
    {
        std::vector<Utf8> statParts;
        ScopedTimedLog::appendTestStats(ctx, statParts, deltaSnapshot.numTests, deltaSnapshot.numTestsFailed);
        return ScopedTimedLog::joinStatItems(ctx, statParts);
    }

    bool hasJitEligibleInputs(const CompilerInstance& compiler)
    {
        for (SourceFile* file : compiler.files())
        {
            if (!file || file->isRuntime())
                continue;
            if (!file->ast().hasSourceView())
                continue;

            const SourceView& srcView = file->ast().srcView();
            if (srcView.mustSkip())
                continue;
            if (srcView.runsJit())
                return true;
        }

        return false;
    }

    uint32_t codeRangeEndLine(const TaskContext& ctx, const SourceCodeRange& codeRange)
    {
        if (!codeRange.srcView || !codeRange.len)
            return codeRange.line;

        SourceCodeRange endRange;
        endRange.fromOffset(ctx, *codeRange.srcView, codeRange.offset + codeRange.len - 1, 1);
        return endRange.line;
    }

    bool functionHasSourceError(const CompilerInstance& compiler, const SymbolFunction& function)
    {
        const SourceFile* file = compiler.srcView(function.srcViewRef()).file();
        if (!file)
            return false;

        const AstNode* decl = function.decl();
        if (!decl)
            return file->hasError();

        const SourceView& declView     = compiler.srcView(decl->srcViewRef());
        const FileRef     ownerFileRef = declView.ownerFileRef();
        if (!ownerFileRef.isValid())
            return file->hasError();

        const Ast& declAst = compiler.file(ownerFileRef).ast();
        if (!declAst.hasSourceView() || declAst.tryFindNodeRef(decl).isInvalid())
            return file->hasError();

        const TaskContext     ctx(compiler.global(), compiler.cmdLine());
        const SourceCodeRange startRange = decl->codeRangeWithChildren(ctx, declAst, declView);
        if (!startRange.srcView || !startRange.len)
            return file->hasError();

        return file->hasErrorLineInRange(startRange.line, codeRangeEndLine(ctx, startRange));
    }

    bool shouldSkipFunctionForTests(const CompilerInstance& compiler, const SymbolFunction& root)
    {
        SmallVector<const SymbolFunction*>        stack;
        std::unordered_set<const SymbolFunction*> visited;
        stack.push_back(&root);

        while (!stack.empty())
        {
            const SymbolFunction* function = stack.back();
            stack.pop_back();
            if (!function)
                continue;
            if (!visited.insert(function).second)
                continue;

            if (function->isIgnored() || functionHasSourceError(compiler, *function))
                return true;

            SmallVector<SymbolFunction*> dependencies;
            function->appendCallDependencies(dependencies);
            for (const SymbolFunction* dependency : dependencies)
            {
                if (dependency && dependency != function)
                    stack.push_back(dependency);
            }
        }

        return false;
    }

    struct JitFunctionSelection
    {
        std::unordered_set<const SymbolFunction*> skippedFunctions;
        std::unordered_set<const SymbolFunction*> functions;
        uint32_t                                  expectedTestCount = 0;
    };

    bool shouldKeepSelectedJitFunction(const JitFunctionSelection& selection, const SymbolFunction* function)
    {
        return function != nullptr && selection.functions.contains(function);
    }

    using ReverseDependencyMap = std::unordered_map<const SymbolFunction*, std::vector<const SymbolFunction*>>;

    struct TestFunctionGraph
    {
        std::unordered_set<const SymbolFunction*> visited;
        ReverseDependencyMap                      reverseDependencies;
        std::vector<const SymbolFunction*>        selfSkippedFunctions;
    };

    void collectTestFunctionGraph(TestFunctionGraph& graph, const CompilerInstance& compiler, const SymbolFunction* root)
    {
        SmallVector<const SymbolFunction*> stack;
        stack.push_back(root);

        while (!stack.empty())
        {
            const SymbolFunction* function = stack.back();
            stack.pop_back();
            if (!function)
                continue;
            if (!graph.visited.insert(function).second)
                continue;
            if (function->isIgnored() || functionHasSourceError(compiler, *function))
            {
                graph.selfSkippedFunctions.push_back(function);
                continue;
            }

            SmallVector<SymbolFunction*> dependencies;
            function->appendCallDependencies(dependencies);
            for (const SymbolFunction* dependency : dependencies)
            {
                if (!dependency || dependency == function)
                    continue;
                graph.reverseDependencies[dependency].push_back(function);
                stack.push_back(dependency);
            }
        }
    }

    void propagateSkippedFunctions(JitFunctionSelection& selection, const TestFunctionGraph& graph)
    {
        SmallVector<const SymbolFunction*> stack;
        for (const SymbolFunction* function : graph.selfSkippedFunctions)
        {
            if (selection.skippedFunctions.insert(function).second)
                stack.push_back(function);
        }

        while (!stack.empty())
        {
            const SymbolFunction* function = stack.back();
            stack.pop_back();

            const auto parents = graph.reverseDependencies.find(function);
            if (parents == graph.reverseDependencies.end())
                continue;

            for (const SymbolFunction* parent : parents->second)
            {
                if (selection.skippedFunctions.insert(parent).second)
                    stack.push_back(parent);
            }
        }
    }

    bool isRuntimeTestFunction(const CompilerInstance& compiler, const SymbolFunction& function);

    void tryAddJitFunction(JitFunctionSelection& selection, const CompilerInstance& compiler, const SymbolFunction* function)
    {
        if (!function)
            return;
        if (function->isIgnored())
            return;
        if (!isRuntimeTestFunction(compiler, *function))
            return;
        const SourceFile* file = compiler.srcView(function->srcViewRef()).file();
        if (file && !file->ast().srcView().runsJit())
            return;
        if (selection.skippedFunctions.contains(function))
            return;

        selection.functions.insert(function);
    }

    JitFunctionSelection selectJitFunctions(const CompilerInstance& compiler, const std::vector<SymbolFunction*>& codeFunctions, const std::vector<SymbolFunction*>& nativeTestFunctions)
    {
        JitFunctionSelection selection;
        TestFunctionGraph    graph;
        graph.visited.reserve(codeFunctions.size());
        graph.reverseDependencies.reserve(codeFunctions.size());
        selection.skippedFunctions.reserve(codeFunctions.size());
        selection.functions.reserve(codeFunctions.size());

        for (const SymbolFunction* function : codeFunctions)
        {
            if (function)
            {
                const SourceFile* file = compiler.srcView(function->srcViewRef()).file();
                if (!file || file->ast().srcView().runsJit())
                    collectTestFunctionGraph(graph, compiler, function);
            }
        }

        for (const SymbolFunction* function : nativeTestFunctions)
        {
            if (!function)
                continue;

            const SourceFile* file = compiler.srcView(function->srcViewRef()).file();
            if (!file || file->ast().srcView().runsJit())
                collectTestFunctionGraph(graph, compiler, function);
        }

        propagateSkippedFunctions(selection, graph);

        for (const SymbolFunction* function : codeFunctions)
            tryAddJitFunction(selection, compiler, function);

        for (const SymbolFunction* function : nativeTestFunctions)
        {
            tryAddJitFunction(selection, compiler, function);
            if (function && selection.functions.contains(function))
                selection.expectedTestCount++;
        }

        return selection;
    }

    void filterJitFunctions(std::vector<SymbolFunction*>& functions, const JitFunctionSelection& selection)
    {
        size_t writeIndex = 0;
        for (size_t readIndex = 0; readIndex < functions.size(); ++readIndex)
        {
            if (!shouldKeepSelectedJitFunction(selection, functions[readIndex]))
                continue;

            functions[writeIndex++] = functions[readIndex];
        }

        functions.resize(writeIndex);
    }

    std::vector<SymbolFunction*> collectPreparedFunctions(const NativeBackendBuilder& builder)
    {
        std::vector<SymbolFunction*> result;
        result.reserve(builder.functionInfos.size());
        for (const NativeFunctionInfo& info : builder.functionInfos)
        {
            if (info.symbol)
                result.push_back(info.symbol);
        }

        return result;
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

    bool isRuntimeTestFunction(const CompilerInstance& compiler, const SymbolFunction& function)
    {
        if (function.attributes().hasRtFlag(RtAttributeFlagsE::Compiler))
            return false;

        const AstNode* decl = function.decl();
        if (!decl)
            return true;

        if (decl->id() == AstNodeId::CompilerRunBlock || decl->id() == AstNodeId::CompilerRunExpr)
            return false;
        if (decl->id() != AstNodeId::CompilerFunc)
            return true;

        const TokenId tokenId = compiler.srcView(function.srcViewRef()).token(function.tokRef()).id;
        return isNativeArtifactCompilerFunction(tokenId);
    }

    bool shouldRunNativeArtifactFunction(const CompilerInstance& compiler, const SymbolFunction& function)
    {
        if (shouldSkipFunctionForTests(compiler, function))
            return false;
        if (!isRuntimeTestFunction(compiler, function))
            return false;

        const SourceFile* file = compiler.srcView(function.srcViewRef()).file();
        return !file || file->ast().srcView().runsNativeArtifact();
    }

    bool hasRunnableNativeArtifactFunction(const CompilerInstance& compiler, const std::vector<SymbolFunction*>& functions)
    {
        for (const SymbolFunction* function : functions)
        {
            if (function && shouldRunNativeArtifactFunction(compiler, *function))
                return true;
        }

        return false;
    }

    bool hasNativeArtifactEntryPoints(const CompilerInstance& compiler)
    {
        return hasRunnableNativeArtifactFunction(compiler, compiler.nativeTestFunctions()) ||
               hasRunnableNativeArtifactFunction(compiler, compiler.nativeMainFunctions()) ||
               hasRunnableNativeArtifactFunction(compiler, compiler.nativeInitFunctions()) ||
               hasRunnableNativeArtifactFunction(compiler, compiler.nativePreMainFunctions()) ||
               hasRunnableNativeArtifactFunction(compiler, compiler.nativeDropFunctions());
    }

    bool reportJitTestCountMismatch(TaskContext& ctx, const uint32_t expectedCount, const uint32_t actualCount)
    {
        Diagnostic diag = Diagnostic::get(DiagnosticId::cmd_err_jit_test_count_mismatch);
        diag.addArgument(Diagnostic::ARG_COUNT, expectedCount);
        diag.addArgument(Diagnostic::ARG_VALUE, actualCount);
        diag.report(ctx);
        return false;
    }

    void verifyExpectedMarkers(TaskContext& ctx)
    {
        if (Stats::hasError())
            return;

        for (SourceFile* file : ctx.compiler().files())
        {
            if (!file)
                continue;
            if (!file->ast().hasSourceView())
                continue;

            const SourceView& srcView = file->ast().srcView();
            if (srcView.mustSkip())
                continue;
            file->unitTest().verifyUntouchedExpected(ctx, srcView);
        }
    }

    struct DataSegmentSnapshot
    {
        ByteArray globalZero;
        ByteArray globalInit;
    };

    DataSegmentSnapshot snapshotDataSegments(const CompilerInstance& compiler)
    {
        DataSegmentSnapshot result;

        const uint32_t zeroExtent = compiler.globalZeroSegment().extentSize();
        if (zeroExtent)
        {
            result.globalZero.resize(zeroExtent);
            compiler.globalZeroSegment().copyToPreserveOffsets(result.globalZero.span());
        }

        const uint32_t initExtent = compiler.globalInitSegment().extentSize();
        if (initExtent)
        {
            result.globalInit.resize(initExtent);
            compiler.globalInitSegment().copyToPreserveOffsets(result.globalInit.span());
        }

        return result;
    }

    struct DataSegmentRestoreGuard
    {
        CompilerInstance*   compiler = nullptr;
        DataSegmentSnapshot snapshot;

        ~DataSegmentRestoreGuard()
        {
            if (!compiler)
                return;

            if (!snapshot.globalZero.empty())
                compiler->globalZeroSegment().restoreFromPreserveOffsets(snapshot.globalZero.span());
            if (!snapshot.globalInit.empty())
                compiler->globalInitSegment().restoreFromPreserveOffsets(snapshot.globalInit.span());
        }
    };

    bool runJitFunction(TaskContext& ctx, const SymbolFunction& function)
    {
        if (!function.jitEntryAddress())
            return false;

        JITExecManager::Request request;
        request.function     = &function;
        request.nodeRef      = function.declNodeRef();
        request.codeRef      = function.decl() ? function.decl()->codeRef() : SourceCodeRef::invalid();
        request.runImmediate = true;
        return CommandRun::afterPauses(ctx, [&] {
                   return ctx.compiler().jitExecMgr().submit(ctx, request);
               }) == Result::Continue &&
               !Stats::hasError();
    }

    // Like runJitFunction, but success is judged against the error count taken before
    // the call: once one test has failed, the global error state must not make every
    // following test look failed too.
    bool runJitTestFunction(TaskContext& ctx, const SymbolFunction& function)
    {
        if (!function.jitEntryAddress())
            return false;

        JITExecManager::Request request;
        request.function     = &function;
        request.nodeRef      = function.declNodeRef();
        request.codeRef      = function.decl() ? function.decl()->codeRef() : SourceCodeRef::invalid();
        request.runImmediate = true;

        const size_t errorsBefore = Stats::getNumErrors();
        while (true)
        {
            const Result result = ctx.compiler().jitExecMgr().submit(ctx, request);
            if (result == Result::Continue)
                break;
            if (result != Result::Pause)
                return false;

            Sema::waitDone(ctx, ctx.compiler().jobClientId());
            if (Stats::getNumErrors() != errorsBefore)
                return false;
        }

        return Stats::getNumErrors() == errorsBefore;
    }

    bool runJitTests(CompilerInstance& compiler)
    {
        if (!hasJitEligibleInputs(compiler))
            return true;

        SWC_MEM_SCOPE("Backend/JIT");
        TaskContext                   ctx(compiler);
        std::optional<ScopedTimedLog> stage;
        if (ScopedTimedLog::isOutputEnabled(ctx, ScopedTimedLog::Stage::JIT))
            stage.emplace(ctx, ScopedTimedLog::Stage::JIT);
        uint32_t expectedTestCount = 0;

        if (CommandRun::afterPauses(ctx, [&] {
                return compiler.ensureCompilerMessagePass(Runtime::CompilerMsgKind::PassBeforeRunByteCode);
            }) != Result::Continue)
            return false;

        std::vector<SymbolFunction*> allFunctions;
        std::vector<SymbolFunction*> initFunctions;
        std::vector<SymbolFunction*> preMainFunctions;
        std::vector<SymbolFunction*> testFunctions;

        {
            SWC_MEM_SCOPE("Backend/JIT/Prepare");
            NativeBackendBuilder nativeBuilder(compiler, false);
            if (nativeBuilder.prepare() != Result::Continue)
                return false;

            allFunctions                            = collectPreparedFunctions(nativeBuilder);
            const JitFunctionSelection jitSelection = selectJitFunctions(compiler, allFunctions, nativeBuilder.testFunctions);
            expectedTestCount                       = jitSelection.expectedTestCount;
            initFunctions                           = std::move(nativeBuilder.initFunctions);
            preMainFunctions                        = std::move(nativeBuilder.preMainFunctions);
            testFunctions                           = std::move(nativeBuilder.testFunctions);
            filterJitFunctions(allFunctions, jitSelection);
            filterJitFunctions(initFunctions, jitSelection);
            filterJitFunctions(preMainFunctions, jitSelection);
            filterJitFunctions(testFunctions, jitSelection);
        }

        SymbolSort::sortAndUniqueByLocation(allFunctions, ctx.compiler());
        SymbolSort::sortAndUniqueByLocation(initFunctions, ctx.compiler());
        SymbolSort::sortAndUniqueByLocation(preMainFunctions, ctx.compiler());
        SymbolSort::sortAndUniqueByLocation(testFunctions, ctx.compiler());

        if (testFunctions.size() != expectedTestCount)
            return reportJitTestCountMismatch(ctx, expectedTestCount, static_cast<uint32_t>(testFunctions.size()));

        // When a module has no #test functions there is nothing to run in the JIT test
        // phase. Executing its #init / #premain here is pointless (the native build still
        // runs them in the produced artifact) and, because #premain can recursively touch
        // typeinfo defined in other modules (e.g. Reflection.registerType walking a type
        // graph), running it concurrently with those modules' code generation in a parallel
        // workspace build races on the shared typeinfo data segments and can read a
        // half-materialized type (null fields buffer) -> JIT access violation. Skip it.
        if (testFunctions.empty())
            return true;

        {
            SWC_MEM_SCOPE("Backend/JIT/Compile");
            if (CommandRun::afterPauses(ctx, [&] {
                    return SymbolFunction::jitBatch(ctx, allFunctions);
                }) != Result::Continue)
                return false;
        }

        uint32_t jitReadyTestCount = 0;
        for (const SymbolFunction* function : testFunctions)
        {
            if (function && function->jitEntryAddress())
                jitReadyTestCount++;
        }

        if (jitReadyTestCount != expectedTestCount)
            return reportJitTestCountMismatch(ctx, expectedTestCount, jitReadyTestCount);

        DataSegmentRestoreGuard restoreGuard = {
            .compiler = &compiler,
            .snapshot = snapshotDataSegments(compiler),
        };

        for (const SymbolFunction* function : initFunctions)
        {
            if (!runJitFunction(ctx, *function))
                return false;
        }

        for (const SymbolFunction* function : preMainFunctions)
        {
            if (!runJitFunction(ctx, *function))
                return false;
        }

        // Run every test even when one fails: a failing #test has already reported its
        // diagnostic through the JIT exception handler, so keep executing the remaining
        // tests and report a pass/fail tally instead of stopping at the first failure.
        uint32_t executedTestCount = 0;
        uint32_t failedTestCount   = 0;
        // With SWC_PROFILE_TESTS set, print how long each #test took: the first tool
        // to reach for when a test suite gets slow.
        const bool profileTests = Os::readEnvironmentVariable("SWC_PROFILE_TESTS").has_value();
        for (const SymbolFunction* function : testFunctions)
        {
            const auto startTick = std::chrono::steady_clock::now();
            if (!runJitTestFunction(ctx, *function))
                failedTestCount++;
            executedTestCount++;
            if (profileTests)
            {
                const double      ms   = static_cast<double>(std::chrono::duration_cast<std::chrono::microseconds>(std::chrono::steady_clock::now() - startTick).count()) / 1000.0;
                const SourceFile* file = ctx.compiler().srcView(function->srcViewRef()).file();
                uint32_t          line = 0;
                if (const AstNode* decl = function->decl(); decl && file)
                {
                    const SourceView& declView = ctx.compiler().srcView(decl->srcViewRef());
                    line                       = decl->codeRangeWithChildren(ctx, file->ast(), declView).line + 1;
                }
                fprintf(stderr, "[test-profile] %9.1f ms %s:%u\n", ms, file ? file->path().filename().string().c_str() : "?", line);
            }
        }

        if (stage)
        {
            std::vector<Utf8> statParts;
            ScopedTimedLog::appendTestStats(ctx, statParts, executedTestCount, failedTestCount);
            stage->setStat(ScopedTimedLog::joinStatItems(ctx, statParts));
        }
        Stats::get().numTests.fetch_add(executedTestCount, std::memory_order_relaxed);
        Stats::get().numTestsFailed.fetch_add(failedTestCount, std::memory_order_relaxed);

        if (executedTestCount != expectedTestCount)
            return reportJitTestCountMismatch(ctx, expectedTestCount, executedTestCount);

        return !Stats::hasError();
    }

    bool finishTestCommand(CompilerInstance& compiler)
    {
        if (compiler.cmdLine().testJit && !runJitTests(compiler))
            return false;

        if (compiler.cmdLine().testNative && compiler.cmdLine().output)
        {
            if (hasNativeArtifactEntryPoints(compiler))
            {
                const Runtime::BuildCfgBackendKind backendKind = effectiveBackendKind(compiler.cmdLine(), compiler.buildCfg().backendKind);
                compiler.buildCfg().backendKind                = backendKind;
                if (Runtime::backendKindProducesNativeArtifact(backendKind))
                {
                    TaskContext          ctx(compiler);
                    NativeBackendBuilder builder(compiler, backendKind == Runtime::BuildCfgBackendKind::Executable);
                    const Result buildResult = CommandRun::afterPauses(ctx, [&] {
                        return builder.run();
                    });

                    // The JIT phase already counted the executed tests. When it is disabled the
                    // native artifact is the one that runs them, so account for them here instead,
                    // preferring the tally the executable reported over the static function count.
                    if (!compiler.cmdLine().testJit)
                    {
                        Stats::get().numTests.fetch_add(builder.hasNativeTestSummary ? builder.nativeTestsExecuted : builder.testFunctions.size(), std::memory_order_relaxed);
                        Stats::get().numTestsFailed.fetch_add(builder.nativeTestsFailed, std::memory_order_relaxed);
                    }

                    if (buildResult != Result::Continue)
                        return false;

                    if (Stats::hasError())
                        return false;

                    std::optional<ScopedTimedLog> stage;
                    if (ScopedTimedLog::isOutputEnabled(ctx, ScopedTimedLog::Stage::Verify))
                        stage.emplace(ctx, ScopedTimedLog::Stage::Verify);
                    verifyExpectedMarkers(ctx);
                    return !Stats::hasError();
                }
            }
        }

        TaskContext                   ctx(compiler);
        std::optional<ScopedTimedLog> stage;
        if (ScopedTimedLog::isOutputEnabled(ctx, ScopedTimedLog::Stage::Verify))
            stage.emplace(ctx, ScopedTimedLog::Stage::Verify);
        verifyExpectedMarkers(ctx);
        return !Stats::hasError();
    }

}

namespace Command
{
    void test(CompilerInstance& compiler)
    {
        SWC_ASSERT(compiler.cmdLine().command == CommandKind::Test);
        TaskContext                   ctx(compiler);
        std::optional<ScopedTimedLog> stage;
        if (ScopedTimedLog::isOutputEnabled(ctx, ScopedTimedLog::Stage::Test))
            stage.emplace(ctx, ScopedTimedLog::Stage::Test);

        bool           testPassed   = true;
        const uint64_t errorsBefore = Stats::getNumErrors();
        {
            Logger::ScopedStageMute muteNestedStages(ctx.global().logger());

            sema(compiler);
            if (Stats::getNumErrors() != errorsBefore)
                testPassed = false;
            else
                testPassed = finishTestCommand(compiler);
        }

        if (!testPassed)
        {
            if (stage)
                stage->markFailure();
        }

        if (stage)
            stage->setStat(formatTestStageStat(ctx, stage->delta()));

        if (!testPassed && !Stats::hasError())
        {
            const Diagnostic diag = Diagnostic::get(DiagnosticId::cmd_err_test_command_failed);
            diag.report(ctx);
        }
    }
}

SWC_END_NAMESPACE();
