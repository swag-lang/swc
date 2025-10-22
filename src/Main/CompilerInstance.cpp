#include "pch.h"

#include "Lexer/LangSpec.h"
#include "Main/CommandLine.h"
#include "Main/CompilerInstance.h"
#include "Os/Os.h"
#include "Report/DiagnosticIds.h"
#include "Report/Logger.h"
#include "Report/Stats.h"
#include "Thread/JobManager.h"

void CompilerInstance::setup()
{
    Os::setup();
    diagIds_  = new DiagnosticIds();
    logger_   = new Logger();
    langSpec_ = new LangSpec();
    cmdLine_  = new CommandLine();
    jobMgr_   = new JobManager();
    stats_    = new Stats();
}
