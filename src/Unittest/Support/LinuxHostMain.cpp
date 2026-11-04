// This standalone boundary runs before the full compiler has a Linux host and target ABI.
#include "pch.h"
#include "Support/Os/Os.h"
#include "Support/Os/ReadOnlyFileMapping.h"
#include "Unittest/Support/LinuxHostTests.h"
#include <signal.h>
#include <sys/mman.h>
#include <sys/resource.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <unistd.h>

namespace swc
{
    void swcAssert(const char* expr, const char* file, const int line)
    {
        std::fprintf(stderr, "%s:%d: assertion: %s\n", file, line, expr);
        std::abort();
    }
}

namespace swc::LinuxHostTests
{
    void require(const bool condition, const char* message)
    {
        if (!condition)
            throw std::runtime_error(message);
    }

    int waitForChild(const pid_t child)
    {
        require(child > 0, "cannot create test child");
        int   status = 0;
        pid_t waited;
        do
            waited = waitpid(child, &status, 0);
        while (waited < 0 && errno == EINTR);
        require(waited == child, "cannot wait for test child");
        return status;
    }

    void expectAccessFault(void* address, const bool write)
    {
        const pid_t child = fork();
        if (child == 0)
        {
            auto* byte = static_cast<volatile uint8_t*>(address);
            if (write)
                *byte = 1;
            else
                SWC_UNUSED(*byte);
            _exit(0);
        }
        const int status = waitForChild(child);
        require(WIFSIGNALED(status) && WTERMSIG(status) == SIGSEGV, "memory access did not fault with SIGSEGV");
    }

    void testExecutableMemory()
    {
        const uint32_t pageSize = Os::memoryPageSize();
        require(pageSize >= 4096 && std::has_single_bit(pageSize), "host page size is not a power of two");
        require(!Os::allocExecutableMemory(0) && !Os::allocProximityMemory(0), "zero allocation succeeded");
        require(!Os::makeExecutableMemory(nullptr, 1), "null protection succeeded");

        auto* code = static_cast<uint8_t*>(Os::allocExecutableMemory(pageSize));
        require(code && reinterpret_cast<uintptr_t>(code) % pageSize == 0, "code allocation is not page-aligned");
        require(code[0] == 0 && code[pageSize - 1] == 0, "new code memory is not zeroed");
        // x86-64: mov eax, 42; ret. No argument/aggregate ABI is implied by this smoke.
        const uint8_t instructions[] = {0xB8, 42, 0, 0, 0, 0xC3};
        std::memcpy(code, instructions, sizeof(instructions));
        require(Os::makeExecutableMemory(code + 1, sizeof(instructions) - 1), "cannot publish an unaligned code range");
        const auto function = reinterpret_cast<int (*)()>(code);
        require(function() == 42, "published code returned another value");
        expectAccessFault(code, true);
        require(Os::makeWritableExecutableMemory(code, pageSize), "cannot reopen code for patching");
        code[1] = 43;
        require(Os::makeExecutableMemory(code, pageSize), "cannot republish patched code");
        require(function() == 43, "patched code returned another value");
        require(!Os::makeExecutableMemory(code, 0), "empty protection succeeded");
        Os::freeExecutableMemory(code, pageSize);
        expectAccessFault(code, false);
        require(Os::isProximityMemory(code), "freed carve lost its address reservation");
        unsigned char resident = 1;
        require(mincore(code, pageSize, &resident) == 0 && !(resident & 1), "released carve retained physical backing");
        auto* next = static_cast<uint8_t*>(Os::allocProximityMemory(pageSize));
        require(next && next != code, "freed carve was reused");
        Os::freeProximityMemory(next, pageSize);
        Os::freeExecutableMemory(nullptr, 0);
    }

