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
    class LoggerShellTestDirectory
    {
    public:
        LoggerShellTestDirectory()
        {
            path_ = (Os::getTemporaryPath() / "swc_unittest" / "logger" / std::format("batch_p{}", Os::currentProcessId())).lexically_normal();
            std::error_code ec;
            fs::remove_all(path_, ec);
            fs::create_directories(path_, ec);
        }

        ~LoggerShellTestDirectory()
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
    std::vector<Utf8> parts;
    ScopedTimedLog::appendTestStats(parts, 10, 0);
    if (ScopedTimedLog::joinStatItems(parts) != "10 passed")
        return Result::Error;

    parts.clear();
    ScopedTimedLog::appendTestStats(parts, 10, 2);
    if (ScopedTimedLog::joinStatItems(parts) != "8 passed, 2 did not pass")
        return Result::Error;
}
SWC_TEST_END()

SWC_TEST_BEGIN(Logger_CommandHelpIsPlainAsciiLines)
{
    std::string           output;
    Os::ProcessRunOptions options;
    options.capturedOutput = &output;
    options.forwardOutput  = false;

    uint32_t                exitCode = UINT32_MAX;
    const std::vector<Utf8> args     = {"help", "build"};
    if (Os::runProcess(exitCode, Os::getExeFullName(), args, Os::getTemporaryPath(), &options) != Os::ProcessRunResult::Ok || exitCode != 0)
        return Result::Error;

    // Help is read by programs: no escape sequence, no glyph outside ASCII, and an option keeps
    // its description on its own line.
    for (const char ch : output)
    {
        if (ch == '\x1b' || static_cast<unsigned char>(ch) >= 0x80)
            return Result::Error;
    }

    bool foundOption = false;
    for (const auto& line : Utf8Helper::splitLines(output))
    {
        if (line.find("--config-file") != Utf8::npos && line.find("Read command-line options from a config file") != Utf8::npos)
            foundOption = true;
    }
    if (!foundOption)
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

SWC_FILESYSTEM_TEST_BEGIN(Logger_ShellRedirectionKeepsPlainOutputAndExitCode)
{
    LoggerShellTestDirectory testDir;
    const fs::path           sourcePath = testDir.path() / "main.swg";
    const fs::path           logPath    = testDir.path() / "build.log";

    SWC_RESULT(writeText(sourcePath, "#main\n{\n}\n"));
#ifdef _WIN32
    const fs::path batchPath = testDir.path() / "compile.bat";
    const Utf8     batch     = std::format("@echo off\r\n\"{}\" syntax --num-cores 3 -f \"{}\" > \"{}\" 2>&1\r\nexit /b %errorlevel%\r\n", Os::getExeFullName().string(), sourcePath.string(), logPath.string());
    SWC_RESULT(writeText(batchPath, batch));

    const std::optional<Utf8> commandInterpreter = Os::readEnvironmentVariable("ComSpec");
    if (!commandInterpreter)
        return Result::Error;

    const fs::path          interpreter{commandInterpreter->c_str()};
    const std::vector<Utf8> args = {"/d", "/c", Utf8(batchPath.string())};
#else
    const fs::path interpreter = "/bin/sh";
    // Paths are positional arguments, so spaces and shell metacharacters stay literal.
    const std::vector<Utf8> args = {"-c", R"("$1" syntax --num-cores 3 -f "$2" > "$3" 2>&1)", "swc-logger-test", Utf8(Os::getExeFullName()), Utf8(sourcePath), Utf8(logPath)};
#endif
    uint32_t                   exitCode  = 0;
    const Os::ProcessRunResult runResult = Os::runProcess(exitCode, interpreter, args, testDir.path());

    std::string             output;
    FileSystem::IoErrorInfo error;
    if (FileSystem::readTextFile(logPath, output, error) != Result::Continue)
    {
        Logger::print(ctx, std::format("[logger-test] shell result={} exit={} log file was not created\n", static_cast<uint32_t>(runResult), exitCode));
        return Result::Error;
    }
    if (runResult != Os::ProcessRunResult::Ok || exitCode != 0)
    {
        Logger::print(ctx, std::format("[logger-test] shell result={} exit={}\n{}", static_cast<uint32_t>(runResult), exitCode, output));
        return Result::Error;
    }
    if (output.find('\x1b') != std::string::npos)
        return Result::Error;
    for (size_t i = 0; i < output.size(); ++i)
    {
        if (output[i] == '\r' && (i + 1 == output.size() || output[i + 1] != '\n'))
            return Result::Error;
    }

    // A plain line still needs its stage and outcome: consumers distinguish successful work
    // from errors and cached results without interpreting presentation labels.
    bool foundSyntax = false;
    Utf8 lastRecord;
    for (const auto& line : Utf8Helper::splitLines(output))
    {
        if (line.empty())
            continue;
        if (line.starts_with("syntax ok: "))
            foundSyntax = true;
        lastRecord = line;
    }
    if (!foundSyntax || !lastRecord.starts_with("command ok: syntax main.swg, "))
        return Result::Error;
}
SWC_TEST_END()

SWC_END_NAMESPACE();

#endif
