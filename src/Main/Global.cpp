#include "pch.h"

#include "Lexer/LangSpec.h"
#include "Main/FileManager.h"
#include "Main/Global.h"
#include "Os/Os.h"
#include "Report/DiagnosticIds.h"
#include "Report/Logger.h"
#include "Thread/JobManager.h"

Global& Global::get()
{
    static Global instance;
    return instance;
}

void Global::initialize()
{
    Os::initialize();
    diagIds_     = std::make_unique<DiagnosticIds>();
    logger_      = std::make_unique<Logger>();
    langSpec_    = std::make_unique<LangSpec>();
    jobManager_  = std::make_unique<JobManager>();
    fileManager_ = std::make_unique<FileManager>();
}
