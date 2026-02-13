#pragma once
#include <bit>
#include <cstdint>
#include <type_traits>

SWC_BEGIN_NAMESPACE();

namespace Backend
{
    class JitExecutableMemory
    {
    public:
        JitExecutableMemory() = default;
        ~JitExecutableMemory();

        JitExecutableMemory(const JitExecutableMemory&)                = delete;
        JitExecutableMemory& operator=(const JitExecutableMemory&)     = delete;
        JitExecutableMemory(JitExecutableMemory&& other) noexcept;
        JitExecutableMemory& operator=(JitExecutableMemory&& other) noexcept;

        void     reset();
        bool     allocateAndCopy(const uint8_t* data, uint32_t size);
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
