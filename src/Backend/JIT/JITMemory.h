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

private:
    friend class JITMemoryManager;

    void*    ptr_            = nullptr;
    uint32_t size_           = 0;
    uint32_t allocationSize_ = 0;
};

SWC_END_NAMESPACE();
