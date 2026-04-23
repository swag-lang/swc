#include "pch.h"
#include "Main/Global.h"
#include "Backend/ABI/CallConv.h"
#include "Compiler/Lexer/LangSpec.h"
#include "Main/Command/CommandLine.h"
#include "Main/Stats.h"
#include "Support/Memory/MemoryProfile.h"
#include "Support/Os/Os.h"
#include "Support/Report/Logger.h"
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
    Stats::setEnabled(cmdLine.stats);
    MemoryProfile::setTrackingEnabled(cmdLine.statsMem);
    MemoryProfile::setDetailedTrackingEnabled(cmdLine.statsMem);
    Os::initialize();
    CallConv::setup();
    langSpec_->setup();
    jobManager_->setup(cmdLine);
}

SWC_END_NAMESPACE();
