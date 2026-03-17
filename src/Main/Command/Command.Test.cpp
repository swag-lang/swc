#include "pch.h"
#include "Main/Command/Command.h"
#include "Backend/JIT/JITExecManager.h"
#include "Backend/Native/NativeBackendBuilder.h"
#include "Compiler/Sema/Symbol/Symbol.Function.h"
#include "Compiler/SourceFile.h"
#include "Compiler/Verify.h"
#include "Main/Command/CommandLine.h"
#include "Main/Command/CommandLineParser.h"
#include "Main/CompilerInstance.h"
#include "Main/Stats.h"
#include "Support/Core/Utf8Helper.h"
#include "Support/Report/ScopedTimedAction.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    using TestSuiteKind = SourceTestKind;

    struct SourceSuiteBuckets
    {
        std::vector<fs::path> syntaxFiles;
        std::vector<fs::path> semaFiles;
        std::vector<fs::path> jitFiles;
        std::vector<fs::path> nativeFiles;
        bool                  hasSourceHints = false;
    };

#if SWC_HAS_STATS
    struct DiscoveryStatsGuard
    {
        DiscoveryStatsGuard()
        {
            const auto& stats = Stats::get();
            timeLoadFile_     = stats.timeLoadFile.load(std::memory_order_relaxed);
            timeLexer_        = stats.timeLexer.load(std::memory_order_relaxed);
            numFiles_         = stats.numFiles.load(std::memory_order_relaxed);
        }

        ~DiscoveryStatsGuard()
        {
            auto& stats = Stats::get();
            stats.timeLoadFile.store(timeLoadFile_, std::memory_order_relaxed);
            stats.timeLexer.store(timeLexer_, std::memory_order_relaxed);
            stats.numFiles.store(numFiles_, std::memory_order_relaxed);
        }

        uint64_t timeLoadFile_ = 0;
        uint64_t timeLexer_    = 0;
        size_t   numFiles_     = 0;
    };
