#include "pch.h"
#include "Backend/JIT/JITExecMemory.h"

SWC_BEGIN_NAMESPACE();

JITExecMemory::JITExecMemory(JITExecMemory&& other) noexcept :
    ptr_(other.ptr_),
    size_(other.size_),
    allocationSize_(other.allocationSize_)
{
    other.ptr_            = nullptr;
    other.size_           = 0;
    other.allocationSize_ = 0;
}

JITExecMemory& JITExecMemory::operator=(JITExecMemory&& other) noexcept
{
    if (this != &other)
    {
        ptr_                  = other.ptr_;
        size_                 = other.size_;
        allocationSize_       = other.allocationSize_;
        other.ptr_            = nullptr;
        other.size_           = 0;
        other.allocationSize_ = 0;
    }

    return *this;
}

void JITExecMemory::reset()
{
    ptr_            = nullptr;
    size_           = 0;
    allocationSize_ = 0;
}

SWC_END_NAMESPACE();
