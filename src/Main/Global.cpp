#include "pch.h"

#include "CommandLine.h"
#include "FileManager.h"
#include "Lexer/LangSpec.h"
#include "Main/Global.h"
#include "Os/Os.h"
#include "Report/Logger.h"
#include "Thread/JobManager.h"

SWC_BEGIN_NAMESPACE()

Global::Global()
{
    static Logger      logger;
    static LangSpec    langSpec;
    static JobManager  jobManager;
    static FileManager fileManager;

    logger_      = &logger;
    langSpec_    = &langSpec;
    jobManager_  = &jobManager;
    fileManager_ = &fileManager;
}

void Global::initialize(const CommandLine& cmdLine) const
{
    Os::initialize();
    langSpec_->setup();
    jobManager_->setNumThreads(cmdLine.numCores);
}

SWC_END_NAMESPACE()
