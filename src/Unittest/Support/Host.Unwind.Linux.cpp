#include "pch.h"
#include "Backend/Encoder/Frame.DWARF.X64.h"
#include "Backend/JIT/JITMemoryManager.h"
#include "Support/Os/Os.h"
#include "Support/Os/Os.Exception.Linux.h"
#include "Unittest/Support/Host.Tests.Linux.h"
#include <signal.h>
#include <sys/resource.h>
#include <sys/wait.h>
#include <unistd.h>

// libgcc's registration lookup is also used by its unwinder. The three bases
// are outputs; checking the lookup avoids attempting an unwind after removal.
extern "C" const void* _Unwind_Find_FDE(const void* address, void* bases);

namespace swc::LinuxHostTests
{
    namespace
    {
        struct UnwindMarker {};
        thread_local uint32_t destroyed = 0;
        thread_local std::array<uintptr_t, 32> captured{};
        thread_local uint32_t capturedCount = 0;
        volatile sig_atomic_t previouslyHandled = 0;

        void previousSignalHandler(int, siginfo_t*, void*)
        {
            previouslyHandled = previouslyHandled + 1;
        }

        void raiseNativeSignal(void*)
        {
            raise(SIGILL);
        }

        void verifyPreviousSignalHandler()
        {
            // Run before the parent's first protected call so each child installs
            // the compiler handlers over its own pre-existing signal disposition.
            for (uint32_t count = 1; count <= 2; ++count)
            {
                const pid_t child = fork();
                if (child == 0)
                {
                    struct sigaction action{};
                    action.sa_sigaction = previousSignalHandler;
                    action.sa_flags = SA_SIGINFO | SA_RESETHAND;
                    sigemptyset(&action.sa_mask);
                    if (sigaction(SIGILL, &action, nullptr) != 0)
                        _exit(76);
                    for (uint32_t i = 0; i < count; ++i)
                    {
                        Os::LinuxException exception;
                        if (!Os::executeWithHostFaultHandler(exception, raiseNativeSignal, nullptr) || previouslyHandled != 1 || exception.signal)
                            _exit(75);
                    }
                    _exit(0);
                }
                const int status = waitForChild(child);
                require(count == 1 ? WIFEXITED(status) && WEXITSTATUS(status) == 0 : WIFSIGNALED(status) && WTERMSIG(status) == SIGILL, "previous signal handler or its reset disposition was lost");
            }
        }

        __attribute__((noinline)) void captureFromGeneratedCode()
        {
            capturedCount = Os::captureCallStack(captured);
            asm volatile("" ::: "memory");
        }

        __attribute__((noinline)) void throwFromGeneratedCode()
        {
            throw UnwindMarker{};
        }

        __attribute__((noinline)) void invokeWithCleanup(void* entry)
        {
            struct Cleanup
            {
                ~Cleanup() { ++destroyed; }
            } cleanup;
            reinterpret_cast<void (*)(void (*)())>(entry)(throwFromGeneratedCode);
            asm volatile("" ::: "memory");
        }

        void invokeNestedBoundary(void* entry)
        {
            Os::LinuxException inner;
            require(!Os::executeWithHostFaultHandler(inner, invokeWithCleanup, entry), "inner boundary did not recover");
            invokeWithCleanup(entry);
        }

        void nativeFault(void*)
        {
            asm volatile("ud2" ::: "memory");
        }

        void completeNormally(void* argument)
        {
            ++*static_cast<uint32_t*>(argument);
        }

