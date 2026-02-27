#include "pch.h"
#include "Main/CommandLine.h"
#include "Main/CommandLineParser.h"
#include "Main/CompilerInstance.h"
#include "Main/ExitCodes.h"
#include "Main/Global.h"
#include "Support/Os/Os.h"
#include "Support/Report/Logger.h"
#include "Support/Unittest/Unittest.h"

namespace
{
    int onUnhandledHostException(const void* exceptionPointers);
    LONG CALLBACK onVectoredExceptionHandler(struct _EXCEPTION_POINTERS* exceptionPointers);

    int runMain(int argc, char* argv[])
    {
        swc::Global            global;
        swc::CommandLine       cmdLine;
        swc::CommandLineParser parser(global, cmdLine);
        if (parser.parse(argc, argv) != swc::Result::Continue)
            return static_cast<int>(swc::ExitCode::ErrorCmdLine);

        global.initialize(cmdLine);

#if SWC_HAS_UNITTEST
        if (cmdLine.unittest)
        {
            const swc::TaskContext ctx(global, cmdLine);
            if (swc::Unittest::runAll(ctx) != swc::Result::Continue)
            {
                swc::Logger::print(ctx, "[unittest] failure detected\n");
                return static_cast<int>(swc::ExitCode::ErrorCommand);
            }
        }
#endif

        swc::CompilerInstance compiler(global, cmdLine);
        return static_cast<int>(compiler.run());
    }

    void printFatalProcessMessage(const char* title)
    {
        std::fprintf(stderr, "%s\n", title);
        std::fflush(stderr);
    }

    [[noreturn]]
    void onTerminate() noexcept
    {
        printFatalProcessMessage("fatal error: unhandled C++ exception (std::terminate)");
        std::abort();
    }

    LONG WINAPI onUnhandledExceptionFilter(struct _EXCEPTION_POINTERS* exceptionPointers)
    {
        onUnhandledHostException(exceptionPointers);
        return SWC_EXCEPTION_EXECUTE_HANDLER;
    }

    LONG CALLBACK onVectoredExceptionHandler(struct _EXCEPTION_POINTERS* exceptionPointers)
    {
        static LONG hasPrinted = 0;
        if (InterlockedCompareExchange(&hasPrinted, 1, 0) != 0)
            return EXCEPTION_CONTINUE_SEARCH;

        onUnhandledHostException(exceptionPointers);
        return EXCEPTION_CONTINUE_SEARCH;
    }

    int onUnhandledHostException(const void* exceptionPointers)
    {
        uint32_t    exceptionCode    = 0;
        const void* exceptionAddress = nullptr;
        swc::Os::decodeHostException(exceptionCode, exceptionAddress, exceptionPointers);
        std::fprintf(stderr,
                     "fatal error: unhandled host exception 0x%08X at %p\n",
                     exceptionCode,
                     exceptionAddress);
        std::fflush(stderr);
        return SWC_EXCEPTION_EXECUTE_HANDLER;
    }
}

int main(int argc, char* argv[])
{
    std::set_terminate(onTerminate);
    AddVectoredExceptionHandler(1, onVectoredExceptionHandler);
    SetUnhandledExceptionFilter(onUnhandledExceptionFilter);

    SWC_TRY
    {
        return runMain(argc, argv);
    }
    SWC_EXCEPT(onUnhandledHostException(SWC_GET_EXCEPTION_INFOS()))
    {
        return static_cast<int>(swc::ExitCode::HardwareException);
    }
}
