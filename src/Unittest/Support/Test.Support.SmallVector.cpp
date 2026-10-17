#include "pch.h"

#if SWC_HAS_UNITTEST

#include "Support/Core/SmallVector.h"
#include "Unittest/Unittest.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    struct CopyFailure
    {
    };

    struct CopyTrackedValue
    {
        static inline uint32_t live                  = 0;
        static inline int32_t  copiesUntilThrow      = -1;
        static inline int32_t  assignmentsUntilThrow = -1;
        uint32_t               value                 = 0;

        explicit CopyTrackedValue(uint32_t requested = 0) noexcept :
            value(requested)
        {
            ++live;
        }

        CopyTrackedValue(const CopyTrackedValue& other) :
            value(other.value)
        {
            if (copiesUntilThrow == 0)
                throw CopyFailure{};
            if (copiesUntilThrow > 0)
                --copiesUntilThrow;
            ++live;
        }

        CopyTrackedValue& operator=(const CopyTrackedValue& other)
        {
            if (assignmentsUntilThrow == 0)
                throw CopyFailure{};
            if (assignmentsUntilThrow > 0)
                --assignmentsUntilThrow;
            value = other.value;
            return *this;
        }

        ~CopyTrackedValue()
        {
            --live;
        }
    };

    struct NonAssignableTrackedValue : CopyTrackedValue
    {
        using CopyTrackedValue::CopyTrackedValue;
        NonAssignableTrackedValue(const NonAssignableTrackedValue&)            = default;
        NonAssignableTrackedValue& operator=(const NonAssignableTrackedValue&) = delete;
    };

    struct NothrowTrackedValue
    {
        static inline uint32_t live  = 0;
        uint32_t               value = 0;

        explicit NothrowTrackedValue(uint32_t requested = 0) noexcept :
            value(requested)
        {
            ++live;
        }
        NothrowTrackedValue(const NothrowTrackedValue& other) noexcept :
            value(other.value)
        {
            ++live;
        }
        NothrowTrackedValue& operator=(const NothrowTrackedValue&) = default;
        ~NothrowTrackedValue() { --live; }
    };

    struct MoveOnlyTrackedValue
    {
        static inline uint32_t live            = 0;
        static inline int32_t  movesUntilThrow = -1;
        uint32_t               value           = 0;

        explicit MoveOnlyTrackedValue(uint32_t requested = 0) noexcept :
            value(requested)
        {
            ++live;
        }
        MoveOnlyTrackedValue(const MoveOnlyTrackedValue&)            = delete;
        MoveOnlyTrackedValue& operator=(const MoveOnlyTrackedValue&) = delete;
        MoveOnlyTrackedValue(MoveOnlyTrackedValue&& other)
        {
            if (movesUntilThrow == 0)
                throw CopyFailure{};
            if (movesUntilThrow > 0)
                --movesUntilThrow;
            value = std::exchange(other.value, 0);
            ++live;
        }
        MoveOnlyTrackedValue& operator=(MoveOnlyTrackedValue&& other) noexcept
        {
            value = std::exchange(other.value, 0);
            return *this;
        }
        ~MoveOnlyTrackedValue() { --live; }
    };

    struct NoAddressValue
    {
        uint32_t value;

        explicit NoAddressValue(uint32_t requested = 0) noexcept :
            value(requested)
        {
        }
        NoAddressValue*       operator&()       = delete;
        const NoAddressValue* operator&() const = delete;
    };

    struct MisleadingAddressValue
    {
        std::string text;

        explicit MisleadingAddressValue(std::string requested) :
            text(std::move(requested))
        {
        }
        MisleadingAddressValue*       operator&() noexcept { return nullptr; }
        const MisleadingAddressValue* operator&() const noexcept { return nullptr; }
    };

    struct ThrowingForwardIterator
    {
        using iterator_category = std::forward_iterator_tag;
        using value_type        = NothrowTrackedValue;
        using difference_type   = std::ptrdiff_t;
        using pointer           = const value_type*;
        using reference         = const value_type&;

        pointer  current            = nullptr;
        int32_t* advancesUntilThrow = nullptr;

        reference                operator*() const noexcept { return *current; }
        bool                     operator==(const ThrowingForwardIterator& other) const noexcept { return current == other.current; }
        bool                     operator!=(const ThrowingForwardIterator& other) const noexcept { return !(*this == other); }
        ThrowingForwardIterator& operator++()
        {
            if (*advancesUntilThrow == 0)
                throw CopyFailure{};
            if (*advancesUntilThrow > 0)
                --*advancesUntilThrow;
            ++current;
            return *this;
        }
        ThrowingForwardIterator operator++(int)
        {
            const auto previous = *this;
            ++*this;
            return previous;
        }
    };

    static_assert(!std::is_nothrow_move_constructible_v<SmallVector<CopyTrackedValue, 4>>);
    static_assert(!std::is_nothrow_move_assignable_v<SmallVector<CopyTrackedValue, 4>>);
    static_assert(std::is_nothrow_move_constructible_v<SmallVector<uint32_t, 4>>);
    static_assert(std::is_nothrow_move_constructible_v<SmallVector<std::string, 4>>);
    static_assert(!std::is_copy_constructible_v<SmallVector<MoveOnlyTrackedValue, 2>>);
    static_assert(!std::is_copy_assignable_v<SmallVector<MoveOnlyTrackedValue, 2>>);
    static_assert(!std::is_nothrow_move_constructible_v<SmallVector<MoveOnlyTrackedValue, 2>>);
    static_assert(!std::is_copy_constructible_v<SmallVector<std::unique_ptr<uint32_t>, 2>>);
}

