#include "pch.h"
#include "Backend/JIT/JITMemory.h"

SWC_BEGIN_NAMESPACE();

JITMemory::~JITMemory()
{
    reset();
}

JITMemory::JITMemory(JITMemory&& other) noexcept :
    ptr_(other.ptr_),
    size_(other.size_),
    allocationSize_(other.allocationSize_),
    unwindInfoOffset_(other.unwindInfoOffset_),
    unwindInfoSize_(other.unwindInfoSize_),
    hostRuntimeFunction_(other.hostRuntimeFunction_)
{
    other.ptr_                 = nullptr;
    other.size_                = 0;
    other.allocationSize_      = 0;
    other.unwindInfoOffset_    = 0;
    other.unwindInfoSize_      = 0;
    other.hostRuntimeFunction_ = nullptr;
}

JITMemory& JITMemory::operator=(JITMemory&& other) noexcept
{
    if (this != &other)
    {
        reset();

        ptr_                       = other.ptr_;
        size_                      = other.size_;
        allocationSize_            = other.allocationSize_;
        unwindInfoOffset_          = other.unwindInfoOffset_;
        unwindInfoSize_            = other.unwindInfoSize_;
        hostRuntimeFunction_       = other.hostRuntimeFunction_;
        other.ptr_                 = nullptr;
        other.size_                = 0;
        other.allocationSize_      = 0;
        other.unwindInfoOffset_    = 0;
        other.unwindInfoSize_      = 0;
        other.hostRuntimeFunction_ = nullptr;
    }

    return *this;
}

void JITMemory::reset()
{
    Os::removeHostJitFunctionTable(*this);

    ptr_                 = nullptr;
    size_                = 0;
    allocationSize_      = 0;
    unwindInfoOffset_    = 0;
    unwindInfoSize_      = 0;
    hostRuntimeFunction_ = nullptr;
}

SWC_END_NAMESPACE();
