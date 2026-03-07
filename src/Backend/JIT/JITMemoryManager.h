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

    void        allocateWithCodeSize(JITMemory& outExecutableMemory, uint32_t allocationSize, uint32_t codeSize);
    void        allocate(JITMemory& outExecutableMemory, uint32_t size);
    static void registerUnwindInfo(JITMemory& executableMemory);
    static void makeExecutable(const JITMemory& executableMemory);
    void        allocateAndCopy(JITMemory& outExecutableMemory, ByteSpan bytes);

private:
    struct Block
    {
        void*    ptr       = nullptr;
        uint32_t size      = 0;
        uint32_t allocated = 0;
    };

    std::mutex         mutex_;
    std::vector<Block> blocks_;
};

SWC_END_NAMESPACE();