SWC_TEST_BEGIN(SmallVector_CopyableValuesNeedNoAddressOfOperator)
{
    const NoAddressValue           fill(7);
    SmallVector<NoAddressValue, 1> values;
    values.resize(3, fill);
    if (values.size() != 3)
        return Result::Error;
    for (const auto& value : values)
    {
        if (value.value != 7)
            return Result::Error;
    }
}
SWC_TEST_END()

SWC_TEST_BEGIN(SmallVector_BorrowedFillUsesTheActualElementAddress)
{
    SmallVector<MisleadingAddressValue, 1> values;
    values.emplace_back("alpha");
    values.resize(3, values.front());
    if (values.size() != 3)
        return Result::Error;
    for (const auto& value : values)
    {
        if (value.text != "alpha")
            return Result::Error;
    }
}
SWC_TEST_END()

SWC_TEST_BEGIN(SmallVector_CopyConstructionCleansPartialValues)
{
    for (const uint32_t count : {2u, 3u, 10u})
    {
        {
            SmallVector<CopyTrackedValue, 2> source;
            for (uint32_t i = 0; i < count; ++i)
                source.emplace_back(i + 1);

            CopyTrackedValue::copiesUntilThrow = 1;
            bool threw                         = false;
            try
            {
                const SmallVector<CopyTrackedValue, 2> copy(source);
            }
            catch (const CopyFailure&)
            {
                threw = true;
            }
            CopyTrackedValue::copiesUntilThrow = -1;
            if (!threw || CopyTrackedValue::live != count)
                return Result::Error;
            for (uint32_t i = 0; i < count; ++i)
            {
                if (source[i].value != i + 1)
                    return Result::Error;
            }
        }
        if (CopyTrackedValue::live)
            return Result::Error;
    }
}
SWC_TEST_END()

SWC_TEST_BEGIN(SmallVector_MoveOnlyFailuresPreserveLiveElements)
{
    for (uint32_t action = 0; action < 4; ++action)
    {
        {
            SmallVector<MoveOnlyTrackedValue, 2> values;
            values.emplace_back(1);
            values.emplace_back(2);
            SmallVector<MoveOnlyTrackedValue, 2> target;
            if (action == 3)
                target.emplace_back(99);
            const auto* original                  = values.data();
            MoveOnlyTrackedValue::movesUntilThrow = 1;
            bool threw                            = false;
            try
            {
                if (action == 0)
                    values.reserve(20);
                else if (action == 1)
                    values.emplace_back(3);
                else if (action == 2)
                {
                    const SmallVector<MoveOnlyTrackedValue, 2> moved(std::move(values));
                }
                else
                    target = std::move(values);
            }
            catch (const CopyFailure&)
            {
                threw = true;
            }
            MoveOnlyTrackedValue::movesUntilThrow = -1;
            if (!threw || values.size() != 2 || values.data() != original || values.capacity() != 2 || !target.empty() || MoveOnlyTrackedValue::live != 2)
                return Result::Error;
            values.emplace_back(9);
            if (values.size() != 3 || values.back().value != 9 || MoveOnlyTrackedValue::live != 3)
                return Result::Error;
        }
        if (MoveOnlyTrackedValue::live)
            return Result::Error;
    }
}
SWC_TEST_END()

