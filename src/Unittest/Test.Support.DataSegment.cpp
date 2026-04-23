#include "pch.h"

#if SWC_HAS_UNITTEST

#include "Support/Core/DataSegment.h"
#include "Unittest/Unittest.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    bool relocationOffsetsAre(const std::vector<DataSegmentRelocation>& relocations, std::initializer_list<uint32_t> expectedOffsets)
    {
        if (relocations.size() != expectedOffsets.size())
            return false;

        size_t index = 0;
        for (const uint32_t expectedOffset : expectedOffsets)
        {
            if (relocations[index].offset != expectedOffset)
                return false;
            ++index;
        }

        return true;
    }
}

SWC_TEST_BEGIN(DataSegment_CopyRelocationsKeepsSortedAppendFastPath)
{
    DataSegment segment;
    segment.addRelocation(4, 40);
    segment.addRelocation(8, 80);
    segment.addRelocation(12, 120);

    std::vector<DataSegmentRelocation> relocations;
    segment.copyRelocations(relocations, 0, 32);
    if (!relocationOffsetsAre(relocations, {4, 8, 12}))
        return Result::Error;

    segment.addRelocation(16, 160);
    segment.copyRelocations(relocations, 0, 32);
    if (!relocationOffsetsAre(relocations, {4, 8, 12, 16}))
        return Result::Error;

    return Result::Continue;
}
SWC_TEST_END()

SWC_TEST_BEGIN(DataSegment_CopyRelocationsRebuildsAfterOutOfOrderAppend)
{
    DataSegment segment;
    segment.addRelocation(8, 80);
    segment.addRelocation(16, 160);
    segment.addRelocation(4, 40);

    std::vector<DataSegmentRelocation> relocations;
    segment.copyRelocations(relocations, 0, 32);
    if (!relocationOffsetsAre(relocations, {4, 8, 16}))
        return Result::Error;

    return Result::Continue;
}
SWC_TEST_END()

SWC_END_NAMESPACE();

#endif
