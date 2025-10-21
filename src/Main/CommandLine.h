#pragma once

class CommandLine
{
public:
    uint32_t tabSize = 4;

    bool verboseErrors = false;
    Utf8 verboseErrorsFilter;
    bool unittest = true;
};
