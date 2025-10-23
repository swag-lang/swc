#include "pch.h"

#include "Lexer/LangSpec.h"
#include "Main/CommandLine.h"
#include "Main/Global.h"
#include "Os/Os.h"
#include "Report/DiagnosticIds.h"
#include "Report/Logger.h"
#include "Report/Stats.h"
#include "Thread/JobManager.h"

Global::Global()
{
    static Stats stats;
    stats_ = &stats;
}

void Global::setup()
{
    Os::setup();
    diagIds_  = new DiagnosticIds();
    logger_   = new Logger();
    langSpec_ = new LangSpec();
    cmdLine_  = new CommandLine();
    jobMgr_   = new JobManager();
}
