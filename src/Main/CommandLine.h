#pragma once

struct CommandLine
{
    bool     ignoreBadParams = false;
    uint32_t tabSize         = 4;

    bool verboseErrors = false;
    Utf8 verboseErrorsFilter;
    bool unittest = true;
};