SWC_TEST_BEGIN(SmallVector_MoveOnlyVectorsRelocateInStandardContainers)
{
    {
        std::vector<SmallVector<MoveOnlyTrackedValue, 2>> outer;
        outer.reserve(1);
        outer.emplace_back();
        outer.front().emplace_back(21);
        outer.front().emplace_back(22);
        outer.emplace_back();
        if (outer.size() != 2 || outer.front().size() != 2 || !outer.back().empty() || MoveOnlyTrackedValue::live != 2)
            return Result::Error;
        if (outer.front()[0].value != 21 || outer.front()[1].value != 22)
            return Result::Error;
    }
    if (MoveOnlyTrackedValue::live)
        return Result::Error;
}
SWC_TEST_END()

SWC_TEST_BEGIN(SmallVector_BorrowedMoveOnlyValuesSurviveGrowth)
{
    SmallVector<std::unique_ptr<uint32_t>, 1> values;
    values.push_back(std::make_unique<uint32_t>(17));
    values.push_back(std::move(values.front()));
    if (values.size() != 2 || values.front() || !values.back() || *values.back() != 17)
        return Result::Error;
    values.emplace(values.begin(), std::move(values.back()));
    if (values.size() != 3 || !values.front() || *values.front() != 17 || values[1] || values[2])
        return Result::Error;
}
SWC_TEST_END()

SWC_TEST_BEGIN(SmallVector_ReserveAndGrowthCleanPartialValues)
{
    for (const bool appendValue : {false, true})
    {
        {
            SmallVector<CopyTrackedValue, 2> values;
            values.emplace_back(1);
            values.emplace_back(2);
            const auto*  original              = values.data();
            const size_t originalCapacity      = values.capacity();
            CopyTrackedValue::copiesUntilThrow = 1;
            bool threw                         = false;
            try
            {
                if (appendValue)
                    values.emplace_back(3);
                else
                    values.reserve(20);
            }
            catch (const CopyFailure&)
            {
                threw = true;
            }
            CopyTrackedValue::copiesUntilThrow = -1;
            if (!threw || values.size() != 2 || values.data() != original || values.capacity() != originalCapacity || CopyTrackedValue::live != 2)
                return Result::Error;
            if (values[0].value != 1 || values[1].value != 2)
                return Result::Error;
            values.emplace_back(3);
            if (values.size() != 3 || values[2].value != 3 || CopyTrackedValue::live != 3)
                return Result::Error;
        }
        if (CopyTrackedValue::live)
            return Result::Error;
    }
}
SWC_TEST_END()

SWC_TEST_BEGIN(SmallVector_BorrowedElementArgumentsSurviveGrowthAndInsertion)
{
    for (const bool reserveAhead : {false, true})
    {
        SmallVector<std::string, 1> values;
        values.emplace_back("alpha");
        if (reserveAhead)
            values.reserve(16);
        values.push_back(values.front());
        if (values.size() != 2 || values[0] != "alpha" || values[1] != "alpha")
            return Result::Error;
        values[1] = "beta";
        values.emplace(values.begin() + 1, values.back());
        if (values.size() != 3 || values[0] != "alpha" || values[1] != "beta" || values[2] != "beta")
            return Result::Error;
        values.resize(9, values.front());
        for (size_t i = 3; i < values.size(); ++i)
        {
            if (values[i] != "alpha")
                return Result::Error;
        }
        values.append(values.data() + 1, 2);
        if (values.size() != 11 || values[9] != "beta" || values[10] != "beta")
            return Result::Error;
    }
}
SWC_TEST_END()

