#pragma once
#include "Main/ExitCodes.h"

SWC_BEGIN_NAMESPACE();

struct CommandLine;
class Global;

ExitCode runEditorService(Global& global, CommandLine& cmdLine);

SWC_END_NAMESPACE();
