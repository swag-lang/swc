#include "pch.h"
#include "Main/Global.h"
#include "Lexer/LangSpec.h"
#include "Support/Os/Os.h"
#include "Report/Logger.h"
#include "Support/Thread/JobManager.h"

SWC_BEGIN_NAMESPACE();

Global::Global()
{
    static Logger     logger;
    static LangSpec   langSpec;
    static JobManager jobManager;

    logger_     = &logger;
    langSpec_   = &langSpec;
    jobManager_ = &jobManager;
}

void Global::initialize(const CommandLine& cmdLine) const
{
    Os::initialize();
    langSpec_->setup();
    jobManager_->setup(cmdLine);
}

SWC_END_NAMESPACE();
