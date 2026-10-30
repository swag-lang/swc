#include "pch.h"

#if SWC_HAS_UNITTEST

#include "Backend/JIT/JITMemory.h"
#include "Backend/JIT/JITMemoryManager.h"
#include "Support/Os/Os.h"
#include "Unittest/Unittest.h"

SWC_BEGIN_NAMESPACE();

SWC_TEST_BEGIN(JIT_ReleasedProximityBlocksAreDecommitted)
{
    std::array<void*, 2> released{};
    {
        JITMemoryManager         manager;
        std::array<JITMemory, 2> allocations;
        for (size_t i = 0; i < allocations.size(); ++i)
        {
            manager.allocate(allocations[i], 4097);
            released[i] = allocations[i].entryPoint();
            if (!Os::isProximityMemory(released[i]))
                return Result::Error;
        }
    }
    for (const void* ptr : released)
    {
        MEMORY_BASIC_INFORMATION memory{};
        if (!VirtualQuery(ptr, &memory, sizeof(memory)) || memory.State != MEM_RESERVE)
            return Result::Error;
    }
}
SWC_TEST_END()

SWC_END_NAMESPACE();

#endif
