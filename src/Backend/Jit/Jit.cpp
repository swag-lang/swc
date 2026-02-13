#include "pch.h"
#include "Backend/Jit/Jit.h"
#include "Backend/MachineCode/Encoder/X64Encoder.h"
#include "Backend/MachineCode/Micro/Passes/MicroEncodePass.h"
#include "Backend/MachineCode/Micro/Passes/MicroPass.h"
#include "Support/Os/Os.h"

SWC_BEGIN_NAMESPACE();

namespace Backend::Jit
{
    ExecutableMemory::~ExecutableMemory()
    {
        reset();
    }

    ExecutableMemory::ExecutableMemory(ExecutableMemory&& other) noexcept :
        ptr_(other.ptr_),
        size_(other.size_)
    {
        other.ptr_  = nullptr;
        other.size_ = 0;
    }

    ExecutableMemory& ExecutableMemory::operator=(ExecutableMemory&& other) noexcept
    {
        if (this != &other)
        {
            reset();
            ptr_       = other.ptr_;
            size_      = other.size_;
            other.ptr_ = nullptr;
            other.size_ = 0;
        }

        return *this;
    }

    void ExecutableMemory::reset()
    {
        if (ptr_)
            Os::freeExecutableMemory(ptr_);
        ptr_  = nullptr;
        size_ = 0;
    }

    bool ExecutableMemory::allocateAndCopy(const uint8_t* data, uint32_t size)
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

    Result X64Jit::compile(TaskContext& ctx, const std::function<void(MicroInstrBuilder&)>& buildFn, ExecutableMemory& outExecutableMemory)
    {
        MicroInstrBuilder builder(ctx);
        buildFn(builder);
        return compile(ctx, builder, outExecutableMemory);
    }

    Result X64Jit::compile(TaskContext& ctx, MicroInstrBuilder& builder, ExecutableMemory& outExecutableMemory)
    {
#if defined(_M_X64)
        X64Encoder      encoder(ctx);
        MicroEncodePass encodePass;
        MicroPassManager passManager;
        passManager.add(encodePass);

        MicroPassContext passContext;
        builder.runPasses(passManager, &encoder, passContext);
        if (!encoder.size())
            return Result::Error;

        if (!outExecutableMemory.allocateAndCopy(encoder.data(), encoder.size()))
            return Result::Error;

        return Result::Continue;
#else
        (void) ctx;
        (void) builder;
        (void) outExecutableMemory;
        return Result::Error;
#endif
    }
}

SWC_END_NAMESPACE();
