#pragma once
#include "Support/Core/ByteSpan.h"
#include <mutex>
#include <vector>

SWC_BEGIN_NAMESPACE();

class JITExecMemory
{
public:
    JITExecMemory() = default;
    ~JITExecMemory() = default;

    JITExecMemory(const JITExecMemory&)            = default;
    JITExecMemory& operator=(const JITExecMemory&) = default;
    JITExecMemory(JITExecMemory&& other) noexcept;
    JITExecMemory& operator=(JITExecMemory&& other) noexcept;

    void     reset();
    uint32_t size() const { return size_; }
    bool     empty() const { return ptr_ == nullptr; }

    template<typename T>
    T entryPoint() const
    {
        static_assert(std::is_pointer_v<T>);
        return std::bit_cast<T>(ptr_);
    }

private:
    friend class JITExecMemoryManager;

    void*    ptr_  = nullptr;
    uint32_t size_ = 0;
};

class JITExecMemoryManager
{
public:
    JITExecMemoryManager() = default;
    ~JITExecMemoryManager();

    JITExecMemoryManager(const JITExecMemoryManager&)            = delete;
    JITExecMemoryManager& operator=(const JITExecMemoryManager&) = delete;

    bool allocateAndCopy(ByteSpan bytes, JITExecMemory& outExecutableMemory);

private:
    struct Block
    {
        void*    ptr      = nullptr;
        uint32_t size     = 0;
        uint32_t allocated = 0;
    };

    static constexpr uint32_t defaultBlockSize = 64 * 1024;

    std::mutex         mutex_;
    std::vector<Block> blocks_;
};

SWC_END_NAMESPACE();