        void verifyFaultUnwind(JITMemoryManager& manager)
        {
            // xor eax,eax; mov [rax],eax; ret. The fault originates in generated
            // code, with a live native C++ cleanup between it and the boundary.
            const uint8_t code[] = {0x31, 0xc0, 0x89, 0x00, 0xc3};
            X64DwarfFrame rules;
            ByteArray frame;
            rules.build(frame, sizeof(code));
            JITMemory memory;
            manager.allocateWithCodeSize(memory, sizeof(code) + frame.size(), sizeof(code));
            std::memcpy(memory.entryPoint(), code, sizeof(code));
            JITMemoryManager::copyUnwindInfo(memory, frame.span());
            JITMemoryManager::registerUnwindInfo(memory);
            JITMemoryManager::makeExecutable(memory);

            const pid_t child = fork();
            if (child == 0)
            {
                destroyed = 0;
                // Repeat to catch an unrestored signal mask or active boundary.
                for (uint32_t i = 0; i < 3; ++i)
                {
                    Os::LinuxException exception;
                    if (Os::executeWithHostFaultHandler(exception, invokeWithCleanup, memory.entryPoint()) || destroyed != i + 1)
                        _exit(83);
                    const uintptr_t expected = reinterpret_cast<uintptr_t>(memory.entryPoint()) + 2;
                    if (exception.signal != SIGSEGV || exception.instructionAddress != expected || exception.faultAddress != 0 ||
                        exception.registers[16] != expected || !exception.frameCount || exception.frames[0] != expected)
                        _exit(82);
                    uint32_t decodedSignal = 0;
                    const void* decodedAddress = nullptr;
                    Os::decodeHostException(decodedSignal, decodedAddress, &exception);
                    if (decodedSignal != SIGSEGV || reinterpret_cast<uintptr_t>(decodedAddress) != expected)
                        _exit(81);
                    Utf8 report;
                    Os::appendHostExceptionSummary(nullptr, report, &exception);
                    Os::appendHostCpuContext(report, &exception);
                    Os::appendHostHandlerStack(report, &exception);
                    if (!report.contains("SIGSEGV") || !report.contains("rip") || !report.contains(std::format("0x{:016X}", expected)))
                        _exit(80);
                }
                Os::LinuxException outer;
                if (Os::executeWithHostFaultHandler(outer, invokeNestedBoundary, memory.entryPoint()) || destroyed != 5)
                    _exit(79);
                uint32_t completed = 0;
                if (!Os::executeWithHostFaultHandler(outer, completeNormally, &completed) || completed != 1 || outer.signal || outer.frameCount)
                    _exit(78);
                _exit(0);
            }
            const int status = waitForChild(child);
            require(WIFEXITED(status) && WEXITSTATUS(status) == 0, "signal unwind across generated code skipped native cleanup");

            const pid_t nativeChild = fork();
            if (nativeChild == 0)
            {
                Os::LinuxException exception;
                Os::executeWithHostFaultHandler(exception, nativeFault, nullptr);
                _exit(77);
            }
            const int nativeStatus = waitForChild(nativeChild);
            require(WIFSIGNALED(nativeStatus) && WTERMSIG(nativeStatus) == SIGILL, "native compiler fault became a recovered JIT error");
        }

        void verifyConcurrentFrameRemoval(JITMemoryManager& manager)
        {
            X64DwarfFrame rules;
            ByteArray frame;
            rules.build(frame, 1);
            std::atomic<bool> scanning = true;
            std::atomic<uint32_t> scans = 0;
            std::thread reader([&] {
                while (scanning.load(std::memory_order_relaxed))
                {
                    Os::isRegisteredJitCode(UINTPTR_MAX);
                    scans.fetch_add(1, std::memory_order_relaxed);
                }
            });
            while (!scans.load(std::memory_order_relaxed))
                std::this_thread::yield();
            for (uint32_t i = 0; i < 128; ++i)
            {
                JITMemory memory;
                manager.allocateWithCodeSize(memory, static_cast<uint32_t>(1 + frame.size()), 1);
                *static_cast<uint8_t*>(memory.entryPoint()) = 0xc3;
                JITMemoryManager::copyUnwindInfo(memory, frame.span());
                JITMemoryManager::registerUnwindInfo(memory);
                memory.reset();
            }
            scanning.store(false, std::memory_order_relaxed);
            reader.join();
            require(scans.load() > 0 && !Os::isRegisteredJitCode(UINTPTR_MAX), "concurrent range lookup did not complete");
        }

