#include "pch.h"
#include "Main/CommandLine.h"
#include "Main/CommandLineParser.h"
#include "Main/CompilerInstance.h"
#include "Main/ExitCodes.h"
#include "Main/Global.h"
#include "Support/Os/Os.h"
#include "Support/Report/HardwareException.h"
#include "Support/Report/Logger.h"
#include "Support/Unittest/Unittest.h"

namespace
{
    int onUnhandledHostException(const void* exceptionPointers);

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
        std::println(stderr, "{}", title);
        std::fflush(stderr);
    }

    [[noreturn]]
    void onTerminate() noexcept
    {
        printFatalProcessMessage("fatal error: unhandled C++ exception (std::terminate)");
        std::abort();
    }

    int onUnhandledHostException(const void* exceptionPointers)
    {
        uint32_t    exceptionCode    = 0;
        const void* exceptionAddress = nullptr;
        swc::Os::decodeHostException(exceptionCode, exceptionAddress, exceptionPointers);

        swc::Utf8 msg;
        msg += "fatal error: unhandled host exception\n";
        swc::HardwareException::appendSectionHeader(msg, "host");
        swc::HardwareException::appendField(msg, "backend", swc::Os::hostExceptionBackendName());
        swc::HardwareException::appendField(msg, "code", std::format("0x{:08X}", exceptionCode));
        swc::HardwareException::appendField(msg, "address", std::format("0x{:016X}", reinterpret_cast<uint64_t>(exceptionAddress)));
        swc::HardwareException::appendSectionHeader(msg, "cpu context");
        swc::Os::appendHostCpuContext(msg, exceptionPointers);
        std::print(stderr, "{}", msg.c_str());
        std::fflush(stderr);
        return SWC_EXCEPTION_EXECUTE_HANDLER;
    }
}

int main(int argc, char* argv[])
{
    std::set_terminate(onTerminate);
    return swc::Os::runMainWithHostExceptionBarrier(runMain, onUnhandledHostException, argc, argv);
}
