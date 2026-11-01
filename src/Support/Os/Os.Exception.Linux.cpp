#include "pch.h"
#include "Support/Os/Os.h"
#include "Support/Os/Os.Exception.Linux.h"
#include "Support/Report/Assert.h"

#ifdef __linux__
#include <setjmp.h>
#include <signal.h>
#include <sys/mman.h>
#include <sys/syscall.h>
#include <ucontext.h>
#include <unistd.h>
#include <unwind.h>

SWC_BEGIN_NAMESPACE();

namespace
{
    struct FaultBoundary
    {
        sigjmp_buf point;
        uintptr_t cfa = 0;
        _Unwind_Exception exception{};
        Os::LinuxException* output = nullptr;
        bool unwinding = false;
    };

    thread_local FaultBoundary* activeBoundary = nullptr;
    constexpr std::array<int, 4> K_FAULT_SIGNALS = {SIGSEGV, SIGBUS, SIGILL, SIGFPE};
    std::array<struct sigaction, K_FAULT_SIGNALS.size()> previousHandlers{};
    std::array<std::atomic<bool>, K_FAULT_SIGNALS.size()> previousHandlerConsumed{};
    static_assert(std::atomic<bool>::is_always_lock_free);

    void terminateWithSignal(const int signal)
    {
        struct sigaction action{};
        action.sa_handler = SIG_DFL;
        sigemptyset(&action.sa_mask);
        sigaction(signal, &action, nullptr);
        // The current signal may still be blocked inside its handler. Queue it,
        // then unblock it rather than fabricating an ordinary exit status.
        syscall(SYS_tgkill, getpid(), syscall(SYS_gettid), signal);
        sigset_t mask;
        sigemptyset(&mask);
        sigaddset(&mask, signal);
        sigprocmask(SIG_UNBLOCK, &mask, nullptr);
        _exit(128 + signal);
    }

    void abandonedFaultUnwind(_Unwind_Reason_Code, _Unwind_Exception*)
    {
        // A foreign catch-all consumed the forced unwind. Continuing would report
        // a successful JIT call after a hardware fault and skip outer cleanup.
        terminateWithSignal(activeBoundary ? static_cast<int>(activeBoundary->output->signal) : SIGABRT);
    }

    _Unwind_Reason_Code stopFaultUnwind(int, const _Unwind_Action actions, uint64_t, _Unwind_Exception*, _Unwind_Context* context, void* data)
    {
        auto* boundary = static_cast<FaultBoundary*>(data);
        if (_Unwind_GetCFA(context) == boundary->cfa)
            siglongjmp(boundary->point, 1);
        auto& output = *boundary->output;
        const uintptr_t ip = _Unwind_GetIP(context);
        if (output.frameCount < output.frames.size() && (output.frameCount || ip == output.instructionAddress))
            output.frames[output.frameCount++] = ip;
        if (actions & _UA_END_OF_STACK)
            terminateWithSignal(static_cast<int>(output.signal));
        return _URC_NO_REASON;
    }

    void captureFault(Os::LinuxException& output, const int signal, const siginfo_t* info, const ucontext_t& context)
    {
        constexpr std::array<int, 17> K_GREGS = {REG_RAX, REG_RDX, REG_RCX, REG_RBX, REG_RSI, REG_RDI, REG_RBP, REG_RSP, REG_R8, REG_R9, REG_R10, REG_R11, REG_R12, REG_R13, REG_R14, REG_R15, REG_RIP};
        output.signal = signal;
        output.signalCode = info ? info->si_code : 0;
        output.instructionAddress = context.uc_mcontext.gregs[REG_RIP];
        output.faultAddress = info ? reinterpret_cast<uintptr_t>(info->si_addr) : 0;
        for (size_t i = 0; i < K_GREGS.size(); ++i)
            output.registers[i] = context.uc_mcontext.gregs[K_GREGS[i]];
    }

    void handleFault(const int signal, siginfo_t* info, void* rawContext)
    {
        const auto* context = static_cast<const ucontext_t*>(rawContext);
        if (activeBoundary && !activeBoundary->unwinding && info && info->si_code > 0 && context &&
            Os::isRegisteredJitCode(context->uc_mcontext.gregs[REG_RIP]))
        {
            FaultBoundary* boundary = activeBoundary;
            boundary->unwinding = true;
            captureFault(*boundary->output, signal, info, *context);
            boundary->exception.exception_class = 0x5357434c494e5558ULL;
            boundary->exception.exception_cleanup = abandonedFaultUnwind;
            _Unwind_ForcedUnwind(&boundary->exception, stopFaultUnwind, boundary);
            terminateWithSignal(signal);
        }

        // Native compiler faults, asynchronous user signals, and faults during
        // cleanup do not become recoverable generated-code errors.
        if (!activeBoundary || !activeBoundary->unwinding)
        {
            for (size_t i = 0; i < K_FAULT_SIGNALS.size(); ++i)
            {
                if (K_FAULT_SIGNALS[i] != signal)
                    continue;
                const auto& previous = previousHandlers[i];
                if (previous.sa_handler == SIG_IGN && info && info->si_code <= 0)
                    return;
                if (previous.sa_handler != SIG_DFL && previous.sa_handler != SIG_IGN)
                {
                    if ((previous.sa_flags & SA_RESETHAND) && previousHandlerConsumed[i].exchange(true))
                        terminateWithSignal(signal);
                    if (previous.sa_flags & SA_SIGINFO)
                        previous.sa_sigaction(signal, info, rawContext);
                    else
                        previous.sa_handler(signal);
                    return;
                }
            }
        }
        terminateWithSignal(signal);
    }

