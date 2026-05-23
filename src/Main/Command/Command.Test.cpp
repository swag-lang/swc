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
#include "Main/Stats.h"
#include "Support/Memory/MemoryProfile.h"
#include "Support/Report/Diagnostic.h"
#include "Support/Report/ScopedTimedAction.h"

SWC_BEGIN_NAMESPACE();

namespace
{
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
        std::vector<std::byte> globalZero;
        std::vector<std::byte> globalInit;
    };

    DataSegmentSnapshot snapshotDataSegments(const CompilerInstance& compiler)
    {
        DataSegmentSnapshot result;

        const uint32_t zeroExtent = compiler.globalZeroSegment().extentSize();
        if (zeroExtent)
        {
            result.globalZero.resize(zeroExtent);
            compiler.globalZeroSegment().copyToPreserveOffsets(ByteSpanRW{result.globalZero.data(), result.globalZero.size()});
        }

        const uint32_t initExtent = compiler.globalInitSegment().extentSize();
        if (initExtent)
        {
            result.globalInit.resize(initExtent);
            compiler.globalInitSegment().copyToPreserveOffsets(ByteSpanRW{result.globalInit.data(), result.globalInit.size()});
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
                compiler->globalZeroSegment().restoreFromPreserveOffsets(ByteSpan{snapshot.globalZero.data(), snapshot.globalZero.size()});
            if (!snapshot.globalInit.empty())
                compiler->globalInitSegment().restoreFromPreserveOffsets(ByteSpan{snapshot.globalInit.data(), snapshot.globalInit.size()});
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

    bool runJitTests(CompilerInstance& compiler)
    {
        if (!hasJitEligibleInputs(compiler))
            return true;

        SWC_MEM_SCOPE("Backend/JIT");
        TaskContext                 ctx(compiler);
        TimedActionLog::ScopedStage stage(ctx, TimedActionLog::Stage::JIT);
        uint32_t                    expectedTestCount = 0;

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

        if (initFunctions.empty() && preMainFunctions.empty() && testFunctions.empty())
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

        uint32_t executedTestCount = 0;
        for (const SymbolFunction* function : testFunctions)
        {
            if (!runJitFunction(ctx, *function))
                return false;
            executedTestCount++;
        }

        stage.setStat(TimedActionLog::formatStatCount(ctx, executedTestCount, "test"));

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
                    if (CommandRun::afterPauses(ctx, [&] {
                            return builder.run();
                        }) != Result::Continue)
                        return false;

                    if (Stats::hasError())
                        return false;

                    TimedActionLog::ScopedStage stage(ctx, TimedActionLog::Stage::Verify);
                    verifyExpectedMarkers(ctx);
                    return !Stats::hasError();
                }
            }
        }

        TaskContext                 ctx(compiler);
        TimedActionLog::ScopedStage stage(ctx, TimedActionLog::Stage::Verify);
        verifyExpectedMarkers(ctx);
        return !Stats::hasError();
    }

}

namespace Command
{
    void test(CompilerInstance& compiler)
    {
        SWC_ASSERT(compiler.cmdLine().command == CommandKind::Test);
        TaskContext    ctx(compiler);
        const uint64_t errorsBefore = Stats::getNumErrors();
        sema(compiler);
        if (Stats::getNumErrors() != errorsBefore)
            return;

        if (!finishTestCommand(compiler) && !Stats::hasError())
        {
            const Diagnostic diag = Diagnostic::get(DiagnosticId::cmd_err_test_command_failed);
            diag.report(ctx);
        }
    }
}

SWC_END_NAMESPACE();
