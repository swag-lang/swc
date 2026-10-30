#include "pch.h"

#if SWC_HAS_UNITTEST

#include "Unittest/Unittest.h"

SWC_BEGIN_NAMESPACE();

SWC_TEST_BEGIN(Allocator_AlignedBlocksSurviveAllocatingThreadExit)
{
    constexpr std::array<size_t, 8>                     sizes{0, 1, 8, 17, 63, 4096, 65537, 2 * 1024 * 1024};
    constexpr std::array<size_t, 4>                     alignments{16, 64, 4096, 65536};
    std::array<void*, sizes.size() * alignments.size()> blocks{};

    // Worker-owned heaps must leave their live blocks usable by the receiving thread.
    std::thread producer([&] {
        size_t index = 0;
        for (const size_t alignment : alignments)
        {
            for (const size_t size : sizes)
            {
                void* block = ::operator new(size, std::align_val_t{alignment}, std::nothrow);
                if (block)
                    std::memset(block, static_cast<int>(index + 1), std::max(size, size_t{1}));
                blocks[index++] = block;
            }
        }
    });
    producer.join();

    bool   valid = true;
    size_t index = 0;
    for (const size_t alignment : alignments)
    {
        for (const size_t size : sizes)
        {
            auto* block = static_cast<uint8_t*>(blocks[index]);
            if (!block)
                valid = false;
            else
            {
                valid &= reinterpret_cast<uintptr_t>(block) % alignment == 0;
                for (size_t offset = 0; offset < std::max(size, size_t{1}); ++offset)
                    valid &= block[offset] == static_cast<uint8_t>(index + 1);
                ::operator delete(block, std::align_val_t{alignment});
            }
            ++index;
        }
    }
    if (!valid)
        return Result::Error;
}
SWC_TEST_END()

SWC_END_NAMESPACE();

#endif
