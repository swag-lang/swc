#include "pch.h"
#include "Main/CompilerInstance.h"
#include "Core/Timer.h"
#include "Main/CommandLine.h"
#include "Main/Context.h"
#include "Main/Global.h"
#include "Report/Stats.h"
#include "Thread/JobManager.h"

SWC_BEGIN_NAMESPACE();

CompilerInstance::CompilerInstance(const CommandLine& cmdLine, const Global& global) :
    context_(cmdLine, global)
{
    context_.jobClientId_ = global.jobMgr().newClientId();
}

int CompilerInstance::run()
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

    if (context_.cmdLine().stats)
    {
        const Context ctx(context_);
        Stats::get().print(ctx);
    }

    return 0;
}

SWC_END_NAMESPACE();