        void verifyStackOverflowUnwind(JITMemoryManager& manager)
        {
            // Anchor CFA in rbp, then grow and touch the stack one page at a time.
            // This needs both the alternate signal stack and a frame rule that
            // remains valid when rsp itself points outside committed stack memory.
            const uint8_t code[] = {0x55, 0x48, 0x89, 0xe5, 0x48, 0x81, 0xec, 0, 0x10, 0, 0, 0xc6, 0x04, 0x24, 0, 0xeb, 0xf3};
            X64DwarfFrame rules;
            rules.advance(1);
            rules.defineCfa(7, 16);
            rules.saveRegister(6, -16);
            rules.advance(4);
            rules.defineCfa(6, 16);
            ByteArray frame;
            rules.build(frame, sizeof(code));
            JITMemory memory;
            manager.allocateWithCodeSize(memory, sizeof(code) + frame.size(), sizeof(code));
            std::memcpy(memory.entryPoint(), code, sizeof(code));
            JITMemoryManager::copyUnwindInfo(memory, frame.span());
            JITMemoryManager::registerUnwindInfo(memory);
            JITMemoryManager::makeExecutable(memory);
            const pid_t child = fork();
            if (child == 0)
            {
                const rlimit stackLimit{128 * 1024, 128 * 1024};
                if (setrlimit(RLIMIT_STACK, &stackLimit) != 0)
                    _exit(74);
                destroyed = 0;
                Os::LinuxException exception;
                if (Os::executeWithHostFaultHandler(exception, invokeWithCleanup, memory.entryPoint()) || destroyed != 1 ||
                    exception.signal != SIGSEGV || exception.instructionAddress != reinterpret_cast<uintptr_t>(memory.entryPoint()) + 11)
                    _exit(73);
                _exit(0);
            }
            const int status = waitForChild(child);
            require(WIFEXITED(status) && WEXITSTATUS(status) == 0, "generated stack overflow did not unwind native cleanup");
        }

        bool hasRegisteredFrame(const void* address)
        {
            std::array<void*, 3> bases{};
            return _Unwind_Find_FDE(address, bases.data()) != nullptr;
        }

        void verifyGeneratedFrame(JITMemoryManager& manager, const std::span<const uint8_t> code, const X64DwarfFrame& rules)
        {
            ByteArray frame;
            rules.build(frame, static_cast<uint32_t>(code.size()));
            JITMemory memory;
            manager.allocateWithCodeSize(memory, static_cast<uint32_t>(code.size() + frame.size()), static_cast<uint32_t>(code.size()));
            std::memcpy(memory.entryPoint(), code.data(), code.size());
            JITMemoryManager::copyUnwindInfo(memory, frame.span());
            JITMemoryManager::makeExecutable(memory);
            require(!hasRegisteredFrame(memory.entryPoint()), "new JIT memory already has unwind metadata");
            JITMemoryManager::registerUnwindInfo(memory);
            require(hasRegisteredFrame(memory.entryPoint()), "registered JIT frame is absent from libgcc");
            const uintptr_t address = reinterpret_cast<uintptr_t>(memory.entryPoint());
            require(Os::isRegisteredJitCode(address) && Os::isRegisteredJitCode(address + code.size() - 1), "registered code range excludes an instruction");
            require(!Os::isRegisteredJitCode(address - 1) && !Os::isRegisteredJitCode(address + code.size()), "registered code range includes neighboring bytes");
            require(Os::addHostJitFunctionTable(memory), "repeated frame registration failed");

            captured.fill(0);
            capturedCount = 0;
            reinterpret_cast<void (*)(void (*)())>(memory.entryPoint())(captureFromGeneratedCode);
            const uintptr_t start = reinterpret_cast<uintptr_t>(memory.entryPoint());
            bool foundJit = false;
            bool foundCaller = false;
            for (uint32_t i = 0; i < capturedCount; ++i)
            {
                const bool inJit = captured[i] >= start && captured[i] < start + code.size();
                if (foundJit && !inJit)
                    foundCaller = true;
                foundJit |= inJit;
            }
            require(foundJit && foundCaller, "native backtrace stopped at a generated frame");

            destroyed = 0;
            bool caught = false;
            try
            {
                Os::LinuxException exception;
                Os::executeWithHostFaultHandler(exception, invokeWithCleanup, memory.entryPoint());
            }
            catch (const UnwindMarker&)
            {
                caught = true;
            }
            require(caught && destroyed == 1, "C++ exception crossing generated code skipped a destructor");

            void* entry = memory.entryPoint();
            JITMemory moved(std::move(memory));
            memory.reset();
            require(hasRegisteredFrame(entry), "move construction deregistered the live frame");
            memory = std::move(moved);
            moved.reset();
            require(hasRegisteredFrame(entry), "move assignment deregistered the live frame");
            memory.reset();
            require(!hasRegisteredFrame(entry) && !Os::isRegisteredJitCode(reinterpret_cast<uintptr_t>(entry)), "reset left a stale JIT frame");
            memory.reset();
        }
    }

