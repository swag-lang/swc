#include "pch.h"

#include "Lexer/LangSpec.h"
#include "Main/CommandLine.h"
#include "Main/CompilerInstance.h"
#include "Report/Logger.h"
#include "Report/Reporter.h"

CompilerInstance::CompilerInstance()
{
    diagReporter_ = std::make_unique<Reporter>();
    logger_ = std::make_unique<Logger>();
    langSpec_ = std::make_unique<LangSpec>();
    cmdLine_ = std::make_unique<CommandLine>();
}