#pragma once

SWC_BEGIN_NAMESPACE();

class JITExecMemory
{
public:
    JITExecMemory()  = default;
    ~JITExecMemory() = default;

    JITExecMemory(const JITExecMemory&)            = default;
    JITExecMemory& operator=(const JITExecMemory&) = default;
    JITExecMemory(JITExecMemory&& other) noexcept;
    JITExecMemory& operator=(JITExecMemory&& other) noexcept;

    void     reset();
    uint32_t size() const { return size_; }
    bool     empty() const { return ptr_ == nullptr; }
    void*    entryPoint() const { return ptr_; }

private:
    friend class JITExecMemoryManager;

    void*    ptr_  = nullptr;
    uint32_t size_ = 0;
};

SWC_END_NAMESPACE();
