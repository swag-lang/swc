#pragma once

struct CommandLine
{
    bool logColor = true;
    bool silent   = false;

    uint32_t tabSize = 4;

    bool verboseErrors = false;
    Utf8 verboseErrorsFilter;
    bool verify = true;
};
