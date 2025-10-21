#include "pch.h"

#include "Lexer/LangSpec.h"
#include "Main/CommandLine.h"
#include "Main/CompilerInstance.h"
#include "Os/Os.h"
#include "Report/DiagnosticIds.h"
#include "Report/Logger.h"

CompilerInstance::CompilerInstance()
{
    Os::setup();
    diagIds_ = std::make_unique<DiagnosticIds>();
    logger_ = std::make_unique<Logger>();
    langSpec_ = std::make_unique<LangSpec>();
    cmdLine_ = std::make_unique<CommandLine>();
}