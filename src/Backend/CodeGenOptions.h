#pragma once
#include "Runtime/Runtime.h"

SWC_BEGIN_NAMESPACE();

struct Module;

struct CodeGenOptions
{
    Module*                       module   = nullptr;
    Runtime::BuildCfgBackendOptim optLevel = Runtime::BuildCfgBackendOptim::O0;
};

SWC_END_NAMESPACE();
