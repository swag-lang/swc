#include "pch.h"
#include "Backend/JIT/JITMemoryManager.h"
#include "Support/Os/Os.h"

SWC_BEGIN_NAMESPACE();

static constexpr uint32_t DEFAULT_BLOCK_SIZE = 64 * 1024;

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
        if (block->ptr)
            Os::freeExecutableMemory(block->ptr);
    }

    blocks_.clear();
    currentBlock_.store(nullptr, std::memory_order_relaxed);
}

bool JITMemoryManager::tryAllocateFromBlock(std::byte*& outPtr, Block& block, const uint32_t allocationSize)
{
    uint32_t allocated = block.allocated.load(std::memory_order_relaxed);
    while (allocated <= block.size && block.size - allocated >= allocationSize)
    {
        const uint32_t newAllocated = allocated + allocationSize;
        if (block.allocated.compare_exchange_weak(allocated, newAllocated, std::memory_order_acq_rel, std::memory_order_relaxed))
        {
            outPtr = static_cast<std::byte*>(block.ptr) + allocated;
            return true;
        }
    }

    return false;
}

std::byte* JITMemoryManager::allocateSlow(const uint32_t allocationSize)
{
    std::byte* dst = nullptr;
    {
        const std::unique_lock lock(mutex_);
        for (const auto& block : blocks_)
        {
            if (tryAllocateFromBlock(dst, *block, allocationSize))
            {
                currentBlock_.store(block.get(), std::memory_order_release);
                return dst;
            }
        }

        const uint32_t blockSize = std::max(DEFAULT_BLOCK_SIZE, allocationSize);
        void*          ptr       = Os::allocExecutableMemory(blockSize);
        SWC_ASSERT(ptr);

        auto block = std::make_unique<Block>();
        block->ptr  = ptr;
        block->size = blockSize;

        Block* const blockPtr = block.get();
        blocks_.push_back(std::move(block));
        const bool allocated = tryAllocateFromBlock(dst, *blockPtr, allocationSize);
        SWC_ASSERT(allocated);
        currentBlock_.store(blockPtr, std::memory_order_release);
    }

    return dst;
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

    std::byte* dst = nullptr;
    if (Block* const block = currentBlock_.load(std::memory_order_acquire))
    {
        if (!tryAllocateFromBlock(dst, *block, requestSizeAlign))
            dst = nullptr;
    }

    if (!dst)
        dst = allocateSlow(requestSizeAlign);

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
