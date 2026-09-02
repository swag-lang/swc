#pragma once
namespace swc
{

    enum class ExitCode
    {
        Success           = 0,
        ErrorCmdLine      = 1,
        HardwareException = 2,
        PanicBox          = 3,
        ErrorCommand      = 4,
        CompileError      = 5,
    };

}