SWC_TEST_BEGIN(SmallVector_InterruptedRangeInsertionRetainsOnlyLiveValues)
{
    for (const uint32_t count : {2u, 5u})
    {
        for (const uint32_t position : {0u, 1u, 4u})
        {
            for (const bool failAssignment : {false, true})
            {
                for (int32_t failurePoint = 0; failurePoint < 10; ++failurePoint)
                {
                    {
                        std::array<CopyTrackedValue, 5> source;
                        for (uint32_t i = 0; i < source.size(); ++i)
                            source[i].value = 10 + i;
                        SmallVector<CopyTrackedValue, 2> values;
                        values.reserve(32);
                        for (uint32_t i = 0; i < 4; ++i)
                            values.emplace_back(i + 1);
                        CopyTrackedValue::copiesUntilThrow      = failAssignment ? -1 : failurePoint;
                        CopyTrackedValue::assignmentsUntilThrow = failAssignment ? failurePoint : -1;
                        bool threw                              = false;
                        try
                        {
                            values.insert(values.begin() + position, source.begin(), source.begin() + count);
                        }
                        catch (const CopyFailure&)
                        {
                            threw = true;
                        }
                        CopyTrackedValue::copiesUntilThrow      = -1;
                        CopyTrackedValue::assignmentsUntilThrow = -1;
                        if (CopyTrackedValue::live != source.size() + values.size())
                            return Result::Error;
                        if (!threw)
                        {
                            if (values.size() != 4 + count)
                                return Result::Error;
                            for (uint32_t i = 0; i < values.size(); ++i)
                            {
                                const uint32_t expected = i < position ? i + 1 : i < position + count ? 10 + i - position
                                                                                                      : i - count + 1;
                                if (values[i].value != expected)
                                    return Result::Error;
                            }
                        }
                        values.clear();
                        if (CopyTrackedValue::live != source.size())
                            return Result::Error;
                        values.emplace_back(99);
                        if (values.front().value != 99)
                            return Result::Error;
                    }
                    if (CopyTrackedValue::live)
                        return Result::Error;
                }
            }
        }
    }
}
SWC_TEST_END()

SWC_TEST_BEGIN(SmallVector_FallibleInlineMovesKeepValidContainers)
{
    {
        SmallVector<CopyTrackedValue, 4> source;
        source.emplace_back(21);
        source.emplace_back(22);
        CopyTrackedValue::copiesUntilThrow = 1;
        bool threw                         = false;
        try
        {
            const SmallVector<CopyTrackedValue, 4> moved(std::move(source));
        }
        catch (const CopyFailure&)
        {
            threw = true;
        }
        CopyTrackedValue::copiesUntilThrow = -1;
        if (!threw || source.size() != 2 || CopyTrackedValue::live != 2)
            return Result::Error;

        SmallVector<CopyTrackedValue, 4> target;
        target.emplace_back(99);
        CopyTrackedValue::copiesUntilThrow = 1;
        threw                              = false;
        try
        {
            target = std::move(source);
        }
        catch (const CopyFailure&)
        {
            threw = true;
        }
        CopyTrackedValue::copiesUntilThrow = -1;
        if (!threw || !target.empty() || source.size() != 2 || CopyTrackedValue::live != 2 || source[0].value != 21 || source[1].value != 22)
            return Result::Error;
    }
    if (CopyTrackedValue::live)
        return Result::Error;
}
SWC_TEST_END()

SWC_TEST_BEGIN(SmallVector_HeapMovesTransferStorageWithoutConstructingValues)
{
    {
        SmallVector<CopyTrackedValue, 1> source;
        source.emplace_back(21);
        source.emplace_back(22);
        const auto* original               = source.data();
        CopyTrackedValue::copiesUntilThrow = 0;
        SmallVector<CopyTrackedValue, 1> moved(std::move(source));
        SmallVector<CopyTrackedValue, 1> target;
        target                             = std::move(moved);
        CopyTrackedValue::copiesUntilThrow = -1;
        if (!source.empty() || !moved.empty() || target.size() != 2 || target.data() != original || CopyTrackedValue::live != 2)
            return Result::Error;
    }
    if (CopyTrackedValue::live)
        return Result::Error;
}
SWC_TEST_END()

