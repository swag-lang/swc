#pragma once

SWC_BEGIN_NAMESPACE();

class Global;
struct CommandLine;

namespace Backend
{
    void test(const Global& global, const CommandLine& cmdLine);
}

SWC_END_NAMESPACE();
