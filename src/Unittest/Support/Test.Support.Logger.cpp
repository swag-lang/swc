#include "pch.h"

#if SWC_HAS_UNITTEST

#include "Main/Command/CommandLine.h"
#include "Main/Command/CommandLineParser.h"
#include "Main/FileSystem.h"
#include "Main/Global.h"
#include "Main/TaskContext.h"
#include "Support/Os/Os.h"
#include "Support/Report/Logger.h"
#include "Support/Report/ScopedTimedLog.h"
#include "Unittest/Unittest.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    class LoggerBatchTestDirectory
    {
    public:
        LoggerBatchTestDirectory()
        {
            path_ = (Os::getTemporaryPath() / "swc_unittest" / "logger" / std::format("batch_p{}", Os::currentProcessId())).lexically_normal();
            std::error_code ec;
            fs::remove_all(path_, ec);
            fs::create_directories(path_, ec);
        }

        ~LoggerBatchTestDirectory()
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
        FileSystem::IoErrorInfo error;
        return FileSystem::writeBinaryFile(path, text.data(), text.size(), error);
    }
}

SWC_TEST_BEGIN(Logger_TestTalliesNameSuccessfulWork)
{
    CommandLine cmdLine;
    cmdLine.logAscii = true;
    cmdLine.logColor = false;
    TaskContext testCtx(ctx.global(), cmdLine);

    std::vector<Utf8> parts;
    ScopedTimedLog::appendTestStats(testCtx, parts, 10, 0);
    if (ScopedTimedLog::joinStatItems(testCtx, parts) != "10 passed")
        return Result::Error;

    parts.clear();
    ScopedTimedLog::appendTestStats(testCtx, parts, 10, 2);
    if (ScopedTimedLog::joinStatItems(testCtx, parts) != "8 passed * 2 did not pass")
        return Result::Error;

    if (ScopedTimedLog::formatTestProgress(testCtx, 8, 10, 2, "Core.Map") != "6/10 passed * 2 did not pass * Core.Map")
        return Result::Error;
}
SWC_TEST_END()

SWC_TEST_BEGIN(Logger_NestedStagesDetailedChoiceDoesNotLeak)
{
    Logger&    logger = ctx.global().logger();
    const bool saved  = logger.stagesDetailed();

    logger.setStagesDetailed(true);
    {
        const Logger::ScopedStagesDetailed nested(logger, false);
        if (logger.stagesDetailed())
        {
            logger.setStagesDetailed(saved);
            return Result::Error;
        }
    }

    const bool restored = logger.stagesDetailed();
    logger.setStagesDetailed(saved);
    if (!restored)
        return Result::Error;
}
SWC_TEST_END()

SWC_TEST_BEGIN(Logger_ProgressCanBeDisabledFromCommandLine)
{
    CommandLine cmdLine;
    char        arg0[] = "swc.dm";
    char        arg1[] = "syntax";
    char        arg2[] = "--no-log-progress";
    char*       argv[] = {arg0, arg1, arg2};

    CommandLineParser parser(const_cast<Global&>(ctx.global()), cmdLine);
    if (parser.parse(std::size(argv), argv) != Result::Continue)
        return Result::Error;
    if (cmdLine.logProgress)
        return Result::Error;
}
SWC_TEST_END()

SWC_FILESYSTEM_TEST_BEGIN(Logger_BatchRedirectionKeepsPlainOutputAndExitCode)
{
    LoggerBatchTestDirectory testDir;
    const fs::path           sourcePath = testDir.path() / "main.swg";
    const fs::path           logPath    = testDir.path() / "build.log";
    const fs::path           batchPath  = testDir.path() / "compile.bat";

    SWC_RESULT(writeText(sourcePath, "#main\n{\n}\n"));
    const Utf8 batch = std::format("@echo off\r\n\"{}\" syntax -f \"{}\" > \"{}\" 2>&1\r\nexit /b %errorlevel%\r\n", Os::getExeFullName().string(), sourcePath.string(), logPath.string());
    SWC_RESULT(writeText(batchPath, batch));

    const std::optional<Utf8> commandInterpreter = Os::readEnvironmentVariable("ComSpec");
    if (!commandInterpreter)
        return Result::Error;

    uint32_t                   exitCode  = 0;
    const std::vector<Utf8>    args      = {"/d", "/c", Utf8(batchPath.string())};
    const Os::ProcessRunResult runResult = Os::runProcess(exitCode, fs::path{commandInterpreter->c_str()}, args, testDir.path());

    std::string             output;
    FileSystem::IoErrorInfo error;
    if (FileSystem::readTextFile(logPath, output, error) != Result::Continue)
    {
        Logger::print(ctx, std::format("[logger-test] batch result={} exit={} log file was not created\n", static_cast<uint32_t>(runResult), exitCode));
        return Result::Error;
    }
    if (runResult != Os::ProcessRunResult::Ok || exitCode != 0)
    {
        Logger::print(ctx, std::format("[logger-test] batch result={} exit={}\n{}", static_cast<uint32_t>(runResult), exitCode, output));
        return Result::Error;
    }
    if (output.find('\x1b') != std::string::npos)
        return Result::Error;
    for (size_t i = 0; i < output.size(); ++i)
    {
        if (output[i] == '\r' && (i + 1 == output.size() || output[i + 1] != '\n'))
            return Result::Error;
    }
}
SWC_TEST_END()

SWC_END_NAMESPACE();

#endif
