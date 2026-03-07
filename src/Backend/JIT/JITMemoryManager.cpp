#include "pch.h"
#include "Backend/JIT/JITMemoryManager.h"
#if SWC_HAS_STATS
#include "Main/Stats.h"
#endif
#include "Support/Os/Os.h"

SWC_BEGIN_NAMESPACE();

static constexpr uint32_t DEFAULT_BLOCK_SIZE = 4 * 1024;

namespace
{
    uint32_t alignUp(uint32_t value, uint32_t alignment)
    {
        SWC_ASSERT(alignment != 0);
        return (value + alignment - 1) & ~(alignment - 1);
    }

    uint32_t executablePageSize()
    {
        static const uint32_t PAGE_SIZE = Os::memoryPageSize();
        SWC_ASSERT(PAGE_SIZE != 0);
        SWC_ASSERT((PAGE_SIZE & (PAGE_SIZE - 1)) == 0);
        return PAGE_SIZE;
    }
}

JITMemoryManager::~JITMemoryManager()
{
    const std::unique_lock lock(mutex_);
    for (const auto& block : blocks_)
    {
        if (block.ptr)
            Os::freeExecutableMemory(block.ptr);
    }

    blocks_.clear();
}

void JITMemoryManager::allocateWithCodeSize(JITMemory& outExecutableMemory, const uint32_t allocationSize, const uint32_t codeSize)
{
    outExecutableMemory.reset();
    SWC_ASSERT(allocationSize);
    SWC_ASSERT(codeSize <= allocationSize);

    const uint32_t pageSize = executablePageSize();
    SWC_ASSERT(allocationSize <= std::numeric_limits<uint32_t>::max() - (pageSize - 1));
    const uint32_t requestSize      = allocationSize;
    const uint32_t requestSizeAlign = alignUp(requestSize, pageSize);

    const std::unique_lock lock(mutex_);

    Block* targetBlock = nullptr;
    for (auto& block : blocks_)
    {
        if (block.size - block.allocated >= requestSizeAlign)
        {
            targetBlock = &block;
            break;
        }
    }

    if (!targetBlock)
    {
        const uint32_t blockSize = std::max(DEFAULT_BLOCK_SIZE, alignUp(requestSizeAlign, pageSize));
        void*          ptr       = Os::allocExecutableMemory(blockSize);
        SWC_ASSERT(ptr);

        blocks_.push_back({.ptr = ptr, .size = blockSize, .allocated = 0});
#if SWC_HAS_STATS
        Stats::get().memJitReserved.fetch_add(blockSize, std::memory_order_relaxed);
#endif
        targetBlock = &blocks_.back();
    }

    SWC_ASSERT(targetBlock);
    std::byte* const dst = static_cast<std::byte*>(targetBlock->ptr) + targetBlock->allocated;
    targetBlock->allocated += requestSizeAlign;

    outExecutableMemory.ptr_              = dst;
    outExecutableMemory.size_             = codeSize;
    outExecutableMemory.allocationSize_   = requestSizeAlign;
    outExecutableMemory.unwindInfoOffset_ = 0;
    outExecutableMemory.unwindInfoSize_   = 0;
}

void JITMemoryManager::allocate(JITMemory& outExecutableMemory, uint32_t size)
{
    allocateWithCodeSize(outExecutableMemory, size, size);
}

void JITMemoryManager::registerUnwindInfo(JITMemory& executableMemory)
{
    if (!executableMemory.hasUnwindInfo())
        return;
    SWC_FORCE_ASSERT(Os::addHostJitFunctionTable(executableMemory));
}

void JITMemoryManager::makeExecutable(const JITMemory& executableMemory)
{
    SWC_ASSERT(!executableMemory.empty());
    SWC_ASSERT(executableMemory.allocationSize_ >= executableMemory.size_);
    SWC_FORCE_ASSERT(Os::makeExecutableMemory(executableMemory.ptr_, executableMemory.allocationSize_));
}

void JITMemoryManager::allocateAndCopy(JITMemory& outExecutableMemory, ByteSpan bytes)
{
    outExecutableMemory.reset();

    SWC_ASSERT(bytes.data() || bytes.empty());
    SWC_ASSERT(!bytes.empty());
    SWC_ASSERT(bytes.size() <= std::numeric_limits<uint32_t>::max());

    const uint32_t requestSize = static_cast<uint32_t>(bytes.size());
    allocateWithCodeSize(outExecutableMemory, requestSize, requestSize);

    std::memcpy(outExecutableMemory.ptr_, bytes.data(), bytes.size());
    makeExecutable(outExecutableMemory);
}

SWC_END_NAMESPACE();