#endif

    bool shouldRunNativeTests(const CommandLine& cmdLine)
    {
        return cmdLine.testNative;
    }

    void registerSourceFile(SourceSuiteBuckets& outBuckets, const fs::path& path, const Verify& verify)
    {
        const TestSuiteKind kind = verify.sourceTestKind();
        outBuckets.hasSourceHints |= verify.hasSourceTestHints();

        switch (kind)
        {
            case TestSuiteKind::Syntax:
                outBuckets.syntaxFiles.push_back(path);
                break;
            case TestSuiteKind::Jit:
                outBuckets.jitFiles.push_back(path);
                break;
            case TestSuiteKind::Native:
                outBuckets.nativeFiles.push_back(path);
                break;
            case TestSuiteKind::Sema:
            case TestSuiteKind::Unknown:
                outBuckets.semaFiles.push_back(path);
                break;
        }
    }

    void collectStandaloneSourceSuites(SourceSuiteBuckets& outBuckets, CompilerInstance& compiler)
    {
        CommandLine cmdLine = compiler.cmdLine();
        cmdLine.runtime     = false;

        CompilerInstance discoveryCompiler(compiler.global(), cmdLine);
        TaskContext      ctx(discoveryCompiler);

        ctx.setSilentDiagnostic(true);

#if SWC_HAS_STATS
        const DiscoveryStatsGuard statsGuard;
#endif

        if (discoveryCompiler.collectFiles(ctx) != Result::Continue)
            return;

        for (SourceFile* const file : discoveryCompiler.files())
        {
            if (file->loadContent(ctx) != Result::Continue)
                continue;

            file->unitTest().tokenize(ctx);
            registerSourceFile(outBuckets, file->path(), file->unitTest());
        }
    }

    fs::path commonPathPrefix(const fs::path& lhs, const fs::path& rhs)
    {
        fs::path result;
        auto     itLhs = lhs.begin();
        auto     itRhs = rhs.begin();
        while (itLhs != lhs.end() && itRhs != rhs.end() && *itLhs == *itRhs)
        {
            result /= *itLhs;
            ++itLhs;
            ++itRhs;
        }

        return result;
    }

    Utf8 displayPath(const fs::path& path)
    {
        std::error_code ec;
        const fs::path  currentPath = fs::current_path(ec);
        if (!ec)
        {
            std::error_code relEc;
            const fs::path  relative = fs::relative(path, currentPath, relEc);
            if (!relEc && !relative.empty())
                return Utf8{relative.generic_string()};
        }

        return Utf8{path.generic_string()};
    }

    Utf8 formatSourceLocation(const std::vector<fs::path>& roots)
    {
        if (roots.empty())
            return "sources";

        fs::path          commonRoot;
        std::vector<Utf8> labels;
        for (const fs::path& root : roots)
        {
            const fs::path normalized = root.lexically_normal();
            if (commonRoot.empty())
                commonRoot = normalized;
            else
                commonRoot = commonPathPrefix(commonRoot, normalized);

            labels.push_back(displayPath(normalized));
        }

        std::ranges::sort(labels);
        labels.erase(std::ranges::unique(labels).begin(), labels.end());

        if (labels.size() == 1)
            return labels.front();

        if (!commonRoot.empty() && commonRoot != "." && commonRoot != commonRoot.root_path())
            return displayPath(commonRoot);

        return std::format("{} locations", Utf8Helper::toNiceBigNumber(labels.size()));
    }

    Utf8 formatSourceFilesLocation(const std::vector<fs::path>& files)
    {
        std::vector<fs::path> roots;
        roots.reserve(files.size());
        for (const fs::path& file : files)
            roots.push_back(file.parent_path().empty() ? file : file.parent_path());

        return formatSourceLocation(roots);
    }

    Utf8 formatCommandSourceRoots(const CommandLine& cmdLine)
    {
        std::vector<fs::path> roots;
        if (!cmdLine.modulePath.empty())
            roots.push_back(cmdLine.modulePath);
        for (const fs::path& folder : cmdLine.directories)
            roots.push_back(folder);
        for (const fs::path& file : cmdLine.files)
            roots.push_back(file.parent_path().empty() ? file : file.parent_path());

        return formatSourceLocation(roots);
    }

    bool hasNewErrors(const uint64_t errorsBefore)
    {
        return Stats::get().numErrors.load(std::memory_order_relaxed) != errorsBefore;
    }

    bool finishAction(ScopedTimedAction& action, const uint64_t errorsBefore)
    {
        if (hasNewErrors(errorsBefore))
        {
            action.fail();
            return false;
        }

        action.success();
        return true;
    }

    void verifyExpectedMarkers(TaskContext& ctx)
    {
        if (Stats::get().numErrors.load(std::memory_order_relaxed) != 0)
            return;

        for (SourceFile* const file : ctx.compiler().files())
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
        verifyExpectedMarkers(ctx);
        return Stats::get().numErrors.load(std::memory_order_relaxed) == 0;
    }

    Utf8 makeFunctionSortKey(const TaskContext& ctx, const SymbolFunction& symbol)
    {
        Utf8 key;
        if (const SourceFile* file = ctx.compiler().srcView(symbol.srcViewRef()).file())
            key += Utf8(file->path());

        key += "|";
        key += std::to_string(symbol.tokRef().get());
        key += "|";
        key += symbol.getFullScopedName(ctx);
        key += "|";
        key += symbol.computeName(ctx);
        return key;
    }

    void sortAndUniqueFunctions(std::vector<SymbolFunction*>& values, const TaskContext& ctx)
    {
        std::erase(values, nullptr);
        std::ranges::sort(values, [&](const SymbolFunction* lhs, const SymbolFunction* rhs) {
            if (lhs == rhs)
                return false;

            const Utf8 lhsKey = makeFunctionSortKey(ctx, *lhs);
            const Utf8 rhsKey = makeFunctionSortKey(ctx, *rhs);
            if (lhsKey != rhsKey)
                return lhsKey < rhsKey;
            return lhs < rhs;
        });

        values.erase(std::ranges::unique(values).begin(), values.end());
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

        std::byte* const dst = segment.ptr<std::byte>(0);
        SWC_ASSERT(dst != nullptr);
        std::memcpy(dst, snapshot.data(), snapshot.size());
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
        NativeBackendBuilder nativeBuilder(compiler, false);
        if (nativeBuilder.prepare() != Result::Continue)
            return false;

        TaskContext ctx(compiler);

        auto allFunctions     = compiler.nativeCodeSegment();
        auto initFunctions    = compiler.nativeInitFunctions();
        auto preMainFunctions = compiler.nativePreMainFunctions();
        auto testFunctions    = compiler.nativeTestFunctions();

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

        if (shouldRunNativeTests(compiler.cmdLine()))
            return runNativeBackends(compiler);

        TaskContext ctx(compiler);
        verifyExpectedMarkers(ctx);
        return Stats::get().numErrors.load(std::memory_order_relaxed) == 0;
    }

    bool runCompilerSubset(CompilerInstance& compiler, const CommandKind command, const std::vector<fs::path>& files, std::string_view backendKindName = {}, const std::optional<bool> testJit = std::nullopt, const std::optional<bool> testNative = std::nullopt)
    {
        if (files.empty())
            return true;

        const TaskContext ctx(compiler);
        CommandLine       cmdLine = compiler.cmdLine();
        cmdLine.command           = command;
        cmdLine.directories.clear();
        cmdLine.files.clear();
        cmdLine.modulePath.clear();
        cmdLine.files.insert(files.begin(), files.end());
        if (!backendKindName.empty())
            cmdLine.backendKindName = backendKindName;
        if (testJit.has_value())
            cmdLine.testJit = testJit.value();
        if (testNative.has_value())
            cmdLine.testNative = testNative.value();
        if (command == CommandKind::Syntax)
            cmdLine.runtime = false;

        CommandLineParser::refreshBuildCfg(cmdLine);

        const uint64_t   errorsBefore = Stats::get().numErrors.load(std::memory_order_relaxed);
        CompilerInstance subCompiler(compiler.global(), cmdLine);

        switch (command)
        {
            case CommandKind::Syntax:
            {
                ScopedTimedAction parseAction(ctx, "Parse", formatSourceFilesLocation(files));
                Command::syntax(subCompiler);
                finishAction(parseAction, errorsBefore);
                break;
            }

            case CommandKind::Sema:
            {
                ScopedTimedAction checkAction(ctx, "Check", formatSourceFilesLocation(files));
                Command::sema(subCompiler);
                finishAction(checkAction, errorsBefore);
                break;
            }

            case CommandKind::Test:
            {
                ScopedTimedAction checkAction(ctx, "Check", formatSourceFilesLocation(files));
                Command::sema(subCompiler);
                if (finishAction(checkAction, errorsBefore))
                    finishTestCommand(subCompiler);
                break;
            }

            default:
                SWC_UNREACHABLE();
        }

        return !hasNewErrors(errorsBefore);
    }

    bool runStandaloneSourceDrivenSuites(CompilerInstance& compiler)
    {
        const CommandLine& cmdLine = compiler.cmdLine();
        SWC_ASSERT(cmdLine.isTestCommand());

        if (!cmdLine.modulePath.empty())
            return false;
        if (cmdLine.directories.empty() && cmdLine.files.empty())
            return false;

        SourceSuiteBuckets buckets;
        const TaskContext  ctx(compiler);
        TimedActionLog::printBuildConfiguration(ctx);
        ScopedTimedAction discoverAction(ctx, "Discover", formatCommandSourceRoots(cmdLine));
        collectStandaloneSourceSuites(buckets, compiler);
        if (!buckets.hasSourceHints)
        {
            discoverAction.fail();
            return false;
        }

        if (buckets.syntaxFiles.empty() && buckets.semaFiles.empty() && buckets.jitFiles.empty() && buckets.nativeFiles.empty())
        {
            discoverAction.fail();
            return false;
        }

        discoverAction.success();

        if (!runCompilerSubset(compiler, CommandKind::Syntax, buckets.syntaxFiles))
            return true;
        if (!runCompilerSubset(compiler, CommandKind::Sema, buckets.semaFiles))
            return true;
        if (!runCompilerSubset(compiler, CommandKind::Test, buckets.jitFiles, compiler.cmdLine().backendKindName, compiler.cmdLine().testJit, false))
            return true;

        runCompilerSubset(compiler, CommandKind::Test, buckets.nativeFiles, compiler.cmdLine().backendKindName, compiler.cmdLine().testJit, compiler.cmdLine().testNative);
        return true;
    }

    void runNativeTestCommand(CompilerInstance& compiler)
    {
        if (runStandaloneSourceDrivenSuites(compiler))
            return;

        const TaskContext ctx(compiler);
        TimedActionLog::printBuildConfiguration(ctx);
        ScopedTimedAction checkAction(ctx, "Check", formatCommandSourceRoots(ctx.cmdLine()));
        const uint64_t    errorsBefore = Stats::get().numErrors.load(std::memory_order_relaxed);
        Command::sema(compiler);
        if (!finishAction(checkAction, errorsBefore))
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
