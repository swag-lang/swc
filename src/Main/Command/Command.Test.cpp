#include "pch.h"
#include "Main/Command/Command.h"
#include "Backend/JIT/JITExecManager.h"
#include "Backend/Native/NativeBackendBuilder.h"
#include "Backend/Native/SymbolSort.h"
#include "Compiler/Sema/Core/Sema.h"
#include "Compiler/Sema/Symbol/Symbol.Function.h"
#include "Compiler/SourceFile.h"
#include "Compiler/Verify.h"
#include "Main/Command/CommandLine.h"
#include "Main/CompilerInstance.h"
#include "Main/Stats.h"
#include "Support/Core/Utf8Helper.h"
#include "Support/Memory/MemoryProfile.h"
#include "Support/Report/Diagnostic.h"
#include "Support/Report/ScopedTimedAction.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    bool hasErrors(const uint64_t errorsBefore)
    {
        return Stats::getNumErrors() != errorsBefore;
    }

    template<typename FUNC>
    Result runAfterPauses(TaskContext& ctx, const FUNC& func)
    {
        while (true)
        {
            const Result result = func();
            if (result != Result::Pause)
                return result;

            Sema::waitDone(ctx, ctx.compiler().jobClientId());
            if (Stats::hasError())
                return Result::Error;
        }
    }

    bool shouldRunNativeTests(const CommandLine& cmdLine)
    {
        return cmdLine.testNative && cmdLine.output;
    }

    bool hasJitEligibleInputs(const CompilerInstance& compiler)
    {
        for (SourceFile* file : compiler.files())
        {
            if (!file || file->isRuntime())
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

        const TaskContext     ctx(compiler.global(), compiler.cmdLine());
        const SourceCodeRange startRange = decl->codeRangeWithChildren(ctx, file->ast(), file->ast().srcView());
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

    bool shouldRunJitFunction(const CompilerInstance& compiler, const SymbolFunction& function)
    {
        if (shouldSkipFunctionForTests(compiler, function))
            return false;

        const SourceFile* file = compiler.srcView(function.srcViewRef()).file();
        return !file || file->ast().srcView().runsJit();
    }

    bool shouldRunNativeArtifactFunction(const CompilerInstance& compiler, const SymbolFunction& function)
    {
        if (shouldSkipFunctionForTests(compiler, function))
            return false;

        const SourceFile* file = compiler.srcView(function.srcViewRef()).file();
        return !file || file->ast().srcView().runsNativeArtifact();
    }

    bool reportJitTestCountMismatch(TaskContext& ctx, const uint32_t expectedCount, const uint32_t actualCount)
    {
        Diagnostic diag = Diagnostic::get(DiagnosticId::cmd_err_jit_test_count_mismatch);
        diag.addArgument(Diagnostic::ARG_COUNT, expectedCount);
        diag.addArgument(Diagnostic::ARG_VALUE, actualCount);
        diag.report(ctx);
        return false;
    }

    uint32_t expectedJitTestCount(const CompilerInstance& compiler)
    {
        uint32_t result = 0;
        for (const SymbolFunction* function : compiler.nativeTestFunctions())
        {
            if (function && shouldRunJitFunction(compiler, *function))
                result++;
        }

        return result;
    }

    bool hasArtifactEntryPoints(const CompilerInstance& compiler)
    {
        for (const SymbolFunction* function : compiler.nativeTestFunctions())
        {
            if (function && shouldRunNativeArtifactFunction(compiler, *function))
                return true;
        }

        for (const SymbolFunction* function : compiler.nativeMainFunctions())
        {
            if (function && shouldRunNativeArtifactFunction(compiler, *function))
                return true;
        }

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

            const SourceView& srcView = file->ast().srcView();
            if (srcView.mustSkip())
                continue;
            file->unitTest().verifyUntouchedExpected(ctx, srcView);
        }
    }

    bool runNativeBackend(CompilerInstance& compiler, const Runtime::BuildCfgBackendKind backendKind, const bool runArtifact)
    {
        compiler.buildCfg().backendKind = backendKind;

        NativeBackendBuilder builder(compiler, runArtifact);
        if (builder.run() != Result::Continue)
            return false;

        return !Stats::hasError();
    }

    bool runNativeBackends(CompilerInstance& compiler)
    {
        const Runtime::BuildCfgBackendKind backendKind = compiler.buildCfg().backendKind;
        if (!runNativeBackend(compiler, backendKind, backendKind == Runtime::BuildCfgBackendKind::Executable))
            return false;

        TaskContext                 ctx(compiler);
        TimedActionLog::ScopedStage stage(ctx, "Verify", "checking expectations", "source-driven expectations");
        verifyExpectedMarkers(ctx);
        return !Stats::hasError();
    }

    void sortAndUniqueFunctions(std::vector<SymbolFunction*>& values, const TaskContext& ctx)
    {
        SymbolSort::sortAndUniqueByLocation(values, ctx.compiler());
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

    void restoreDataSegment(const DataSegment& segment, const std::vector<std::byte>& snapshot)
    {
        if (snapshot.empty())
            return;

        segment.restoreFromPreserveOffsets(ByteSpan{snapshot.data(), snapshot.size()});
    }

    struct DataSegmentRestoreGuard
    {
        CompilerInstance*   compiler = nullptr;
        DataSegmentSnapshot snapshot;

        ~DataSegmentRestoreGuard()
        {
            if (!compiler)
                return;

            restoreDataSegment(compiler->globalZeroSegment(), snapshot.globalZero);
            restoreDataSegment(compiler->globalInitSegment(), snapshot.globalInit);
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
        return runAfterPauses(ctx, [&] {
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
        const uint32_t              expectedTestCount = expectedJitTestCount(compiler);
        TimedActionLog::ScopedStage stage(ctx, "JIT", "sparking test code", "compiler test entry points");

        std::vector<SymbolFunction*> allFunctions;
        std::vector<SymbolFunction*> initFunctions;
        std::vector<SymbolFunction*> preMainFunctions;
        std::vector<SymbolFunction*> testFunctions;

        {
            SWC_MEM_SCOPE("Backend/JIT/Prepare");
            NativeBackendBuilder nativeBuilder(compiler, false);
            if (nativeBuilder.prepare() != Result::Continue)
                return false;

            allFunctions = compiler.nativeCodeSegment();
            std::erase_if(allFunctions, [&](const SymbolFunction* function) {
                return function == nullptr || !shouldRunJitFunction(compiler, *function);
            });
            initFunctions    = std::move(nativeBuilder.initFunctions);
            preMainFunctions = std::move(nativeBuilder.preMainFunctions);
            testFunctions    = std::move(nativeBuilder.testFunctions);
        }

        sortAndUniqueFunctions(allFunctions, ctx);
        sortAndUniqueFunctions(initFunctions, ctx);
        sortAndUniqueFunctions(preMainFunctions, ctx);
        sortAndUniqueFunctions(testFunctions, ctx);

        if (testFunctions.size() != expectedTestCount)
            return reportJitTestCountMismatch(ctx, expectedTestCount, static_cast<uint32_t>(testFunctions.size()));

        if (initFunctions.empty() && preMainFunctions.empty() && testFunctions.empty())
            return true;

        {
            SWC_MEM_SCOPE("Backend/JIT/Compile");
            if (runAfterPauses(ctx, [&] {
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

        stage.setStat(Utf8Helper::countWithLabel(executedTestCount, "test"));

        if (executedTestCount != expectedTestCount)
            return reportJitTestCountMismatch(ctx, expectedTestCount, executedTestCount);

        return !Stats::hasError();
    }

    bool finishTestCommand(CompilerInstance& compiler)
    {
        if (compiler.cmdLine().testJit && !runJitTests(compiler))
            return false;

        if (shouldRunNativeTests(compiler.cmdLine()) && hasArtifactEntryPoints(compiler))
            return runNativeBackends(compiler);

        TaskContext                 ctx(compiler);
        TimedActionLog::ScopedStage stage(ctx, "Verify", "checking expectations", "source-driven expectations");
        verifyExpectedMarkers(ctx);
        return !Stats::hasError();
    }

    void runNativeTestCommand(CompilerInstance& compiler)
    {
        const TaskContext ctx(compiler);
        TimedActionLog::printBuildConfiguration(ctx);
        const uint64_t errorsBefore = Stats::getNumErrors();
        Command::sema(compiler);
        if (hasErrors(errorsBefore))
            return;

        finishTestCommand(compiler);
    }
}

namespace Command
{
    void test(CompilerInstance& compiler)
    {
        SWC_ASSERT(compiler.cmdLine().isTestCommand());
        runNativeTestCommand(compiler);
    }
}

SWC_END_NAMESPACE();
