#include "pch.h"

#if SWC_HAS_UNITTEST

#include "Main/Command/CommandLine.h"
#include "Main/Command/CommandLineParser.h"
#include "Main/CompilerInstance.h"
#include "Main/FileSystem.h"
#include "Support/Os/Os.h"
#include "Unittest/Unittest.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    class FormatCommandTestDirectory
    {
    public:
        explicit FormatCommandTestDirectory(const std::string_view testName)
        {
            path_ = (Os::getTemporaryPath() / "swc_unittest" / "format" / std::format("{}_p{}", testName, Os::currentProcessId())).lexically_normal();
            std::error_code ec;
            fs::remove_all(path_, ec);
        }

        ~FormatCommandTestDirectory()
        {
            std::error_code ec;
            fs::remove_all(path_, ec);
        }

        const fs::path& path() const { return path_; }

    private:
        fs::path path_;
    };

    Result writeText(const fs::path& path, const std::string_view text)
    {
        std::error_code ec;
        fs::create_directories(path.parent_path(), ec);
        if (ec)
            return Result::Error;

        FileSystem::IoErrorInfo error;
        return FileSystem::writeBinaryFile(path, text.data(), text.size(), error);
    }

    Result readText(std::string& result, const fs::path& path)
    {
        FileSystem::IoErrorInfo error;
        return FileSystem::readTextFile(path, result, error);
    }

    Result runFormat(TaskContext& ctx, CommandLine& cmdLine)
    {
        cmdLine.command  = CommandKind::Format;
        cmdLine.numCores = 1;
        cmdLine.silent   = true;
        CommandLineParser::refreshBuildCfg(cmdLine);

        CompilerInstance compiler(ctx.global(), cmdLine);
        return compiler.run() == ExitCode::Success ? Result::Continue : Result::Error;
    }
}

SWC_FILESYSTEM_TEST_BEGIN(Compiler_FormatCommandHonorsExplicitDotPaths)
{
    static constexpr std::string_view SOURCE   = "func main()\n{\n      let value=1\n}\n";
    static constexpr std::string_view EXPECTED = "func main()\n{\n    let value = 1\n}\n";

    FormatCommandTestDirectory testDir("HonorsExplicitDotPaths");

    const fs::path explicitFile = testDir.path() / ".explicit" / "input.swg";
    SWC_RESULT(writeText(explicitFile, SOURCE));

    CommandLine fileCommand;
    fileCommand.files.insert(explicitFile);
    SWC_RESULT(runFormat(ctx, fileCommand));

    std::string formatted;
    SWC_RESULT(readText(formatted, explicitFile));
    if (formatted != EXPECTED)
        return Result::Error;

    const fs::path worktreeFile = testDir.path() / ".worktree" / "src" / "input.swg";
    const fs::path cacheFile    = testDir.path() / ".worktree" / ".output" / "cached.swg";
    SWC_RESULT(writeText(worktreeFile, SOURCE));
    SWC_RESULT(writeText(cacheFile, SOURCE));

    CommandLine directoryCommand;
    directoryCommand.directories.insert(testDir.path() / ".worktree");
    SWC_RESULT(runFormat(ctx, directoryCommand));

    SWC_RESULT(readText(formatted, worktreeFile));
    if (formatted != EXPECTED)
        return Result::Error;

    SWC_RESULT(readText(formatted, cacheFile));
    if (formatted != SOURCE)
        return Result::Error;
}
SWC_TEST_END()

SWC_END_NAMESPACE();

#endif
