#pragma once

struct CommandLine
{
    bool ignoreBadParams = false;
    bool logColor        = true;

    uint32_t tabSize = 4;

    bool verboseErrors = false;
    Utf8 verboseErrorsFilter;
    bool verify = true;
};
