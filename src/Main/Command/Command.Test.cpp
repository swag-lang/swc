#include "pch.h"
#include "Main/Command/Command.h"
#include "Backend/JIT/JITExecManager.h"
#include "Backend/Native/NativeBackendBuilder.h"
#include "Compiler/Sema/Symbol/Symbol.Function.h"
#include "Compiler/SourceFile.h"
#include "Compiler/Verify.h"
#include "Main/Command/CommandLine.h"
#include "Main/CompilerInstance.h"
#include "Main/Stats.h"
#include "Support/Report/ScopedTimedAction.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    template<typename T>
    struct SortEntry
    {
        T*   symbol = nullptr;
        Utf8 key;
    };

    bool hasErrors(const uint64_t errorsBefore)
    {
        return Stats::get().numErrors.load(std::memory_order_relaxed) != errorsBefore;
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

    bool shouldRunJitFunction(const CompilerInstance& compiler, const SymbolFunction& function)
    {
        const SourceFile* file = compiler.srcView(function.srcViewRef()).file();
        return !file || file->ast().srcView().runsJit();
    }

    bool shouldRunNativeArtifactFunction(const CompilerInstance& compiler, const SymbolFunction& function)
    {
        const SourceFile* file = compiler.srcView(function.srcViewRef()).file();
        return !file || file->ast().srcView().runsNativeArtifact();
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
        if (Stats::get().numErrors.load(std::memory_order_relaxed) != 0)
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

        return Stats::get().numErrors.load(std::memory_order_relaxed) == 0;
    }

    bool runNativeBackends(CompilerInstance& compiler)
    {
        const Runtime::BuildCfgBackendKind backendKind = compiler.buildCfg().backendKind;
        if (!runNativeBackend(compiler, backendKind, backendKind == Runtime::BuildCfgBackendKind::Executable))
            return false;

        TaskContext ctx(compiler);
        TimedActionLog::ScopedStage stage(ctx, {
            .key    = "verify",
            .label  = "Verify",
            .verb   = "checking expectations",
            .detail = "source-driven expectations",
        });
        verifyExpectedMarkers(ctx);
        return Stats::get().numErrors.load(std::memory_order_relaxed) == 0;
    }

    template<typename T>
    Utf8 makeSymbolLocationSortKey(const TaskContext& ctx, const T& symbol)
    {
        Utf8 key;
        if (const SourceFile* file = ctx.compiler().srcView(symbol.srcViewRef()).file())
            key += Utf8(file->path());

        key += "|";
        key += std::to_string(symbol.tokRef().get());
        return key;
    }

    Utf8 makeFunctionSortKey(const TaskContext& ctx, const SymbolFunction& symbol)
    {
        return makeSymbolLocationSortKey(ctx, symbol);
    }

    void sortAndUniqueFunctions(std::vector<SymbolFunction*>& values, const TaskContext& ctx)
    {
        std::erase(values, nullptr);
        if (values.size() < 2)
            return;

        std::vector<SortEntry<SymbolFunction>> entries;
        entries.reserve(values.size());
        for (SymbolFunction* symbol : values)
        {
            SWC_ASSERT(symbol != nullptr);
            entries.push_back({.symbol = symbol, .key = makeFunctionSortKey(ctx, *symbol)});
        }

        std::ranges::stable_sort(entries, [](const SortEntry<SymbolFunction>& lhs, const SortEntry<SymbolFunction>& rhs) {
            return lhs.key < rhs.key;
        });

        values.clear();
        values.reserve(entries.size());
        const SymbolFunction* previous = nullptr;
        for (const auto& entry : entries)
        {
            if (entry.symbol == previous)
                continue;

            values.push_back(entry.symbol);
            previous = entry.symbol;
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

    void restoreDataSegment(DataSegment& segment, const std::vector<std::byte>& snapshot)
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
        return ctx.compiler().jitExecMgr().submit(ctx, request) == Result::Continue &&
               Stats::get().numErrors.load(std::memory_order_relaxed) == 0;
    }

    bool runJitTests(CompilerInstance& compiler)
    {
        if (!hasJitEligibleInputs(compiler))
            return true;

        TaskContext ctx(compiler);
        TimedActionLog::ScopedStage stage(ctx, {
            .key    = "jit",
            .label  = "JIT",
            .verb   = "sparking test code",
            .detail = "compiler test entry points",
        });

        NativeBackendBuilder nativeBuilder(compiler, false);
        if (nativeBuilder.prepare() != Result::Continue)
            return false;

        auto allFunctions = compiler.nativeCodeSegment();
        std::erase_if(allFunctions, [&](const SymbolFunction* function) {
            return function == nullptr || !shouldRunJitFunction(compiler, *function);
        });
        auto initFunctions    = nativeBuilder.initFunctions;
        auto preMainFunctions = nativeBuilder.preMainFunctions;
        auto testFunctions    = nativeBuilder.testFunctions;

        sortAndUniqueFunctions(allFunctions, ctx);
        sortAndUniqueFunctions(initFunctions, ctx);
        sortAndUniqueFunctions(preMainFunctions, ctx);
        sortAndUniqueFunctions(testFunctions, ctx);

        if (initFunctions.empty() && preMainFunctions.empty() && testFunctions.empty())
            return true;

        if (!SymbolFunction::jitBatch(ctx, allFunctions))
            return false;

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

        for (const SymbolFunction* function : testFunctions)
        {
            if (!runJitFunction(ctx, *function))
                return false;
        }

        return true;
    }

    bool finishTestCommand(CompilerInstance& compiler)
    {
        if (compiler.cmdLine().testJit && !runJitTests(compiler))
            return false;

        if (shouldRunNativeTests(compiler.cmdLine()) && hasArtifactEntryPoints(compiler))
            return runNativeBackends(compiler);

        TaskContext ctx(compiler);
        TimedActionLog::ScopedStage stage(ctx, {
            .key    = "verify",
            .label  = "Verify",
            .verb   = "checking expectations",
            .detail = "source-driven expectations",
        });
        verifyExpectedMarkers(ctx);
        return Stats::get().numErrors.load(std::memory_order_relaxed) == 0;
    }

    void runNativeTestCommand(CompilerInstance& compiler)
    {
        const TaskContext ctx(compiler);
        TimedActionLog::printBuildConfiguration(ctx);
        const uint64_t errorsBefore = Stats::get().numErrors.load(std::memory_order_relaxed);
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
