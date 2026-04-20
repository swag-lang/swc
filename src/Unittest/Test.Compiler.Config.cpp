#include "pch.h"

#if SWC_HAS_UNITTEST

#include "Compiler/Parser/Parser/ParserJob.h"
#include "Format/FormatOptionsLoader.h"
#include "Format/Formatter.h"
#include "Main/Command/CommandLine.h"
#include "Main/Command/CommandLineParser.h"
#include "Main/CompilerInstance.h"
#include "Main/FileSystem.h"
#include "Main/Stats.h"
#include "Support/Core/Utf8Helper.h"
#include "Support/Os/Os.h"
#include "Support/Report/ScopedTimedAction.h"
#include "Unittest/Unittest.h"
#include "Unittest/UnittestSource.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    class ScopedTempTree
    {
    public:
        explicit ScopedTempTree(std::string_view name)
        {
            const fs::path tempRoot = Os::getTemporaryPath();
            SWC_ASSERT(!tempRoot.empty());

            root_ = (tempRoot / "swc_unittest" / name).lexically_normal();

            std::error_code ec;
            fs::remove_all(root_, ec);
            ec.clear();
            const bool created = fs::create_directories(root_, ec);
            if (!ec && (created || fs::exists(root_)))
                ready_ = true;
        }

        ~ScopedTempTree()
        {
            std::error_code ec;
            fs::remove_all(root_, ec);
        }

        bool            ready() const { return ready_; }
        const fs::path& root() const { return root_; }

    private:
        fs::path root_;
        bool     ready_ = false;
    };

    bool ensureDirectory(const fs::path& path)
    {
        std::error_code ec;
        if (fs::exists(path, ec))
            return !ec && fs::is_directory(path, ec);

        ec.clear();
        return fs::create_directories(path, ec) && !ec;
    }

    bool writeTextFile(const fs::path& path, std::string_view content)
    {
        const fs::path parentPath = path.parent_path();
        if (!parentPath.empty() && !ensureDirectory(parentPath))
            return false;

        std::ofstream stream(path, std::ios::binary | std::ios::trunc);
        if (!stream.is_open())
            return false;

        stream.write(content.data(), static_cast<std::streamsize>(content.size()));
        return stream.good();
    }

    bool containsPath(const std::set<fs::path>& paths, const fs::path& expectedPath)
    {
        for (const fs::path& path : paths)
        {
            if (FileSystem::pathEquals(path, expectedPath))
                return true;
        }

        return false;
    }

    Result parseCommandLine(const TaskContext& ctx, CommandLine& cmdLine, const std::vector<std::string>& args)
    {
        std::vector<char*> argv;
        argv.reserve(args.size());
        for (const std::string& arg : args)
            argv.push_back(const_cast<char*>(arg.c_str()));

        CommandLineParser parser(const_cast<Global&>(ctx.global()), cmdLine);
        return parser.parse(static_cast<int>(argv.size()), argv.data());
    }

    Result formatSourceText(const Global& global, std::string_view source, const FormatOptions& options, Utf8& outText)
    {
        CommandLine cmdLine;
        cmdLine.command = CommandKind::Format;
        cmdLine.name    = "compiler_format_options_apply";

        CompilerInstance compiler(global, cmdLine);
        TaskContext      compilerCtx(compiler);

        SourceFile& sourceFile = Unittest::addTestSource(compilerCtx, "Compiler", "FormatOptionsApply", source);
        SWC_RESULT(sourceFile.loadContent(compilerCtx));

        constexpr ParserJobOptions parserOptions = {
            .emitTrivia       = true,
            .ignoreGlobalSkip = true,
        };

        SWC_RESULT(parseLoadedSourceFile(compilerCtx, sourceFile, parserOptions));
        if (compilerCtx.hasError())
            return Result::Error;

        Formatter formatter(options);
        formatter.prepare(sourceFile);
        outText = formatter.text();
        return Result::Continue;
    }
}

