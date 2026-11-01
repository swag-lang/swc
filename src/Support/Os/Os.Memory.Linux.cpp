#include "pch.h"
#include "Support/Os/Os.h"
#include "Support/Report/Assert.h"

#ifdef __linux__
#include <fcntl.h>
#include <sys/mman.h>
#include <sys/uio.h>
#include <unistd.h>

SWC_BEGIN_NAMESPACE();

namespace
{
    bool tryReadProcMemory(const std::span<std::byte> outBytes, const void* address)
    {
        // /proc/self/mem can bypass PROT_NONE. Preserve ordinary readable-page semantics
        // before using it on kernels/sandboxes without process_vm_readv. Mapping changes
        // can still make pread fail, but cannot raise a signal in the diagnostic reporter.
        uintptr_t cursor = reinterpret_cast<uintptr_t>(address);
        if (cursor > static_cast<uintptr_t>(std::numeric_limits<off_t>::max()) - outBytes.size())
            return false;
        const uintptr_t limit = cursor + outBytes.size();
        std::ifstream maps("/proc/self/maps");
        std::string line;
        while (cursor < limit && std::getline(maps, line))
        {
            unsigned long long start = 0, end = 0;
            char permissions[5]{};
            if (std::sscanf(line.c_str(), "%llx-%llx %4s", &start, &end, permissions) != 3 || end <= cursor)
                continue;
            if (start > cursor || permissions[0] != 'r')
                return false;
            cursor = std::min<uintptr_t>(limit, end);
        }
        if (cursor != limit)
            return false;
        const int memory = open("/proc/self/mem", O_RDONLY | O_CLOEXEC);
        if (memory < 0)
            return false;
        ssize_t count;
        do
            count = pread(memory, outBytes.data(), outBytes.size(), static_cast<off_t>(reinterpret_cast<uintptr_t>(address)));
        while (count < 0 && errno == EINTR);
        const int error = errno;
        close(memory);
        errno = error;
        return count >= 0 && static_cast<size_t>(count) == outBytes.size();
    }
}

bool Os::tryReadMemory(const std::span<std::byte> outBytes, const void* address)
{
    if (outBytes.empty())
        return true;
    if (outBytes.size() > static_cast<size_t>(std::numeric_limits<ssize_t>::max()))
        return false;
    const iovec local{outBytes.data(), outBytes.size()};
    const iovec remote{const_cast<void*>(address), outBytes.size()};
    ssize_t count;
    do
        count = process_vm_readv(getpid(), &local, 1, &remote, 1, 0);
    while (count < 0 && errno == EINTR);
    if (count < 0 && (errno == ENOSYS || errno == EPERM))
        return tryReadProcMemory(outBytes, address);
    return count >= 0 && static_cast<size_t>(count) == outBytes.size();
}

namespace
{
    // Keep JIT code and compile-time globals within a signed RIP-relative displacement.
    // Released carves keep their addresses reserved for the lifetime of the compiler.
    constexpr uint64_t K_PROXIMITY_RESERVE = 1ull << 31;

    struct ProximityArena
    {
        std::mutex            mutex;
        std::atomic<uint8_t*> base{nullptr};
        uint64_t              used = 0;
    };

    ProximityArena g_proximityArena;

    bool protectMemory(void* ptr, const uint32_t size, const int protection)
    {
        if (!ptr || !size)
            return false;

        // VirtualProtect accepts byte ranges; mprotect needs a page-aligned start.
        const auto     address  = reinterpret_cast<uintptr_t>(ptr);
        const uint64_t pageSize = Os::memoryPageSize();
        const auto     start    = address & ~(pageSize - 1);
        if (address > std::numeric_limits<uintptr_t>::max() - size)
            return false;
        return mprotect(reinterpret_cast<void*>(start), address - start + size, protection) == 0;
    }
}

uint32_t Os::memoryPageSize()
{
    static const long size = sysconf(_SC_PAGESIZE);
    SWC_ASSERT(size > 0 && static_cast<uint64_t>(size) <= std::numeric_limits<uint32_t>::max());
    return static_cast<uint32_t>(size);
}

void* Os::allocProximityMemory(const uint32_t size)
{
    if (!size || size > K_PROXIMITY_RESERVE)
        return nullptr;

    const std::scoped_lock lock(g_proximityArena.mutex);
    auto&                 arena = g_proximityArena;
    if (!arena.base.load(std::memory_order_relaxed))
    {
        void* base = mmap(nullptr, K_PROXIMITY_RESERVE, PROT_NONE, MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
        if (base == MAP_FAILED)
            return nullptr;
        arena.base.store(static_cast<uint8_t*>(base), std::memory_order_release);
    }

    const uint64_t pageSize = memoryPageSize();
    const uint64_t aligned  = (static_cast<uint64_t>(size) + pageSize - 1) & ~(pageSize - 1);
    if (aligned > K_PROXIMITY_RESERVE - arena.used)
        return nullptr;

    uint8_t* result = arena.base.load(std::memory_order_relaxed) + arena.used;
    if (mprotect(result, aligned, PROT_READ | PROT_WRITE) != 0)
        return nullptr;
    arena.used += aligned;
    return result;
}

bool Os::isProximityMemory(const void* ptr)
{
    const auto base    = reinterpret_cast<uintptr_t>(g_proximityArena.base.load(std::memory_order_acquire));
    const auto address = reinterpret_cast<uintptr_t>(ptr);
    return base && address >= base && address - base < K_PROXIMITY_RESERVE;
}

void Os::freeProximityMemory(void* ptr, const uint32_t size)
{
    SWC_ASSERT(ptr && size && isProximityMemory(ptr));
    const bool protectedPages = protectMemory(ptr, size, PROT_NONE);
    SWC_ASSERT(protectedPages);
    if (!protectedPages)
        return;

    // Drop physical backing without opening a hole that an unrelated mapping could reuse.
    const int discarded = madvise(ptr, size, MADV_DONTNEED);
    SWC_ASSERT(discarded == 0);
    SWC_UNUSED(discarded);
}

void* Os::allocExecutableMemory(const uint32_t size)
{
    if (!size)
        return nullptr;
    if (void* proximity = allocProximityMemory(size))
        return proximity;

    void* ptr = mmap(nullptr, size, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
    return ptr == MAP_FAILED ? nullptr : ptr;
}

bool Os::makeWritableExecutableMemory(void* ptr, const uint32_t size)
{
    // Existing JIT patching keeps published code executable while rewriting it.
    return protectMemory(ptr, size, PROT_READ | PROT_WRITE | PROT_EXEC);
}

bool Os::makeExecutableMemory(void* ptr, const uint32_t size)
{
    if (!protectMemory(ptr, size, PROT_READ | PROT_EXEC))
        return false;
    __builtin___clear_cache(static_cast<char*>(ptr), static_cast<char*>(ptr) + size);
    return true;
}

void Os::freeExecutableMemory(void* ptr, const uint32_t size)
{
    if (!ptr)
        return;
    if (isProximityMemory(ptr))
    {
        freeProximityMemory(ptr, size);
        return;
    }

    const int released = munmap(ptr, size);
    SWC_ASSERT(released == 0);
    SWC_UNUSED(released);
}

SWC_END_NAMESPACE();
#endif
