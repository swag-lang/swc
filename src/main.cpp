#include "pch.h"
#include "Main/CompilerCli.h"
#include "Main/ExitCodes.h"
#include "Main/TaskContext.h"
#include "Support/Memory/Allocator.h"
#include "Support/Os/Os.h"
#include "Support/Report/HardwareException.h"

namespace
{
    // Hosted programs keep the process-scoped sandbox root alive between runtime calls. Once
    // this compiler command finishes, no hosted run remains to use the root.
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

    class ExecutableProcess
    {
    public:
        ExecutableProcess()
        {
            swc::Allocator::configure();
#ifdef _WIN32
            swc::Os::reserveFaultHandlerStack();
            hostExceptionHandler_ = AddVectoredExceptionHandler(1, reportUnhandledHostException);
#endif
        }

        ~ExecutableProcess()
        {
            removeOwnDefaultSandboxRoot();
            std::cout.flush();
            std::cerr.flush();
            (void) std::fflush(stdout);
            (void) std::fflush(stderr);
#ifdef _WIN32
            if (hostExceptionHandler_)
                RemoveVectoredExceptionHandler(hostExceptionHandler_);
#endif
        }

    private:
#ifdef _WIN32
        void* hostExceptionHandler_ = nullptr;
#endif
    };
}

int main(const int argc, char* argv[])
{
    const ExecutableProcess process;
    return static_cast<int>(swc::runCompilerCli(argc, argv));
}
