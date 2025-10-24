#include "pch.h"

#include "CommandLine.h"
#include "FileManager.h"
#include "Lexer/LangSpec.h"
#include "Main/Global.h"
#include "Os/Os.h"
#include "Report/DiagnosticIds.h"
#include "Report/Logger.h"
#include "Thread/JobManager.h"

void Global::initialize(const CommandLine& cmdLine)
{
    static DiagnosticIds diagIds;
    static Logger        logger;
    static LangSpec      langSpec;
    static JobManager    jobManager;
    static FileManager   fileManager;

    diagIds_     = &diagIds;
    logger_      = &logger;
    langSpec_    = &langSpec;
    jobManager_  = &jobManager;
    fileManager_ = &fileManager;

    Os::initialize();
    jobManager_->setNumThreads(cmdLine.numCores);
}
