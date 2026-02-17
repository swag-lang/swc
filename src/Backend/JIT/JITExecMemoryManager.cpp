#include "pch.h"
#include "Backend/JIT/JITExecMemoryManager.h"
#include "Support/Os/Os.h"

SWC_BEGIN_NAMESPACE();

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

JITExecMemoryManager::~JITExecMemoryManager()
{
    std::unique_lock lock(mutex_);
    for (const auto& block : blocks_)
    {
        if (block.ptr)
            Os::freeExecutableMemory(block.ptr);
    }
    blocks_.clear();
}

bool JITExecMemoryManager::allocate(JITExecMemory& outExecutableMemory, uint32_t size)
{
    outExecutableMemory.reset();
    if (!size)
        return false;

    const uint32_t pageSize = executablePageSize();
    SWC_ASSERT(size <= std::numeric_limits<uint32_t>::max() - (pageSize - 1));
    const uint32_t requestSize      = size;
    const uint32_t requestSizeAlign = alignUp(requestSize, pageSize);

    std::unique_lock lock(mutex_);

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
        const auto blockSize = std::max(DEFAULT_BLOCK_SIZE, alignUp(requestSizeAlign, pageSize));
        auto*      ptr       = Os::allocExecutableMemory(blockSize);
        if (!ptr)
            return false;

        blocks_.push_back({.ptr = ptr, .size = blockSize, .allocated = 0});
        targetBlock = &blocks_.back();
    }

    SWC_ASSERT(targetBlock);
    auto* const dst = static_cast<std::byte*>(targetBlock->ptr) + targetBlock->allocated;
    targetBlock->allocated += requestSizeAlign;

    outExecutableMemory.ptr_            = dst;
    outExecutableMemory.size_           = requestSize;
    outExecutableMemory.allocationSize_ = requestSizeAlign;
    return true;
}

bool JITExecMemoryManager::makeExecutable(const JITExecMemory& executableMemory)
{
    if (executableMemory.empty())
        return false;

    SWC_ASSERT(executableMemory.allocationSize_ >= executableMemory.size_);
    return Os::makeExecutableMemory(executableMemory.ptr_, executableMemory.allocationSize_);
}

bool JITExecMemoryManager::allocateAndCopy(JITExecMemory& outExecutableMemory, ByteSpan bytes)
{
    outExecutableMemory.reset();
    SWC_ASSERT(bytes.data() || bytes.empty());
    if (bytes.empty())
        return false;

    SWC_ASSERT(bytes.size() <= std::numeric_limits<uint32_t>::max());
    const auto requestSize = static_cast<uint32_t>(bytes.size());
    if (!allocate(outExecutableMemory, requestSize))
        return false;

    std::memcpy(outExecutableMemory.ptr_, bytes.data(), bytes.size());
    if (!makeExecutable(outExecutableMemory))
    {
        outExecutableMemory.reset();
        return false;
    }

    return true;
}

SWC_END_NAMESPACE();
