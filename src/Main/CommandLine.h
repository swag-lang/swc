#pragma once
SWC_BEGIN_NAMESPACE();

struct CommandLine
{
    bool     logColor      = true;
    bool     errorAbsolute = false;
    bool     silent        = false;
    bool     stats         = false;
    uint32_t numCores      = 0;

    uint32_t tabSize = 4;

    bool verboseErrors = false;
    Utf8 verboseErrorsFilter;
    bool verify = true;
};

SWC_END_NAMESPACE();
