#pragma once
#include "Backend/JIT/JITMemory.h"
#include "Support/Core/ByteSpan.h"

SWC_BEGIN_NAMESPACE();

class JITMemoryManager
{
public:
    JITMemoryManager() = default;
    ~JITMemoryManager();

    JITMemoryManager(const JITMemoryManager&)            = delete;
    JITMemoryManager& operator=(const JITMemoryManager&) = delete;

    bool        allocate(JITMemory& outExecutableMemory, uint32_t size);
    static bool makeExecutable(const JITMemory& executableMemory);
    bool        allocateAndCopy(JITMemory& outExecutableMemory, ByteSpan bytes);

private:
    struct Block
    {
        void*    ptr       = nullptr;
        uint32_t size      = 0;
        uint32_t allocated = 0;
    };

    static constexpr uint32_t DEFAULT_BLOCK_SIZE = 64 * 1024;

    std::mutex         mutex_;
    std::vector<Block> blocks_;
};

SWC_END_NAMESPACE();
