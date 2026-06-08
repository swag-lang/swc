#pragma once

#include "Support/Os/Os.h"

SWC_BEGIN_NAMESPACE();

// A fully self-contained description of a single external linker/librarian invocation. Everything
// the background thread needs to spawn and wait on the tool lives here, so the actual process run
// (NativeLinker::executeToolRun) touches no compiler state and can run concurrently with other
// module work. All diagnostics, output replay and artifact validation happen back on the foreground
// thread in NativeLinker::finishToolRun, which keeps the build log ordered and avoids racing the
// global logger.
struct NativeLinkerToolRun
{
    fs::path                              exePath;
    std::vector<Utf8>                     runArgs;
    fs::path                              buildDir;
    std::function<bool(std::string_view)> outputLineFilter;

    // Filled in by NativeLinker::executeToolRun on whatever thread runs the process.
    std::string          capturedOutput;
    Utf8                 systemError;
    uint32_t             exitCode  = 0;
    Os::ProcessRunResult runResult = Os::ProcessRunResult::Ok;
    bool                 executed  = false;
};

SWC_END_NAMESPACE();