SWC_TEST_BEGIN(Compiler_CommandLineConfigFileSetsCommandAndResolvesRelativePaths)
{
    const ScopedTempTree tempTree("compiler_config_file_sets_command");
    if (!tempTree.ready())
        return Result::Error;

    const fs::path configDir  = tempTree.root() / "cfg";
    const fs::path sourceFile = configDir / "inputs" / "main.swg";
    const fs::path sourceDir  = configDir / "suite";
    const fs::path moduleDir  = configDir / "module";
    const fs::path configPath = configDir / "swc.cfg";

    if (!writeTextFile(sourceFile, "func main() {}\n"))
        return Result::Error;
    if (!ensureDirectory(sourceDir))
        return Result::Error;
    if (!ensureDirectory(moduleDir))
        return Result::Error;
    if (!writeTextFile(configPath, R"(# A polished config file should accept comments and quoted values.
command = test
file = ./inputs/main.swg
directory = ./suite
module = ./module
artifact-name = "cfg#artifact" # hashes inside quotes are part of the value
runtime = off
tag = "User.Name: string = hello world"
out-dir = ./out
work-dir = ./work
)"))
        return Result::Error;

    CommandLine                    cmdLine;
    const uint64_t                 errorsBefore = Stats::getNumErrors();
    const std::vector<std::string> args         = {
        "swc_devmode",
        "--config-file",
        configPath.string(),
    };

    if (parseCommandLine(ctx, cmdLine, args) != Result::Continue)
        return Result::Error;
    if (Stats::getNumErrors() != errorsBefore)
        return Result::Error;
    if (cmdLine.command != CommandKind::Test)
        return Result::Error;
    if (!cmdLine.commandExplicit)
        return Result::Error;
    if (!cmdLine.sourceDrivenTest)
        return Result::Error;
    if (cmdLine.runtime)
        return Result::Error;
    if (cmdLine.name != "cfg#artifact")
        return Result::Error;
    if (cmdLine.tags.size() != 1 || cmdLine.tags[0] != "User.Name: string = hello world")
        return Result::Error;
    if (!FileSystem::pathEquals(cmdLine.configFile, configPath))
        return Result::Error;
    if (!containsPath(cmdLine.files, sourceFile))
        return Result::Error;
    if (!containsPath(cmdLine.directories, sourceDir))
        return Result::Error;
    if (!FileSystem::pathEquals(cmdLine.modulePath, moduleDir))
        return Result::Error;
    if (!FileSystem::pathEquals(cmdLine.outDir, configDir / "out"))
        return Result::Error;
    if (!FileSystem::pathEquals(cmdLine.workDir, configDir / "work"))
        return Result::Error;
}
SWC_TEST_END()

SWC_TEST_BEGIN(Compiler_CommandLineConfigFileAllowsCliOverrides)
{
    const ScopedTempTree tempTree("compiler_config_file_cli_override");
    if (!tempTree.ready())
        return Result::Error;

    const fs::path configPath = tempTree.root() / "swc.cfg";
    if (!writeTextFile(configPath, R"(command = test
runtime = off
artifact-kind = static-library
)"))
        return Result::Error;

    CommandLine                    cmdLine;
    const uint64_t                 errorsBefore = Stats::getNumErrors();
    const std::vector<std::string> args         = {
        "swc_devmode",
        "build",
        "--config-file",
        configPath.string(),
        "--runtime",
        "--artifact-kind",
        "executable",
    };

    if (parseCommandLine(ctx, cmdLine, args) != Result::Continue)
        return Result::Error;
    if (Stats::getNumErrors() != errorsBefore)
        return Result::Error;
    if (cmdLine.command != CommandKind::Build)
        return Result::Error;
    if (cmdLine.sourceDrivenTest)
        return Result::Error;
    if (!cmdLine.runtime)
        return Result::Error;
    if (cmdLine.backendKind != Runtime::BuildCfgBackendKind::Executable)
        return Result::Error;
    if (!cmdLine.artifactKindExplicit)
        return Result::Error;
}
SWC_TEST_END()

SWC_TEST_BEGIN(Compiler_FormatSummaryLineShowsWrittenFilesAfterTime)
{
    Stats::resetCommandMetrics();

    Stats& stats = Stats::get();
    stats.numFiles.store(3, std::memory_order_relaxed);
    stats.timeTotal.store(1'000'000'000, std::memory_order_relaxed);
    stats.numFormatRewrittenFiles.store(2, std::memory_order_relaxed);

    CommandLine cmdLine;
    cmdLine.command  = CommandKind::Format;
    cmdLine.logColor = false;

    const TaskContext                   formatCtx(ctx.global(), cmdLine);
    const TimedActionLog::StatsSnapshot snapshot        = TimedActionLog::StatsSnapshot::capture();
    const Utf8                          summaryLine     = TimedActionLog::formatSummaryLine(formatCtx, snapshot);
    const Utf8                          expectedTime    = Utf8Helper::toNiceTime(1.0);
    const Utf8                          expectedWritten = Utf8Helper::countWithLabel(2, "written file");
    const size_t                        landedPos       = summaryLine.find("Landed");
    const size_t                        timePos         = summaryLine.find(expectedTime);
    const size_t                        writtenPos      = summaryLine.find(expectedWritten);

    Stats::resetCommandMetrics();

    if (landedPos == Utf8::npos || timePos == Utf8::npos || writtenPos == Utf8::npos)
        return Result::Error;
    if (!(landedPos < timePos && timePos < writtenPos))
        return Result::Error;
}
SWC_TEST_END()

SWC_TEST_BEGIN(Compiler_FormatOptionsLoaderMergesHierarchy)
{
    const ScopedTempTree tempTree("compiler_format_options_loader");
    if (!tempTree.ready())
        return Result::Error;

    const fs::path rootConfig    = tempTree.root() / ".swc-format";
    const fs::path projectConfig = tempTree.root() / "project" / ".swc-format";
    const fs::path packageConfig = tempTree.root() / "project" / "pkg" / ".swc-format";
    const fs::path sourcePath    = tempTree.root() / "project" / "pkg" / "sub" / "main.swg";

    if (!writeTextFile(rootConfig, R"(# The temp root establishes a deterministic baseline.
preserve-bom = false
preserve-trailing-whitespace = true
insert-final-newline = false
indent-width = 3
indent-style = tabs
end-of-line-style = crlf
)"))
        return Result::Error;
    if (!writeTextFile(projectConfig, R"(insert-final-newline = true
indent-width = 2
)"))
        return Result::Error;
    if (!writeTextFile(packageConfig, R"(# More specific folders override only the settings they care about.
preserve-trailing-whitespace = false
indent-width = 6
indent-style = spaces
end-of-line-style = lf
)"))
        return Result::Error;
    if (!writeTextFile(sourcePath, "func main() {}\n"))
        return Result::Error;

    FormatOptions       formatOptions;
    const uint64_t      errorsBefore = Stats::getNumErrors();
    FormatOptionsLoader loader(ctx);
    if (loader.resolve(sourcePath, formatOptions) != Result::Continue)
        return Result::Error;
    if (Stats::getNumErrors() != errorsBefore)
        return Result::Error;

    if (formatOptions.preserveBom)
        return Result::Error;
    if (formatOptions.preserveTrailingWhitespace)
        return Result::Error;
    if (!formatOptions.insertFinalNewline)
        return Result::Error;
    if (formatOptions.indentWidth != 6)
        return Result::Error;
    if (formatOptions.indentStyle != FormatIndentStyle::Spaces)
        return Result::Error;
    if (formatOptions.endOfLineStyle != FormatEndOfLineStyle::Lf)
        return Result::Error;
}
SWC_TEST_END()

SWC_TEST_BEGIN(Compiler_FormatterAppliesFormatOptions)
{
    static constexpr std::string_view SOURCE = "\xEF\xBB\xBF"
                                               "func A() {\r\n\tlet a  = 1  \r\n\tlet b = 2\t \r\n}";

    FormatOptions formatOptions;
    formatOptions.preserveBom                = false;
    formatOptions.preserveTrailingWhitespace = false;
    formatOptions.insertFinalNewline         = true;
    formatOptions.indentWidth                = 2;
    formatOptions.indentStyle                = FormatIndentStyle::Spaces;
    formatOptions.endOfLineStyle             = FormatEndOfLineStyle::Lf;

    Utf8 formatted;
    SWC_RESULT(formatSourceText(ctx.global(), SOURCE, formatOptions, formatted));

    if (formatted != "func A() {\n  let a  = 1\n  let b = 2\n}\n")
        return Result::Error;
}
SWC_TEST_END()

SWC_TEST_BEGIN(Compiler_FormatterPreservesTriviaAndInfersFinalNewlineStyle)
{
    static constexpr std::string_view SOURCE = "\xEF\xBB\xBF"
                                               "func A() {\r\n\tlet a = 1  \r\n}";

    FormatOptions formatOptions;
    formatOptions.preserveBom                = true;
    formatOptions.preserveTrailingWhitespace = true;
    formatOptions.insertFinalNewline         = true;
    formatOptions.indentStyle                = FormatIndentStyle::Preserve;
    formatOptions.endOfLineStyle             = FormatEndOfLineStyle::Preserve;

    Utf8 formatted;
    SWC_RESULT(formatSourceText(ctx.global(), SOURCE, formatOptions, formatted));

    if (formatted != "\xEF\xBB\xBF"
                     "func A() {\r\n\tlet a = 1  \r\n}\r\n")
        return Result::Error;
}
SWC_TEST_END()

SWC_END_NAMESPACE();

#endif