    void testProtectionRange()
    {
        const uint32_t pageSize = Os::memoryPageSize();
        auto*          memory = static_cast<uint8_t*>(Os::allocProximityMemory(3 * pageSize));
        require(memory != nullptr, "cannot allocate page-range fixture");
        require(Os::makeExecutableMemory(memory + pageSize - 1, 2), "cannot protect a range across two pages");
        expectAccessFault(memory + pageSize - 1, true);
        expectAccessFault(memory + pageSize, true);
        memory[2 * pageSize] = 7;
        require(memory[2 * pageSize] == 7, "protection changed the neighboring page");
        expectAccessFault(memory + 3 * pageSize, false);
        Os::freeProximityMemory(memory, 3 * pageSize);
    }

    void testConcurrentCarves()
    {
        constexpr size_t                    count = 96;
        std::array<void*, count>            carves{};
        std::array<std::jthread, 3>          workers;
        const uint32_t                      pageSize = Os::memoryPageSize();
        for (size_t worker = 0; worker < workers.size(); ++worker)
        {
            workers[worker] = std::jthread([&, worker] {
                for (size_t index = worker; index < count; index += workers.size())
                {
                    carves[index] = Os::allocProximityMemory(pageSize + 1);
                    if (carves[index])
                        std::memset(carves[index], static_cast<int>(index), pageSize + 1);
                }
            });
        }
        for (auto& worker : workers)
            worker.join();

        std::set<uintptr_t> addresses;
        for (size_t index = 0; index < count; ++index)
        {
            require(carves[index] && Os::isProximityMemory(carves[index]), "concurrent carve failed");
            const auto* bytes = static_cast<const uint8_t*>(carves[index]);
            require(bytes[0] == index && bytes[pageSize] == index, "concurrent carves overlap");
            addresses.insert(reinterpret_cast<uintptr_t>(carves[index]));
        }
        require(addresses.size() == count, "concurrent carves share an address");
        require(*addresses.rbegin() - *addresses.begin() < (1ull << 31), "carves exceed RIP-relative reach");
        for (void* carve : carves)
            Os::freeProximityMemory(carve, pageSize + 1);
    }

    void testArenaExhaustion()
    {
        // Run before any parent allocation so this child starts with an empty arena.
        const pid_t child = fork();
        if (child == 0)
        {
            constexpr uint32_t arenaSize = 1u << 31;
            void*              arena = Os::allocProximityMemory(arenaSize);
            if (!arena || Os::allocProximityMemory(1))
                _exit(1);
            const uint32_t pageSize = Os::memoryPageSize();
            void*          fallback = Os::allocExecutableMemory(pageSize);
            if (!fallback || Os::isProximityMemory(fallback))
                _exit(2);
            std::memset(fallback, 0xCC, pageSize);
            Os::freeExecutableMemory(fallback, pageSize);
            unsigned char resident = 0;
            if (mincore(fallback, pageSize, &resident) != -1 || errno != ENOMEM)
                _exit(3);
            Os::freeProximityMemory(arena, arenaSize);
            if (!Os::isProximityMemory(arena) || Os::allocProximityMemory(1))
                _exit(4);
            _exit(0);
        }
        const int status = waitForChild(child);
        require(WIFEXITED(status) && WEXITSTATUS(status) == 0, "arena exhaustion/fallback contract failed");
    }

    void writeFile(const fs::path& path, const std::string_view contents)
    {
        std::ofstream file(path, std::ios::binary);
        file.write(contents.data(), static_cast<std::streamsize>(contents.size()));
        file.close();
        require(file.good(), "cannot write mapping fixture");
    }

    bool hasBytes(const Os::ReadOnlyFileMapping& mapping, const std::string_view expected)
    {
        return mapping.bytes().size() == expected.size() && std::memcmp(mapping.bytes().data(), expected.data(), expected.size()) == 0;
    }

