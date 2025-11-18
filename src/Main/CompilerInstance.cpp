#include "pch.h"
#include "Main/CompilerInstance.h"
#include "Core/Timer.h"
#include "Core/Utf8Helper.h"
#include "FileSystem.h"
#include "Main/Command.h"
#include "Main/CommandLine.h"
#include "Main/Global.h"
#include "Main/Stats.h"
#include "Main/TaskContext.h"
#include "Os/Os.h"
#include "Report/Diagnostic.h"
#include "Report/LogColor.h"
#include "Report/Logger.h"
#include "Thread/JobManager.h"
#include "Wmf/SourceFile.h"

SWC_BEGIN_NAMESPACE()

CompilerInstance::~CompilerInstance() = default;

CompilerInstance::CompilerInstance(const Global& global, const CommandLine& cmdLine) :
    cmdLine_(&cmdLine),
    global_(&global),
    jobClientId_(global.jobMgr().newClientId()),
    exeFullName_{Os::getExeFullName()}
{
}

void CompilerInstance::logBefore()
{
    const TaskContext ctx(*this);

    ctx.global().logger().lock();

#if SWC_DEBUG
    Logger::printHeaderCentered(ctx, LogColor::Magenta, "[Debug]", LogColor::Magenta, "ON");
#elif SWC_DEV_MODE
    Logger::printHeaderCentered(ctx, LogColor::Blue, "[DevMode]", LogColor::Blue, "ON");
    if (ctx.cmdLine().randomize)
        Logger::printHeaderCentered(ctx, LogColor::Blue, "[DevMode]", LogColor::Blue, std::format("randomize seed is {}", ctx.global().jobMgr().randSeed()));
#elif SWC_STATS
    Logger::printHeaderCentered(ctx, LogColor::Yellow, "[Stats]", LogColor::Yellow, "ON");
#endif

    ctx.global().logger().unlock();
}

void CompilerInstance::logAfter()
{
    const TaskContext ctx(*this);

    const auto timeSrc = Utf8Helper::toNiceTime(Timer::toSeconds(Stats::get().timeTotal));
    ctx.global().logger().lock();
    if (Stats::get().numErrors.load() == 1)
        Logger::printHeaderCentered(ctx, LogColor::Green, "Done", LogColor::BrightRed, "1 error");
    else if (Stats::get().numErrors.load() > 1)
        Logger::printHeaderCentered(ctx, LogColor::Green, "Done", LogColor::BrightRed, std::format("{} errors", Stats::get().numErrors.load()));
    else if (Stats::get().numWarnings.load() == 1)
        Logger::printHeaderCentered(ctx, LogColor::Green, "Done", LogColor::Magenta, std::format("{} (1 warning)", timeSrc));
    else if (Stats::get().numWarnings.load() > 1)
        Logger::printHeaderCentered(ctx, LogColor::Green, "Done", LogColor::Magenta, std::format("{} ({} warnings)", timeSrc, Stats::get().numWarnings.load()));
    else
        Logger::printHeaderCentered(ctx, LogColor::Green, "Done", LogColor::White, timeSrc);
    ctx.global().logger().unlock();
}

void CompilerInstance::logStats()
{
    if (cmdLine().stats)
    {
        const TaskContext ctx(*this);
        Stats::get().print(ctx);
    }
}

void CompilerInstance::processCommand()
{
    Timer time(&Stats::get().timeTotal);
    switch (cmdLine().command)
    {
        case CommandKind::Syntax:
            Command::syntax(*this);
            break;
        case CommandKind::Format:
            Command::format(*this);
            break;
        case CommandKind::Build:
            Command::build(*this);
            break;
        default:
            SWC_UNREACHABLE();
    }
}

ExitCode CompilerInstance::run()
{
    logBefore();
    processCommand();
    logAfter();
    logStats();
    return ExitCode::Success;
}

FileRef CompilerInstance::addFile(fs::path path, FileFlags flags)
{
    path               = fs::absolute(path);
    const auto fileRef = static_cast<FileRef>(static_cast<uint32_t>(files_.size()));
    files_.emplace_back(std::make_unique<SourceFile>(std::move(path), flags));
    return fileRef;
}

std::vector<SourceFile*> CompilerInstance::files() const
{
    std::vector<SourceFile*> result;
    result.reserve(files_.size());
    for (const auto& f : files_)
        result.push_back(f.get());
    return result;
}

Result CompilerInstance::collectFiles(const TaskContext& ctx)
{
    const auto&           cmdLine = ctx.cmdLine();
    std::vector<fs::path> paths;

    // Collect direct folders from the command line
    paths.clear();
    for (const auto& folder : cmdLine.directories)
    {
        FileSystem::collectSwagFilesRec(ctx, folder, paths);
        if (cmdLine.numCores == 1)
            std::ranges::sort(paths);
        for (const auto& f : paths)
            addFile(f, FileFlagsE::CustomSrc);
    }

    // Collect direct files from the command line
    paths.clear();
    for (const auto& file : cmdLine.files)
        paths.push_back(file);
    if (cmdLine.numCores == 1)
        std::ranges::sort(paths);
    for (const auto& f : paths)
        addFile(f, FileFlagsE::CustomSrc);

    // Collect files for the module
    if (!cmdLine.modulePath.empty())
    {
        modulePathFile_ = cmdLine.modulePath;
        modulePathFile_.append("module.swg");
        if (FileSystem::resolveFile(ctx, modulePathFile_) != Result::Success)
            return Result::Error;
        addFile(modulePathFile_, FileFlagsE::Module);

        modulePathSrc_ = cmdLine.modulePath;
        modulePathSrc_.append("src");
        if (FileSystem::resolveFolder(ctx, modulePathSrc_) != Result::Success)
            return Result::Error;
        FileSystem::collectSwagFilesRec(ctx, modulePathSrc_, paths);
        if (cmdLine.numCores == 1)
            std::ranges::sort(paths);
        for (const auto& f : paths)
            addFile(f, FileFlagsE::ModuleSrc);
    }

    // Collect runtime files
    if (cmdLine.command == CommandKind::Build)
    {
        fs::path runtimePath = exeFullName_.parent_path() / "Runtime";
        if (FileSystem::resolveFolder(ctx, runtimePath) != Result::Success)
            return Result::Error;
        FileSystem::collectSwagFilesRec(ctx, modulePathSrc_, paths);
        if (cmdLine.numCores == 1)
            std::ranges::sort(paths);
        for (const auto& f : paths)
            addFile(f, FileFlagsE::Runtime);
    }

    if (files_.empty())
    {
        const auto diag = Diagnostic::get(DiagnosticId::cmd_err_no_input);
        diag.report(ctx);
        return Result::Error;
    }

    return Result::Success;
}

SWC_END_NAMESPACE()
