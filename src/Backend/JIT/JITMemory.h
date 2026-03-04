#pragma once

SWC_BEGIN_NAMESPACE();

class JITMemory
{
public:
    JITMemory()  = default;
    ~JITMemory() = default;

    JITMemory(const JITMemory&)            = default;
    JITMemory& operator=(const JITMemory&) = default;
    JITMemory(JITMemory&& other) noexcept;
    JITMemory& operator=(JITMemory&& other) noexcept;

    void     reset();
    uint32_t size() const { return size_; }
    bool     empty() const { return ptr_ == nullptr; }
    void*    entryPoint() const { return ptr_; }
    bool     hasUnwindInfo() const { return unwindInfoSize_ != 0; }

private:
    friend class JIT;
    friend class JITMemoryManager;

    void*    ptr_              = nullptr;
    uint32_t size_             = 0;
    uint32_t allocationSize_   = 0;
    uint32_t unwindInfoOffset_ = 0;
    uint32_t unwindInfoSize_   = 0;
};

SWC_END_NAMESPACE();
