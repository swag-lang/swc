#include "pch.h"
#include "Main/Command/Command.h"
#include "Main/Command/CommandLine.h"
#include "Main/Command/CommandLineParser.h"
#include "Main/CompilerInstance.h"
#include "Main/ExitCodes.h"
#include "Main/Global.h"
#include "Main/TaskContext.h"
#include "Support/Memory/MemoryProfile.h"
#include "Support/Os/Os.h"
#include "Support/Report/HardwareException.h"
#include "Support/Report/ScopedTimedLog.h"
#if SWC_HAS_UNITTEST
#include "Unittest/Unittest.h"
#endif

namespace
{
    // A hosted run — a script, a JIT test — arms its sandbox inside this very process, so its
    // default root carries this process id, and the runtime's own drop hook leaves it in place:
    // the same process may host another run right after, and that run expects the armed root to
    // still be there. Once the command is over nothing hosted remains, which makes this the one
    // point that can retire the root. The name is the contract with the runtime sandbox in
    // bin/std/modules/core/src/system/sandbox.swg, and only this process's own directory is ever
    // considered — never a sweep over its siblings.
    void removeOwnDefaultSandboxRoot()
    {
        std::error_code ec;
        const fs::path  root = swc::Os::getTemporaryPath() / "swag-sandbox" / std::format("run-{}", swc::Os::currentProcessId());
        fs::remove_all(root, ec);
    }

#ifdef _WIN32
    // ReSharper disable once CppParameterMayBeConstPtrOrRef
    LONG WINAPI reportUnhandledHostException(EXCEPTION_POINTERS* exceptionPointers)
    {
        static std::atomic_bool reported = false;
        const auto*             record   = exceptionPointers ? exceptionPointers->ExceptionRecord : nullptr;
        if (!record || !swc::Os::isFatalHostException(record->ExceptionCode))
            return EXCEPTION_CONTINUE_SEARCH;
        if (reported.exchange(true, std::memory_order_acq_rel))
            return EXCEPTION_CONTINUE_SEARCH;

        const swc::TaskContext* ctx = swc::TaskContext::current();
        const swc::Utf8         msg = swc::HardwareException::format(ctx, "fatal error: unhandled host hardware exception", exceptionPointers);
        std::print(stderr, "{}", msg.c_str());
        (void) std::fflush(stderr);
        return EXCEPTION_CONTINUE_SEARCH;
    }
#endif
}

int main(int argc, char* argv[])
{
    swc::MemoryProfile::configureAllocator();

#ifdef _WIN32
    void* hostExceptionHandler = AddVectoredExceptionHandler(1, reportUnhandledHostException);
#endif

    swc::Global            global;
    swc::CommandLine       cmdLine;
    swc::CommandLineParser parser(global, cmdLine);
    if (parser.parse(argc, argv) != swc::Result::Continue)
        return static_cast<int>(swc::ExitCode::ErrorCmdLine);
    if (cmdLine.helpPrinted)
        return static_cast<int>(swc::ExitCode::Success);

    global.initialize(cmdLine);
    swc::TaskContext            startupCtx(global, cmdLine);
    const swc::ScopedCommandLog commandLog(startupCtx);

    if (cmdLine.command == swc::CommandKind::New)
    {
        const swc::Result result = swc::Command::createProject(startupCtx);
        return static_cast<int>(result == swc::Result::Continue ? swc::ExitCode::Success : swc::ExitCode::ErrorCommand);
    }

    // Removing what a build wrote needs none of what a build needs: no inputs to collect, no
    // module setup to run, and nothing to schedule.
    if (cmdLine.command == swc::CommandKind::Clean)
    {
        const swc::Result result = swc::Command::clean(startupCtx);
        return static_cast<int>(result == swc::Result::Continue ? swc::ExitCode::Success : swc::ExitCode::ErrorCommand);
    }

#if SWC_HAS_UNITTEST
    if (cmdLine.command == swc::CommandKind::Unittest && !cmdLine.dryRun && !cmdLine.showConfig)
    {
        if (swc::Unittest::runAll(startupCtx) != swc::Result::Continue)
            return static_cast<int>(swc::ExitCode::ErrorCommand);
        return static_cast<int>(swc::ExitCode::Success);
    }
#endif

    swc::CompilerInstance compiler(global, cmdLine);

    const auto result = static_cast<int>(compiler.run());
    removeOwnDefaultSandboxRoot();
    std::cout.flush();
    std::cerr.flush();
    (void) std::fflush(stdout);
    (void) std::fflush(stderr);
#ifdef _WIN32
    if (hostExceptionHandler)
        RemoveVectoredExceptionHandler(hostExceptionHandler);
#endif
    return result;
}