    void testGeneratedUnwind()
    {
        verifyPreviousSignalHandler();
        JITMemoryManager manager;
        X64DwarfFrame rules;
        // sub rsp,8; call rdi; add rsp,8; ret
        const std::array<uint8_t, 11> frameless = {0x48, 0x83, 0xec, 8, 0xff, 0xd7, 0x48, 0x83, 0xc4, 8, 0xc3};
        rules.advance(4);
        rules.defineCfa(7, 16);
        rules.advance(10);
        rules.defineCfa(7, 8);
        verifyGeneratedFrame(manager, frameless, rules);

        // A frame pointer keeps CFA stable across an additional body allocation.
        // push rbp; mov rbp,rsp; sub rsp,32; call rdi; add rsp,32; pop rbp; ret
        const std::array<uint8_t, 16> framed = {0x55, 0x48, 0x89, 0xe5, 0x48, 0x83, 0xec, 32, 0xff, 0xd7, 0x48, 0x83, 0xc4, 32, 0x5d, 0xc3};
        rules.reset();
        rules.advance(1);
        rules.defineCfa(7, 16);
        rules.saveRegister(6, -16);
        rules.advance(4);
        rules.defineCfa(6, 16);
        rules.advance(15);
        rules.defineCfa(7, 8);
        rules.restoreRegister(6);
        verifyGeneratedFrame(manager, framed, rules);

        // Exercise a long location delta and a multibyte ULEB stack offset.
        std::vector<uint8_t> large(128, 0x90);
        const uint8_t body[] = {0x48, 0x81, 0xec, 8, 2, 0, 0, 0xff, 0xd7, 0x48, 0x81, 0xc4, 8, 2, 0, 0, 0xc3};
        large.insert(large.end(), std::begin(body), std::end(body));
        rules.reset();
        rules.advance(135);
        rules.defineCfa(7, 528);
        rules.advance(144);
        rules.defineCfa(7, 8);
        verifyGeneratedFrame(manager, large, rules);

        // A second return path must recover the body's CFA after the first
        // epilogue. Non-null callback addresses always take that second path.
        const std::array<uint8_t, 23> twoReturns = {0x48, 0x83, 0xec, 8, 0x48, 0x85, 0xff, 0x75, 7, 0xff, 0xd7, 0x48, 0x83, 0xc4, 8, 0xc3, 0xff, 0xd7, 0x48, 0x83, 0xc4, 8, 0xc3};
        rules.reset();
        rules.advance(4);
        rules.defineCfa(7, 16);
        rules.rememberState();
        rules.advance(15);
        rules.defineCfa(7, 8);
        rules.advance(16);
        rules.restoreState();
        rules.advance(22);
        rules.defineCfa(7, 8);
        verifyGeneratedFrame(manager, twoReturns, rules);
        verifyFaultUnwind(manager);
        verifyStackOverflowUnwind(manager);
        verifyConcurrentFrameRemoval(manager);

        ByteArray malformed;
        rules.build(malformed, static_cast<uint32_t>(large.size()));
        require(!X64DwarfFrame::relocate(malformed, 0, large.size()), "null code address accepted");
        require(!X64DwarfFrame::relocate(malformed, 4096, 1), "mismatched code range accepted");
        malformed[8] = std::byte{0xff};
        require(!X64DwarfFrame::relocate(malformed, 4096, large.size()), "foreign CIE version accepted");
    }
}
