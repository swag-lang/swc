#pragma once
SWC_BEGIN_NAMESPACE()

enum class ExitCode
{
    Success           = 0,
    ErrorCmdLine      = -1,
    HardwareException = -2,
    PanicBox          = -3,
    ErrorCommand      = -4,
};

SWC_END_NAMESPACE()
