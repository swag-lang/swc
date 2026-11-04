#include "pch.h"
#include "Support/Os/Os.h"
#include "Unittest/Support/LinuxHostTests.h"
#include <signal.h>
#include <sys/mman.h>
#include <sys/resource.h>
#include <sys/wait.h>
#include <unistd.h>

namespace swc::LinuxHostTests
{
    namespace
    {
        thread_local uintptr_t stackBegin = 0;
        thread_local uintptr_t stackEnd = 0;
        thread_local volatile sig_atomic_t deliveredOnStack = 0;
        thread_local bool exitOnSignal = false;

        void observeSignal(int)
        {
            volatile unsigned char marker = 0;
            const auto address = reinterpret_cast<uintptr_t>(&marker);
            const bool onStack = stackBegin <= address && address < stackEnd;
            deliveredOnStack = onStack ? 1 : -1;
            if (exitOnSignal)
                _exit(onStack ? 0 : 1);
        }

        bool prepareSignalStack()
        {
            Os::reserveFaultHandlerStack();
            stack_t stack{};
            if (sigaltstack(nullptr, &stack) != 0 || (stack.ss_flags & SS_DISABLE) || stack.ss_size < 64 * 1024)
                return false;
            stackBegin = reinterpret_cast<uintptr_t>(stack.ss_sp);
            stackEnd = stackBegin + stack.ss_size;
            Os::reserveFaultHandlerStack();
            stack_t repeated{};
            return sigaltstack(nullptr, &repeated) == 0 && repeated.ss_sp == stack.ss_sp && repeated.ss_size == stack.ss_size;
        }
    }

    void testFaultHandlerStacks()
    {
        require(Os::isFatalHostException(SIGSEGV) && Os::isFatalHostException(SIGBUS) && Os::isFatalHostException(SIGILL) && Os::isFatalHostException(SIGFPE), "hardware fault classification omitted a fatal signal");
        require(!Os::isFatalHostException(SIGUSR1) && !Os::isFatalHostException(0), "ordinary signal was classified as a hardware fault");
        struct sigaction action{}, previous{};
        action.sa_handler = observeSignal;
        action.sa_flags = SA_ONSTACK;
        sigemptyset(&action.sa_mask);
        require(sigaction(SIGUSR1, &action, &previous) == 0, "cannot install signal-stack observer");
        std::array<uintptr_t, 3> stacks{};
        std::array<std::jthread, 3> workers;
        std::barrier ready(3);
        std::atomic_bool passed = true;
        for (size_t i = 0; i < workers.size(); ++i)
        {
            workers[i] = std::jthread([&, i] {
                if (!prepareSignalStack() || raise(SIGUSR1) != 0 || deliveredOnStack != 1)
                    passed.store(false);
                stacks[i] = stackBegin;
                ready.arrive_and_wait();
            });
        }
        for (auto& worker : workers)
            worker.join();
        require(sigaction(SIGUSR1, &previous, nullptr) == 0, "cannot restore earlier signal handler");
        require(passed.load() && stacks[0] != stacks[1] && stacks[0] != stacks[2] && stacks[1] != stacks[2], "threads did not receive private fault-handler stacks");
        for (const uintptr_t stack : stacks)
        {
            unsigned char resident = 0;
            require(mincore(reinterpret_cast<void*>(stack), Os::memoryPageSize(), &resident) == -1 && errno == ENOMEM, "thread exit retained its fault-handler stack");
        }

        const pid_t child = fork();
        if (child == 0)
        {
            const rlimit limit{128 * 1024, 128 * 1024};
            if (setrlimit(RLIMIT_STACK, &limit) != 0 || !prepareSignalStack() || sigaction(SIGSEGV, &action, nullptr) != 0)
                _exit(2);
            exitOnSignal = true;
            // sub rsp, 4096; mov [rsp], rax; jmp back. Touch every page until the regular
            // stack cannot grow; only the alternate signal stack can report this fault.
            const uint8_t instructions[]{0x48, 0x81, 0xec, 0x00, 0x10, 0x00, 0x00, 0x48, 0x89, 0x04, 0x24, 0xeb, 0xf3};
            void* code = Os::allocExecutableMemory(Os::memoryPageSize());
            if (!code)
                _exit(2);
            std::memcpy(code, instructions, sizeof(instructions));
            if (!Os::makeExecutableMemory(code, Os::memoryPageSize()))
                _exit(2);
            reinterpret_cast<void (*)()>(code)();
            _exit(3);
        }
        const int status = waitForChild(child);
        require(WIFEXITED(status) && WEXITSTATUS(status) == 0, "stack overflow was not delivered on the fault-handler stack");
    }
}