    void installFaultHandlers()
    {
        // Load the native unwinder before a fault can need it on an alternate stack.
        std::array<uintptr_t, 1> frames{};
        Os::captureCallStack(frames);
        struct sigaction action{};
        action.sa_sigaction = handleFault;
        for (size_t i = 0; i < K_FAULT_SIGNALS.size(); ++i)
        {
            SWC_FORCE_ASSERT(sigaction(K_FAULT_SIGNALS[i], nullptr, &previousHandlers[i]) == 0);
            action.sa_mask = previousHandlers[i].sa_mask;
            action.sa_flags = SA_SIGINFO | SA_ONSTACK | (previousHandlers[i].sa_flags & (SA_NODEFER | SA_RESTART));
            SWC_FORCE_ASSERT(sigaction(K_FAULT_SIGNALS[i], &action, nullptr) == 0);
        }
    }

    struct FaultHandlerStack
    {
        void* mapping = nullptr;
        size_t mappingSize = 0;
        stack_t previous{};

        ~FaultHandlerStack()
        {
            if (!mapping)
                return;
            stack_t current{};
            if (sigaltstack(nullptr, &current) != 0 || (current.ss_flags & SS_ONSTACK))
                return;
            if (current.ss_sp == static_cast<std::byte*>(mapping) + Os::memoryPageSize())
            {
                // Restore an embedder's earlier stack, but never replace a stack installed
                // after ours. A failed restore leaves the kernel using this mapping.
                if (sigaltstack(&previous, nullptr) != 0)
                    return;
            }
            munmap(mapping, mappingSize);
        }

        void reserve()
        {
            if (mapping)
                return;
            const size_t page = Os::memoryPageSize();
            const long recommended = sysconf(_SC_SIGSTKSZ);
            // Account for the kernel's extended CPU-state signal frame, with room for the
            // fault reporter even when the interrupted thread has exhausted its own stack.
            const size_t usable = (std::max<size_t>(64 * 1024, recommended > 0 ? recommended : 0) + page - 1) & ~(page - 1);
            mappingSize = usable + 2 * page;
            void* memory = mmap(nullptr, mappingSize, PROT_NONE, MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
            SWC_FORCE_ASSERT(memory != MAP_FAILED);
            void* base = static_cast<std::byte*>(memory) + page;
            if (mprotect(base, usable, PROT_READ | PROT_WRITE) != 0)
            {
                munmap(memory, mappingSize);
                SWC_FORCE_ASSERT(false && "cannot commit the fault handler stack");
            }
            const stack_t stack{.ss_sp = base, .ss_flags = 0, .ss_size = usable};
            if (sigaltstack(&stack, &previous) != 0)
            {
                munmap(memory, mappingSize);
                SWC_FORCE_ASSERT(false && "cannot install the fault handler stack");
            }
            mapping = memory;
        }
    };
}

__attribute__((noinline)) bool Os::executeWithHostFaultHandler(LinuxException& outException, void (*function)(void*), void* argument)
{
    SWC_ASSERT(function);
    reserveFaultHandlerStack();
    static std::once_flag installed;
    std::call_once(installed, installFaultHandlers);
    outException = {};
    FaultBoundary boundary;
    // siglongjmp makes modified automatic locals indeterminate. The restoration
    // object is separate, never modified by the handler, and also runs for C++ throws.
    struct RestoreBoundary
    {
        FaultBoundary* previous;
        ~RestoreBoundary() { activeBoundary = previous; }
    } restore{activeBoundary};
    boundary.output = &outException;
    boundary.cfa = reinterpret_cast<uintptr_t>(__builtin_dwarf_cfa());
    activeBoundary = &boundary;
    if (sigsetjmp(boundary.point, 1))
        return false;
    function(argument);
    return true;
}

void Os::reserveFaultHandlerStack()
{
    thread_local FaultHandlerStack stack;
    stack.reserve();
}

const char* Os::hostExceptionBackendName()
{
    return "POSIX signals";
}

bool Os::isFatalHostException(const uint32_t exceptionCode)
{
    return exceptionCode == SIGSEGV || exceptionCode == SIGBUS || exceptionCode == SIGILL || exceptionCode == SIGFPE;
}

SWC_END_NAMESPACE();
#endif
