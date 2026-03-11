#pragma once

SWC_BEGIN_NAMESPACE();

class JITMemory;

namespace Os
{
    bool addHostJitFunctionTable(JITMemory& executableMemory);
    void removeHostJitFunctionTable(JITMemory& executableMemory);
}

class JITMemory
{
public:
    JITMemory() noexcept = default;
    ~JITMemory();

    JITMemory(const JITMemory&)            = delete;
    JITMemory& operator=(const JITMemory&) = delete;
    JITMemory(JITMemory&& other) noexcept;
    JITMemory& operator=(JITMemory&& other) noexcept;

    void     reset();
    uint32_t size() const { return size_; }
    bool     empty() const { return ptr_ == nullptr; }
    void*    entryPoint() const { return ptr_; }
    bool     hasUnwindInfo() const { return unwindInfoSize_ != 0; }

private:
    friend bool Os::addHostJitFunctionTable(JITMemory& executableMemory);
    friend void Os::removeHostJitFunctionTable(JITMemory& executableMemory);
    friend class JIT;
    friend class JITMemoryManager;

    void*    ptr_                 = nullptr;
    uint32_t size_                = 0;
    uint32_t allocationSize_      = 0;
    uint32_t unwindInfoOffset_    = 0;
    uint32_t unwindInfoSize_      = 0;
    void*    hostRuntimeFunction_ = nullptr;
};

SWC_END_NAMESPACE();
