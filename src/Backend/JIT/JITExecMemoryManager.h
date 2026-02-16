#pragma once
#include "Backend/JIT/JITExecMemory.h"
#include "Support/Core/ByteSpan.h"

SWC_BEGIN_NAMESPACE();

class JITExecMemoryManager
{
public:
    JITExecMemoryManager() = default;
    ~JITExecMemoryManager();

    JITExecMemoryManager(const JITExecMemoryManager&)            = delete;
    JITExecMemoryManager& operator=(const JITExecMemoryManager&) = delete;

    bool allocate(JITExecMemory& outExecutableMemory, uint32_t size);
    bool makeExecutable(const JITExecMemory& executableMemory);
    bool allocateAndCopy(JITExecMemory& outExecutableMemory, ByteSpan bytes);

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