    void testFileMappings()
    {
        const fs::path cache = "cache-\xc3\xa9.bin";
        writeFile(cache, std::string_view("old\0bytes", 9));
        writeFile("empty.bin", "");
        require(mkfifo("pipe", 0600) == 0, "cannot create FIFO fixture");

        Os::ReadOnlyFileMapping oldGeneration;
        require(oldGeneration.bytes().empty(), "unopened mapping is not empty");
        require(!oldGeneration.open("missing.bin", 10), "missing file mapped");
        require(!oldGeneration.open("empty.bin", 10), "empty file mapped");
        require(!oldGeneration.open(".", 10), "directory mapped");
        require(!oldGeneration.open("pipe", 10), "FIFO mapped");
        require(!oldGeneration.open(cache, 0) && !oldGeneration.open(cache, 8), "mapping ignored byte limit");
        require(oldGeneration.bytes().empty(), "rejected mapping left a view");
        require(oldGeneration.open(cache, 9), "cannot map binary UTF-8 path after a rejected open");
        require(hasBytes(oldGeneration, std::string_view("old\0bytes", 9)), "mapping changed binary bytes");
        expectAccessFault(const_cast<std::byte*>(oldGeneration.bytes().data()), true);

        writeFile("replacement.bin", "replacement");
        fs::rename("replacement.bin", cache);
        Os::ReadOnlyFileMapping newGeneration;
        require(newGeneration.open(cache, 11), "cannot map replaced file");
        fs::remove(cache);
        require(hasBytes(oldGeneration, std::string_view("old\0bytes", 9)), "replacement changed an existing reader");
        require(hasBytes(newGeneration, "replacement"), "unlink changed an existing reader");

        writeFile(cache, "x");
        const auto descriptorCount = [] { return std::distance(fs::directory_iterator("/proc/self/fd"), fs::directory_iterator{}); };
        const auto before = descriptorCount();
        const void* lastView = nullptr;
        for (size_t i = 0; i < 128; ++i)
        {
            Os::ReadOnlyFileMapping mapping;
            require(!mapping.open(cache, 0) && mapping.open(cache, 1), "mapping retry failed");
            lastView = mapping.bytes().data();
        }
        unsigned char resident = 0;
        require(mincore(const_cast<void*>(lastView), Os::memoryPageSize(), &resident) == -1 && errno == ENOMEM, "mapping destructor retained its view");
        require(descriptorCount() == before, "mapping leaked file descriptors");
    }
}

int main(const int argc, char* argv[])
{
    using namespace swc::LinuxHostTests;
    if (argc > 1)
        return runProcessChild(argc, argv);
    // Protection tests deliberately fault in children; never leave core files behind.
    const rlimit coreLimit{};
    if (setrlimit(RLIMIT_CORE, &coreLimit) != 0)
        return 1;
    try
    {
        testArenaExhaustion();
        std::puts("PASS arena exhaustion and standalone fallback");
        testExecutableMemory();
        std::puts("PASS executable memory, patching and protection");
        testProtectionRange();
        std::puts("PASS page-range protection and reserved guard page");
        testConcurrentCarves();
        std::puts("PASS concurrent proximity allocations");
        testFileMappings();
        std::puts("PASS file mappings, replacement, rejection and cleanup");
        testHostBasics();
        std::puts("PASS host identity, environment and errors");
        testFileServices();
        std::puts("PASS atomic file publication and common I/O");
        testFileOwners();
        std::puts("PASS file users across mappings, aliases and processes");
        testCrossToolchainDiscovery();
        std::puts("PASS explicit Windows cross-toolchain discovery and missing inputs");
        testDirectoryLocks();
        std::puts("PASS directory locks across processes, aliases and replacement");
        testThreadStorage();
        std::puts("PASS thread-local storage isolation and accounting");
        testModuleLoading();
        std::puts("PASS shared-library search, exports and C calls");
        testTerminal();
        std::puts("PASS terminal capabilities, redirection and cursor restoration");
        testCallStacks();
        std::puts("PASS native stack capture, frame skipping and ELF symbols");
        testGeneratedUnwind();
        std::puts("PASS generated DWARF frames, C++ cleanup and registration lifetime");
        testFaultHandlerStacks();
        std::puts("PASS signal stacks, thread cleanup and actual stack overflow");
        testProcessOutput();
        std::puts("PASS process output capture, observation and filtering");
        testProcessServices();
        std::puts("PASS process arguments, deadlines, descendants and caller death");
        return 0;
    }
    catch (const std::exception& error)
    {
        std::fprintf(stderr, "FAIL %s\n", error.what());
        return 1;
    }
}
