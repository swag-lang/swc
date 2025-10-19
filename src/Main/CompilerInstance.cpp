#include "pch.h"
#include "Main/CompilerInstance.h"
#include "Report/Logger.h"
#include "Report/Reporter.h"

CompilerInstance::CompilerInstance()
{
    diagReporter_ = std::make_unique<Reporter>();
    logger_ = std::make_unique<Logger>();
}