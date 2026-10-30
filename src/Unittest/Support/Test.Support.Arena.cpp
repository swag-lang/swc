#include "pch.h"

#if SWC_HAS_UNITTEST

#include "Support/Memory/Arena.h"
#include "Unittest/Unittest.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    struct ArenaLifetime
    {
        std::vector<uint32_t>* destroyed;
        uint32_t               id;

        ~ArenaLifetime() { destroyed->push_back(id); }
    };

    struct ArenaThrowingElement
    {
        inline static thread_local uint32_t attempts  = 0;
        inline static thread_local uint32_t destroyed = 0;

        ArenaThrowingElement()
        {
            if (++attempts == 3)
                throw std::runtime_error("array construction failed");
        }

        ~ArenaThrowingElement() { ++destroyed; }
    };
}

SWC_TEST_BEGIN(Arena_MoveAndResetDestroyOwnedObjectsOnce)
{
    std::vector<uint32_t> destroyed;
    {
        Arena source(64);
        source.make<ArenaLifetime>(&destroyed, 1);
        source.make<ArenaLifetime>(&destroyed, 2);
        Arena moved(std::move(source));
        source.reset();
        if (!destroyed.empty())
            return Result::Error;

        Arena target(64);
        target.make<ArenaLifetime>(&destroyed, 3);
        target = std::move(moved);
        if (destroyed != std::vector<uint32_t>{3})
            return Result::Error;
        target.reset();
        target.reset();
    }
    if (destroyed != std::vector<uint32_t>{3, 2, 1})
        return Result::Error;
}
SWC_TEST_END()

SWC_TEST_BEGIN(Arena_FailedArrayConstructionDestroysOnlyCompletedElements)
{
    ArenaThrowingElement::attempts  = 0;
    ArenaThrowingElement::destroyed = 0;
    Arena arena;
    bool  failed = false;
    try
    {
        arena.makeArray<ArenaThrowingElement>(4);
    }
    catch (const std::runtime_error&)
    {
        failed = true;
    }
    arena.reset();
    if (!failed || ArenaThrowingElement::attempts != 3 || ArenaThrowingElement::destroyed != 2)
        return Result::Error;
}
SWC_TEST_END()

SWC_END_NAMESPACE();

#endif
