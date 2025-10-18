#include "pch.h"
#include "Main/CompilerInstance.h"
#include "Report/DiagReporter.h"
#include "Report/Logger.h"

CompilerInstance::CompilerInstance()
{
    diagReporter_ = std::make_unique<DiagReporter>();
    logger_ = std::make_unique<Logger>();
}