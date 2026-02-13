#include "pch.h"
#include "Backend/Jit/JitExecutableMemory.h"
#include "Support/Os/Os.h"

SWC_BEGIN_NAMESPACE();

namespace Backend
{
    JitExecutableMemory::~JitExecutableMemory()
    {
        reset();
    }

    JitExecutableMemory::JitExecutableMemory(JitExecutableMemory&& other) noexcept :
        ptr_(other.ptr_),
        size_(other.size_)
    {
        other.ptr_  = nullptr;
        other.size_ = 0;
    }

    JitExecutableMemory& JitExecutableMemory::operator=(JitExecutableMemory&& other) noexcept
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

    void JitExecutableMemory::reset()
    {
        if (ptr_)
            Os::freeExecutableMemory(ptr_);
        ptr_  = nullptr;
        size_ = 0;
    }

    bool JitExecutableMemory::allocateAndCopy(const uint8_t* data, uint32_t size)
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
