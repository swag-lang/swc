#include "pch.h"
#include "Main/CompilerInstance.h"
#include "Report/DiagReporter.h"

CompilerInstance::CompilerInstance()
{
    diagReporter_ = std::make_unique<DiagReporter>();
}