SWC_TEST_BEGIN(SmallVector_UnorderedEraseKeepsLiveValuesWhenReplacementThrows)
{
    {
        SmallVector<CopyTrackedValue, 4> values;
        values.emplace_back(1);
        values.emplace_back(2);
        values.emplace_back(3);
        CopyTrackedValue::assignmentsUntilThrow = 0;
        bool threw                              = false;
        try
        {
            values.erase_unordered(values.begin() + 1);
        }
        catch (const CopyFailure&)
        {
            threw = true;
        }
        CopyTrackedValue::assignmentsUntilThrow = -1;
        if (!threw || values.size() != 3 || CopyTrackedValue::live != 3)
            return Result::Error;
        values.erase_unordered(values.begin() + 1);
        if (values.size() != 2 || values[0].value != 1 || values[1].value != 3 || CopyTrackedValue::live != 2)
            return Result::Error;
    }
    if (CopyTrackedValue::live)
        return Result::Error;

    for (uint32_t position = 0; position < 4; ++position)
    {
        {
            SmallVector<NonAssignableTrackedValue, 4> values;
            for (uint32_t i = 0; i < 4; ++i)
                values.emplace_back(i + 1);
            CopyTrackedValue::copiesUntilThrow = 0;
            bool threw                         = false;
            try
            {
                values.erase_unordered(values.begin() + position);
            }
            catch (const CopyFailure&)
            {
                threw = true;
            }
            CopyTrackedValue::copiesUntilThrow = -1;
            const uint32_t expected            = position == 3 ? 3 : position;
            if (threw != (position != 3) || values.size() != expected || CopyTrackedValue::live != expected)
                return Result::Error;
            for (uint32_t i = 0; i < values.size(); ++i)
            {
                if (values[i].value != i + 1)
                    return Result::Error;
            }
        }
        if (CopyTrackedValue::live)
            return Result::Error;
    }
}
SWC_TEST_END()

SWC_TEST_BEGIN(SmallVector_ThrowingRangeTraversalRetainsOnlyLiveValues)
{
    for (const uint32_t count : {2u, 5u})
    {
        for (const uint32_t position : {0u, 3u, 4u})
        {
            for (int32_t failurePoint = 0; failurePoint < 13; ++failurePoint)
            {
                {
                    std::array<NothrowTrackedValue, 5> source;
                    for (uint32_t i = 0; i < source.size(); ++i)
                        source[i].value = 10 + i;
                    SmallVector<NothrowTrackedValue, 2> values;
                    values.reserve(32);
                    for (uint32_t i = 0; i < 4; ++i)
                        values.emplace_back(i + 1);
                    int32_t remaining = failurePoint;
                    bool    threw     = false;
                    try
                    {
                        values.insert(values.begin() + position, ThrowingForwardIterator{source.data(), &remaining}, ThrowingForwardIterator{source.data() + count, &remaining});
                    }
                    catch (const CopyFailure&)
                    {
                        threw = true;
                    }
                    if (NothrowTrackedValue::live != source.size() + values.size())
                        return Result::Error;
                    if (!threw)
                    {
                        if (values.size() != 4 + count)
                            return Result::Error;
                        for (uint32_t i = 0; i < values.size(); ++i)
                        {
                            const uint32_t expected = i < position ? i + 1 : i < position + count ? 10 + i - position
                                                                                                  : i - count + 1;
                            if (values[i].value != expected)
                                return Result::Error;
                        }
                    }
                    values.clear();
                    if (NothrowTrackedValue::live != source.size())
                        return Result::Error;
                }
                if (NothrowTrackedValue::live)
                    return Result::Error;
            }
        }
    }
}
SWC_TEST_END()

SWC_TEST_BEGIN(SmallVector_RangeInsertionAndAssignmentPreserveValues)
{
    constexpr std::array source = {10u, 11u, 12u, 13u, 14u, 15u, 16u, 17u};
    for (uint32_t initialCount = 0; initialCount <= 5; ++initialCount)
    {
        for (uint32_t count = 0; count <= source.size(); ++count)
        {
            for (uint32_t position = 0; position <= initialCount; ++position)
            {
                SmallVector<uint32_t, 2> values;
                for (uint32_t i = 0; i < initialCount; ++i)
                    values.push_back(i + 1);
                const auto inserted = values.insert(values.begin() + position, source.begin(), source.begin() + count);
                if (inserted != values.begin() + position || values.size() != initialCount + count)
                    return Result::Error;
                for (uint32_t i = 0; i < values.size(); ++i)
                {
                    const uint32_t expected = i < position ? i + 1 : i < position + count ? source[i - position]
                                                                                          : i - count + 1;
                    if (values[i] != expected)
                        return Result::Error;
                }
                const size_t capacity = values.capacity();
                values.assign(source.begin(), source.begin() + count);
                if (values.capacity() != capacity || !std::ranges::equal(values, std::span(source).first(count)))
                    return Result::Error;
            }
        }
    }
}
SWC_TEST_END()

SWC_END_NAMESPACE();

#endif
