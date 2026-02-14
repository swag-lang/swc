#include "pch.h"
#include "Backend/JIT/JITExecMemory.h"
#include "Support/Os/Os.h"

SWC_BEGIN_NAMESPACE();

JITExecMemory::JITExecMemory(JITExecMemory&& other) noexcept :
    ptr_(other.ptr_),
    size_(other.size_)
{
    other.ptr_  = nullptr;
    other.size_ = 0;
}

JITExecMemory& JITExecMemory::operator=(JITExecMemory&& other) noexcept
{
    if (this != &other)
    {
        ptr_        = other.ptr_;
        size_       = other.size_;
        other.ptr_  = nullptr;
        other.size_ = 0;
    }

    return *this;
}

void JITExecMemory::reset()
{
    ptr_  = nullptr;
    size_ = 0;
}

namespace
{
    uint32_t alignUp(uint32_t value, uint32_t alignment)
    {
        SWC_ASSERT(alignment != 0);
        return (value + alignment - 1) & ~(alignment - 1);
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

bool JITExecMemoryManager::allocateAndCopy(ByteSpan bytes, JITExecMemory& outExecutableMemory)
{
    outExecutableMemory.reset();
    SWC_ASSERT(bytes.data() || bytes.empty());
    if (bytes.empty())
        return false;

    SWC_ASSERT(bytes.size() <= std::numeric_limits<uint32_t>::max());
    const auto requestSize = static_cast<uint32_t>(bytes.size());

    std::unique_lock lock(mutex_);

    Block* targetBlock = nullptr;
    for (auto& block : blocks_)
    {
        if (block.size - block.allocated >= requestSize)
        {
            targetBlock = &block;
            break;
        }
    }

    if (!targetBlock)
    {
        const auto blockSize = std::max(defaultBlockSize, alignUp(requestSize, 4096));
        auto*      ptr       = Os::allocExecutableMemory(blockSize);
        if (!ptr)
            return false;

        blocks_.push_back({.ptr = ptr, .size = blockSize, .allocated = 0});
        targetBlock = &blocks_.back();
    }

    SWC_ASSERT(targetBlock);
    if (!Os::makeWritableExecutableMemory(targetBlock->ptr, targetBlock->size))
        return false;

    auto* dst = static_cast<std::byte*>(targetBlock->ptr) + targetBlock->allocated;
    std::memcpy(dst, bytes.data(), bytes.size());

    const auto newAllocated = targetBlock->allocated + requestSize;
    if (!Os::makeExecutableMemory(targetBlock->ptr, newAllocated))
        return false;

    targetBlock->allocated    = newAllocated;
    outExecutableMemory.ptr_  = dst;
    outExecutableMemory.size_ = requestSize;
    return true;
}

SWC_END_NAMESPACE();
