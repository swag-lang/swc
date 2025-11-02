#include "pch.h"
#include "Main/CompilerInstance.h"
#include "Core/Timer.h"
#include "Core/Utf8Helper.h"
#include "Main/CommandLine.h"
#include "Main/Context.h"
#include "Main/Global.h"
#include "Report/LogColor.h"
#include "Report/Logger.h"
#include "Report/Stats.h"
#include "Thread/JobManager.h"

SWC_BEGIN_NAMESPACE()

CompilerInstance::CompilerInstance(const CommandLine& cmdLine, const Global& global) :
    context_(cmdLine, global)
{
    context_.jobClientId_ = global.jobMgr().newClientId();
}

ExitCode CompilerInstance::run()
{
    {
        Timer time(&Stats::get().timeTotal);
        switch (context_.cmdLine().command)
        {
        case Command::Syntax:
            cmdSyntax();
            break;
        case Command::Format:
            break;
        case Command::Invalid:
            break;
        }
    }

    const Context ctx(context_);

    // End message
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

    // Stats
    if (context_.cmdLine().stats)
        Stats::get().print(ctx);

    return ExitCode::Success;
}

SWC_END_NAMESPACE()
