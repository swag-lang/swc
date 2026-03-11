#include "pch.h"
#include "Main/Command.h"
#include "Backend/JIT/JITExecManager.h"
#include "Backend/Native/NativeBackendBuilder.h"
#include "Compiler/Sema/Symbol/Symbol.Function.h"
#include "Main/CommandLine.h"
#include "Main/CommandLineParser.h"
#include "Main/CompilerInstance.h"
#include "Main/Stats.h"
#include "Wmf/SourceFile.h"
#include "Wmf/Verify.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    enum class TestSuiteKind
    {
        Unknown,
        Syntax,
        Sema,
        Test,
    };

    struct SourceSuiteClassification
    {
        TestSuiteKind kind      = TestSuiteKind::Unknown;
        bool          hasSource = false;
    };

    struct SourceSuiteBuckets
    {
        std::vector<fs::path> syntaxFiles;
        std::vector<fs::path> semaFiles;
        std::vector<fs::path> testFiles;
        bool                  hasSourceHints = false;
    };

    constexpr std::string_view VERIFY_OPTION_PREFIX_A = "swc-option ";
    constexpr std::string_view VERIFY_OPTION_PREFIX_B = "swc-options ";
    constexpr std::string_view VERIFY_SUITE_SYNTAX    = "suite-syntax";
    constexpr std::string_view VERIFY_SUITE_SEMA      = "suite-sema";
    constexpr std::string_view VERIFY_SUITE_TEST      = "suite-test";
    constexpr std::string_view VERIFY_LEX_ONLY        = "lex-only";
    constexpr std::string_view EXPECTED_PARSER_ID     = "{{parser_";
    constexpr std::string_view EXPECTED_LEX_ID        = "{{lex_";
    constexpr std::string_view EXPECTED_SEMA_ID       = "{{sema_";
    constexpr std::string_view BACKEND_KIND_ALL       = "all";

    bool pathMatchesFilter(const CommandLine& cmdLine, const fs::path& path)
    {
        if (cmdLine.fileFilter.empty())
            return true;

        const std::string pathString = path.string();
        for (const Utf8& filter : cmdLine.fileFilter)
        {
            if (!pathString.contains(filter))
                return false;
        }

        return true;
    }

    void collectSwagFilesRec(const CommandLine& cmdLine, const fs::path& folder, std::vector<fs::path>& files)
    {
        std::error_code ec;
        for (fs::recursive_directory_iterator it(folder, fs::directory_options::skip_permission_denied, ec), end; it != end; it.increment(ec))
        {
            if (ec)
            {
                ec.clear();
                continue;
            }

            const fs::directory_entry& entry = *it;
            if (!entry.is_regular_file(ec))
            {
                ec.clear();
                continue;
            }

            const fs::path&   path = entry.path();
            const std::string ext  = path.extension().string();
            if (ext != ".swg" && ext != ".swgs")
                continue;
            if (!pathMatchesFilter(cmdLine, path))
                continue;

            files.push_back(path);
        }
    }

    void collectInputFiles(const CommandLine& cmdLine, std::vector<fs::path>& files)
    {
        std::vector<fs::path> collected;
        for (const fs::path& folder : cmdLine.directories)
        {
            collected.clear();
            collectSwagFilesRec(cmdLine, folder, collected);
            if (cmdLine.numCores == 1)
                std::ranges::sort(collected);
            files.insert(files.end(), collected.begin(), collected.end());
        }

        collected.clear();
        for (const fs::path& file : cmdLine.files)
        {
            if (!pathMatchesFilter(cmdLine, file))
                continue;
            collected.push_back(file);
        }

        if (cmdLine.numCores == 1)
            std::ranges::sort(collected);
        files.insert(files.end(), collected.begin(), collected.end());
    }

    void replaceCrLf(std::string& content)
    {
        std::erase(content, '\r');
    }

    bool containsVerifyOption(std::string_view content, std::string_view option)
    {
        return content.contains(std::string(VERIFY_OPTION_PREFIX_A) + std::string(option)) ||
               content.contains(std::string(VERIFY_OPTION_PREFIX_B) + std::string(option));
    }

    SourceSuiteClassification classifySourceFile(const fs::path& path)
    {
        std::ifstream file(path, std::ios::binary | std::ios::ate);
        if (!file)
            return {};

        const std::streamsize fileSize = file.tellg();
        if (fileSize <= 0)
            return {};

        std::string content;
        content.resize(static_cast<size_t>(fileSize));
        file.seekg(0, std::ios::beg);
        if (!file.read(content.data(), fileSize))
            return {};

        replaceCrLf(content);

        if (containsVerifyOption(content, VERIFY_SUITE_SYNTAX))
            return {.kind = TestSuiteKind::Syntax, .hasSource = true};
        if (containsVerifyOption(content, VERIFY_SUITE_SEMA))
            return {.kind = TestSuiteKind::Sema, .hasSource = true};
        if (containsVerifyOption(content, VERIFY_SUITE_TEST))
            return {.kind = TestSuiteKind::Test, .hasSource = true};
        if (containsVerifyOption(content, VERIFY_LEX_ONLY))
            return {.kind = TestSuiteKind::Syntax, .hasSource = true};
        if (content.contains(EXPECTED_PARSER_ID) || content.contains(EXPECTED_LEX_ID))
            return {.kind = TestSuiteKind::Syntax, .hasSource = true};
        if (content.contains("#run") || content.contains(EXPECTED_SEMA_ID))
            return {.kind = TestSuiteKind::Sema, .hasSource = true};

        return {};
    }

    SourceSuiteBuckets bucketStandaloneSourceSuites(const std::vector<fs::path>& inputFiles)
    {
        SourceSuiteBuckets result;
        result.semaFiles.reserve(inputFiles.size());

        for (const fs::path& path : inputFiles)
        {
            const SourceSuiteClassification classification = classifySourceFile(path);
            result.hasSourceHints |= classification.hasSource;

            switch (classification.kind)
            {
                case TestSuiteKind::Syntax:
                    result.syntaxFiles.push_back(path);
                    break;
                case TestSuiteKind::Test:
                    result.testFiles.push_back(path);
                    break;
                case TestSuiteKind::Sema:
                case TestSuiteKind::Unknown:
                    result.semaFiles.push_back(path);
                    break;
            }
        }

        return result;
    }

    bool usesAllBackendKinds(const CommandLine& cmdLine)
    {
        return cmdLine.backendKindName == BACKEND_KIND_ALL;
    }

    bool hasNewErrors(const uint64_t errorsBefore)
    {
        return Stats::get().numErrors.load(std::memory_order_relaxed) != errorsBefore;
    }

    void runNativeTestCommand(CompilerInstance& compiler);

    bool runCompilerSubset(const CompilerInstance& compiler, CommandKind command, const std::vector<fs::path>& files, std::string_view backendKindName = {}, const bool clearOutputs = true)
    {
        if (files.empty())
            return true;

        CommandLine cmdLine = compiler.cmdLine();
        cmdLine.command     = command;
        cmdLine.directories.clear();
        cmdLine.files.clear();
        cmdLine.modulePath.clear();
        cmdLine.files.insert(files.begin(), files.end());
        cmdLine.clear = cmdLine.clear && clearOutputs;
        if (!backendKindName.empty())
            cmdLine.backendKindName = backendKindName;
        if (command == CommandKind::Syntax)
            cmdLine.runtime = false;

        CommandLineParser::refreshBuildCfg(cmdLine);

        const uint64_t   errorsBefore = Stats::get().numErrors.load(std::memory_order_relaxed);
        CompilerInstance subCompiler(compiler.global(), cmdLine);

        switch (command)
        {
            case CommandKind::Syntax:
                Command::syntax(subCompiler);
                break;
            case CommandKind::Sema:
                Command::sema(subCompiler);
                break;
            case CommandKind::Test:
                Command::test(subCompiler);
                break;
            default:
                SWC_UNREACHABLE();
        }

        return !hasNewErrors(errorsBefore);
    }

    bool runLegacyTestBackend(const CompilerInstance& compiler, std::string_view backendKind, const bool clearOutputs)
    {
        CommandLine cmdLine     = compiler.cmdLine();
        cmdLine.backendKindName = backendKind;
        cmdLine.clear           = cmdLine.clear && clearOutputs;
        CommandLineParser::refreshBuildCfg(cmdLine);

        const uint64_t   errorsBefore = Stats::get().numErrors.load(std::memory_order_relaxed);
        CompilerInstance subCompiler(compiler.global(), cmdLine);
        runNativeTestCommand(subCompiler);
        return !hasNewErrors(errorsBefore);
    }

    Result prepareJitFunction(TaskContext& ctx, SymbolFunction& symbol)
    {
        ctx.state().jitEmissionError = false;
        SWC_RESULT_VERIFY(symbol.emit(ctx));
        if (ctx.state().jitEmissionError)
            return Result::Error;

        symbol.jit(ctx);
        if (ctx.state().jitEmissionError || !symbol.jitEntryAddress())
            return Result::Error;

        return Result::Continue;
    }

    Result runJitFunction(TaskContext& ctx, SymbolFunction& symbol)
    {
        SWC_RESULT_VERIFY(prepareJitFunction(ctx, symbol));

        JITExecManager::Request request;
        request.function     = &symbol;
        request.nodeRef      = symbol.declNodeRef();
        request.codeRef      = symbol.codeRef();
        request.runImmediate = true;
        return ctx.compiler().jitExecMgr().submit(ctx, request);
    }

    Result runJitFunctions(TaskContext& ctx, const std::vector<SymbolFunction*>& functions)
    {
        for (SymbolFunction* symbol : functions)
        {
            if (!symbol)
                continue;
            SWC_RESULT_VERIFY(runJitFunction(ctx, *symbol));
        }

        return Result::Continue;
    }

    Result runCollectedJitTests(TaskContext& ctx)
    {
        const CompilerInstance& compiler = ctx.compiler();
        SWC_RESULT_VERIFY(runJitFunctions(ctx, compiler.nativeInitFunctions()));
        SWC_RESULT_VERIFY(runJitFunctions(ctx, compiler.nativePreMainFunctions()));
        SWC_RESULT_VERIFY(runJitFunctions(ctx, compiler.nativeTestFunctions()));
        SWC_RESULT_VERIFY(runJitFunctions(ctx, compiler.nativeDropFunctions()));
        return Result::Continue;
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

    void runNativeTestCommand(CompilerInstance& compiler)
    {
        Command::sema(compiler);
        if (Stats::get().numErrors.load(std::memory_order_relaxed) != 0)
            return;

        const bool           runArtifact = compiler.buildCfg().backendKind == Runtime::BuildCfgBackendKind::Executable;
        NativeBackendBuilder builder(compiler, runArtifact);
        if (builder.run() != Result::Continue)
            return;
        if (Stats::get().numErrors.load(std::memory_order_relaxed) != 0)
            return;

        if (runCollectedJitTests(builder.ctx()) != Result::Continue)
            return;

        verifyExpectedMarkers(builder.ctx());
    }

    bool runFullTestBackends(CompilerInstance& compiler, const std::vector<fs::path>* files = nullptr)
    {
        if (!usesAllBackendKinds(compiler.cmdLine()))
        {
            if (files)
                return runCompilerSubset(compiler, CommandKind::Test, *files, compiler.cmdLine().backendKindName);

            runNativeTestCommand(compiler);
            return Stats::get().numErrors.load(std::memory_order_relaxed) == 0;
        }

        bool clearOutputs = compiler.cmdLine().clear;
        for (const std::string_view backendKind : {std::string_view("exe"), std::string_view("dll"), std::string_view("lib")})
        {
            const bool ok = files
                                ? runCompilerSubset(compiler, CommandKind::Test, *files, backendKind, clearOutputs)
                                : runLegacyTestBackend(compiler, backendKind, clearOutputs);
            if (!ok)
                return false;
            clearOutputs = false;
        }

        return true;
    }

    bool runStandaloneSourceDrivenSuites(CompilerInstance& compiler)
    {
        const CommandLine& cmdLine = compiler.cmdLine();
        if (!cmdLine.modulePath.empty())
            return false;
        if (cmdLine.directories.empty() && cmdLine.files.empty())
            return false;

        std::vector<fs::path> inputFiles;
        collectInputFiles(cmdLine, inputFiles);
        if (inputFiles.empty())
            return false;

        const SourceSuiteBuckets buckets = bucketStandaloneSourceSuites(inputFiles);
        if (!buckets.hasSourceHints)
            return false;
        if (buckets.syntaxFiles.empty() && buckets.semaFiles.empty())
            return false;

        if (!runCompilerSubset(compiler, CommandKind::Syntax, buckets.syntaxFiles))
            return true;
        if (!runCompilerSubset(compiler, CommandKind::Sema, buckets.semaFiles))
            return true;

        runFullTestBackends(compiler, &buckets.testFiles);
        return true;
    }
}

namespace Command
{
    void test(CompilerInstance& compiler)
    {
        if (runStandaloneSourceDrivenSuites(compiler))
            return;

        if (usesAllBackendKinds(compiler.cmdLine()))
        {
            runFullTestBackends(compiler);
            return;
        }

        runNativeTestCommand(compiler);
    }
}

SWC_END_NAMESPACE();
