#pragma once
#include "Backend/MachineCode/Micro/MicroInstrBuilder.h"
#include "Support/Core/Result.h"
#include <bit>
#include <cstdint>
#include <functional>
#include <type_traits>

SWC_BEGIN_NAMESPACE();

class TaskContext;

namespace Backend::Jit
{
    class ExecutableMemory
    {
    public:
        ExecutableMemory() = default;
        ~ExecutableMemory();

        ExecutableMemory(const ExecutableMemory&)                = delete;
        ExecutableMemory& operator=(const ExecutableMemory&)     = delete;
        ExecutableMemory(ExecutableMemory&& other) noexcept;
        ExecutableMemory& operator=(ExecutableMemory&& other) noexcept;

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

    class X64Jit final
    {
    public:
        static Result compile(TaskContext& ctx, const std::function<void(MicroInstrBuilder&)>& buildFn, ExecutableMemory& outExecutableMemory);
        static Result compile(TaskContext& ctx, MicroInstrBuilder& builder, ExecutableMemory& outExecutableMemory);
    };
}

SWC_END_NAMESPACE();
