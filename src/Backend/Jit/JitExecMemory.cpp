#include "pch.h"
#include "Backend/Jit/JitExecMemory.h"
#include "Support/Os/Os.h"

SWC_BEGIN_NAMESPACE();

namespace Backend
{
    JitExecMemory::~JitExecMemory()
    {
        reset();
    }

    JitExecMemory::JitExecMemory(JitExecMemory&& other) noexcept :
        ptr_(other.ptr_),
        size_(other.size_)
    {
        other.ptr_  = nullptr;
        other.size_ = 0;
    }

    JitExecMemory& JitExecMemory::operator=(JitExecMemory&& other) noexcept
    {
        if (this != &other)
        {
            reset();
            ptr_        = other.ptr_;
            size_       = other.size_;
            other.ptr_  = nullptr;
            other.size_ = 0;
        }

        return *this;
    }

    void JitExecMemory::reset()
    {
        if (ptr_)
            Os::freeExecutableMemory(ptr_);
        ptr_  = nullptr;
        size_ = 0;
    }

    bool JitExecMemory::allocateAndCopy(const uint8_t* data, uint32_t size)
    {
        reset();
        if (!data || !size)
            return false;

        ptr_ = Os::allocExecutableMemory(size);
        if (!ptr_)
            return false;

        std::memcpy(ptr_, data, size);
        if (!Os::makeExecutableMemory(ptr_, size))
        {
            reset();
            return false;
        }

        size_ = size;
        return true;
    }
}

SWC_END_NAMESPACE();
