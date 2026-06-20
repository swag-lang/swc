#include "pch.h"
#include "Main/Command/CommandLine.h"
#include "Main/Command/CommandLineParser.h"
#include "Main/CompilerInstance.h"
#include "Main/ExitCodes.h"
#include "Main/Global.h"
#include "Main/TaskContext.h"
#include "Support/Os/Os.h"
#include "Support/Report/HardwareException.h"
#include "Support/Report/ScopedTimedAction.h"
#include "Unittest/Unittest.h"

namespace
{
#ifdef _WIN32
    bool isFatalHostException(const DWORD code)
    {
        switch (code)
        {
            case EXCEPTION_ACCESS_VIOLATION:
            case EXCEPTION_ARRAY_BOUNDS_EXCEEDED:
            case EXCEPTION_DATATYPE_MISALIGNMENT:
            case EXCEPTION_FLT_DENORMAL_OPERAND:
            case EXCEPTION_FLT_DIVIDE_BY_ZERO:
            case EXCEPTION_FLT_INEXACT_RESULT:
            case EXCEPTION_FLT_INVALID_OPERATION:
            case EXCEPTION_FLT_OVERFLOW:
            case EXCEPTION_FLT_STACK_CHECK:
            case EXCEPTION_FLT_UNDERFLOW:
            case EXCEPTION_ILLEGAL_INSTRUCTION:
            case EXCEPTION_IN_PAGE_ERROR:
            case EXCEPTION_INT_DIVIDE_BY_ZERO:
            case EXCEPTION_INT_OVERFLOW:
            case EXCEPTION_PRIV_INSTRUCTION:
            case EXCEPTION_STACK_OVERFLOW:
            case 0xC0000374: // STATUS_HEAP_CORRUPTION
            case 0xC0000409: // STATUS_STACK_BUFFER_OVERRUN
                return true;
            default:
                return false;
        }
    }

    // ReSharper disable once CppParameterMayBeConstPtrOrRef
    LONG WINAPI reportUnhandledHostException(EXCEPTION_POINTERS* exceptionPointers)
    {
        static std::atomic_bool reported = false;
        const auto*             record   = exceptionPointers ? exceptionPointers->ExceptionRecord : nullptr;
        if (!record || !isFatalHostException(record->ExceptionCode))
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
#ifdef _WIN32
    void* hostExceptionHandler = AddVectoredExceptionHandler(1, reportUnhandledHostException);
#endif

    swc::Global            global;
    swc::CommandLine       cmdLine;
    swc::CommandLineParser parser(global, cmdLine);
    if (parser.parse(argc, argv) != swc::Result::Continue)
        return static_cast<int>(swc::ExitCode::ErrorCmdLine);

    global.initialize(cmdLine);
    const swc::TaskContext startupCtx(global, cmdLine);
    swc::ScopedTimedLog::printCommandHeader(startupCtx);

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
