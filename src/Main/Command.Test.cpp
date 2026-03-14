#include "pch.h"
#include "Main/Command.h"
#include "Backend/Native/NativeBackendBuilder.h"
#include "Main/CommandLine.h"
#include "Main/CommandLineParser.h"
#include "Main/CompilerInstance.h"
#include "Main/Stats.h"
#include "Support/Core/Utf8Helper.h"
#include "Support/Report/ScopedTimedAction.h"
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
        Native,
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

    bool isRunCommand(const CommandKind command)
    {
        return command == CommandKind::Run;
    }

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

    void collectSwagFilesRec(std::vector<fs::path>& outFiles, const CommandLine& cmdLine, const fs::path& folder)
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

            outFiles.push_back(path);
        }
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

    bool classifySourceFile(TestSuiteKind& outKind, const fs::path& path)
    {
        outKind = TestSuiteKind::Unknown;

        std::ifstream file(path, std::ios::binary | std::ios::ate);
        if (!file)
            return false;

        const std::streamsize fileSize = file.tellg();
        if (fileSize <= 0)
            return false;

        std::string content;
        content.resize(static_cast<size_t>(fileSize));
        file.seekg(0, std::ios::beg);
        if (!file.read(content.data(), fileSize))
            return false;

        replaceCrLf(content);

        if (containsVerifyOption(content, VERIFY_SUITE_SYNTAX))
        {
            outKind = TestSuiteKind::Syntax;
            return true;
        }

        if (containsVerifyOption(content, VERIFY_SUITE_SEMA))
        {
            outKind = TestSuiteKind::Sema;
            return true;
        }

        if (containsVerifyOption(content, VERIFY_SUITE_TEST))
        {
            outKind = TestSuiteKind::Native;
            return true;
        }

        if (containsVerifyOption(content, VERIFY_LEX_ONLY))
        {
            outKind = TestSuiteKind::Syntax;
            return true;
        }

        if (content.contains(EXPECTED_PARSER_ID) || content.contains(EXPECTED_LEX_ID))
        {
            outKind = TestSuiteKind::Syntax;
            return true;
        }

        if (content.contains("#run") || content.contains(EXPECTED_SEMA_ID))
        {
            outKind = TestSuiteKind::Sema;
            return true;
        }

        return false;
    }

    void appendStandaloneSourceFile(SourceSuiteBuckets& outBuckets, const fs::path& path)
    {
        auto       kind           = TestSuiteKind::Unknown;
        const bool hasSourceHints = classifySourceFile(kind, path);
        outBuckets.hasSourceHints |= hasSourceHints;

        switch (kind)
        {
            case TestSuiteKind::Syntax:
                outBuckets.syntaxFiles.push_back(path);
                break;
            case TestSuiteKind::Native:
                outBuckets.testFiles.push_back(path);
                break;
            case TestSuiteKind::Sema:
            case TestSuiteKind::Unknown:
                outBuckets.semaFiles.push_back(path);
                break;
        }
    }

    void collectStandaloneSourceSuites(SourceSuiteBuckets& outBuckets, const CommandLine& cmdLine)
    {
        std::vector<fs::path> collected;

        for (const fs::path& folder : cmdLine.directories)
        {
            collected.clear();
            collectSwagFilesRec(collected, cmdLine, folder);
            std::ranges::sort(collected);

            for (const fs::path& path : collected)
                appendStandaloneSourceFile(outBuckets, path);
        }

        collected.clear();
        for (const fs::path& path : cmdLine.files)
        {
            if (!pathMatchesFilter(cmdLine, path))
                continue;
            collected.push_back(path);
        }

        std::ranges::sort(collected);

        for (const fs::path& path : collected)
            appendStandaloneSourceFile(outBuckets, path);
    }

    bool hasNewErrors(const uint64_t errorsBefore)
    {
        return Stats::get().numErrors.load(std::memory_order_relaxed) != errorsBefore;
    }

    Utf8 formatFileGroup(std::string_view name, const size_t fileCount)
    {
        return std::format("{} ({} {})",
                           name,
                           Utf8Helper::toNiceBigNumber(fileCount),
                           fileCount == 1 ? "file" : "files");
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

    bool runNativeBackends(CompilerInstance& compiler, const bool runArtifact)
    {
        const Runtime::BuildCfgBackendKind backendKind = compiler.buildCfg().backendKind;
        if (!runNativeBackend(compiler, backendKind, runArtifact && backendKind == Runtime::BuildCfgBackendKind::Executable))
            return false;

        TaskContext ctx(compiler);
        verifyExpectedMarkers(ctx);
        return Stats::get().numErrors.load(std::memory_order_relaxed) == 0;
    }

    bool runCompilerSubset(CompilerInstance& compiler, const CommandKind command, const std::vector<fs::path>& files, std::string_view backendKindName = {})
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
        if (command == CommandKind::Syntax)
            cmdLine.runtime = false;

        CommandLineParser::refreshBuildCfg(cmdLine);

        const uint64_t   errorsBefore = Stats::get().numErrors.load(std::memory_order_relaxed);
        CompilerInstance subCompiler(compiler.global(), cmdLine);

        switch (command)
        {
            case CommandKind::Syntax:
            {
                ScopedTimedAction parseAction(ctx, "Parse", formatFileGroup("syntax tests", files.size()));
                Command::syntax(subCompiler);
                finishAction(parseAction, errorsBefore);
                break;
            }

            case CommandKind::Sema:
            {
                ScopedTimedAction analyzeAction(ctx, "Analyze", formatFileGroup("semantic tests", files.size()));
                Command::sema(subCompiler);
                finishAction(analyzeAction, errorsBefore);
                break;
            }

            case CommandKind::Build:
            case CommandKind::Run:
            {
                ScopedTimedAction analyzeAction(ctx, "Analyze", formatFileGroup("native tests", files.size()));
                Command::sema(subCompiler);
                if (finishAction(analyzeAction, errorsBefore))
                    runNativeBackends(subCompiler, isRunCommand(command));
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
        SWC_ASSERT(cmdLine.test);

        if (!cmdLine.modulePath.empty())
            return false;
        if (cmdLine.directories.empty() && cmdLine.files.empty())
            return false;

        SourceSuiteBuckets buckets;
        const TaskContext  ctx(compiler);
        ScopedTimedAction  discoverAction(ctx, "Discover", "test suites");
        collectStandaloneSourceSuites(buckets, cmdLine);
        if (!buckets.hasSourceHints)
        {
            discoverAction.fail();
            return false;
        }

        if (buckets.syntaxFiles.empty() && buckets.semaFiles.empty() && buckets.testFiles.empty())
        {
            discoverAction.fail();
            return false;
        }

        discoverAction.success();

        if (!runCompilerSubset(compiler, CommandKind::Syntax, buckets.syntaxFiles))
            return true;
        if (!runCompilerSubset(compiler, CommandKind::Sema, buckets.semaFiles))
            return true;

        runCompilerSubset(compiler, compiler.cmdLine().command, buckets.testFiles, compiler.cmdLine().backendKindName);
        return true;
    }

    void runNativeTestCommand(CompilerInstance& compiler, const bool runArtifact)
    {
        if (runStandaloneSourceDrivenSuites(compiler))
            return;

        const TaskContext ctx(compiler);
        ScopedTimedAction analyzeAction(ctx, "Analyze", "sources");
        const uint64_t    errorsBefore = Stats::get().numErrors.load(std::memory_order_relaxed);
        Command::sema(compiler);
        if (!finishAction(analyzeAction, errorsBefore))
            return;

        runNativeBackends(compiler, runArtifact);
    }
}

namespace Command
{
    void test(CompilerInstance& compiler)
    {
        SWC_ASSERT(compiler.cmdLine().test);
        runNativeTestCommand(compiler, isRunCommand(compiler.cmdLine().command));
    }
}

SWC_END_NAMESPACE();
