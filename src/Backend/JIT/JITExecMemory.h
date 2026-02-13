#pragma once
#include "Support/Core/ByteSpan.h"
#include <bit>
#include <cstdint>
#include <type_traits>

SWC_BEGIN_NAMESPACE();

namespace Backend
{
    class JITExecMemory
    {
    public:
        JITExecMemory() = default;
        ~JITExecMemory();

        JITExecMemory(const JITExecMemory&)            = delete;
        JITExecMemory& operator=(const JITExecMemory&) = delete;
        JITExecMemory(JITExecMemory&& other) noexcept;
        JITExecMemory& operator=(JITExecMemory&& other) noexcept;

        void     reset();
        bool     allocateAndCopy(ByteSpan bytes);
        uint32_t size() const { return size_; }
        bool     empty() const { return ptr_ == nullptr; }

        template<typename T>
        T entryPoint() const
        {
            static_assert(std::is_pointer_v<T>);
            return std::bit_cast<T>(ptr_);
        }

    private:
        void*    ptr_  = nullptr;
        uint32_t size_ = 0;
    };
}

SWC_END_NAMESPACE();
