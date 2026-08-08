#include "pch.h"

#if SWC_HAS_UNITTEST

#include "Support/Core/Utf8.h"
#include "Support/Core/Utf8Helper.h"
#include "Unittest/Unittest.h"

SWC_BEGIN_NAMESPACE();

SWC_TEST_BEGIN(Utf8_MoveOperationsTransferStorage)
{
    Utf8        source(256, 'a');
    const char* sourceData = source.data();

    Utf8 constructed(std::move(source));
    if (constructed.size() != 256 || constructed.front() != 'a')
        return Result::Error;
    if (constructed.data() != sourceData || !source.empty())
        return Result::Error;

    Utf8        assignedSource(512, 'b');
    const char* assignedSourceData = assignedSource.data();
    Utf8        assigned(384, 'c');

    assigned = std::move(assignedSource);
    if (assigned.size() != 512 || assigned.front() != 'b')
        return Result::Error;
    if (assigned.data() != assignedSourceData || !assignedSource.empty())
        return Result::Error;
}
SWC_TEST_END()

SWC_TEST_BEGIN(Utf8_FixedDecimalFormatting)
{
    if (Utf8Helper::formatFixedDecimal(12.345, 2) != "12.35")
        return Result::Error;
    if (Utf8Helper::formatFixedDecimal(-0.0, 2) != "-0.00")
        return Result::Error;
    if (Utf8Helper::formatFixedDecimal(0.0, 1, true) != "+0.0")
        return Result::Error;
    if (Utf8Helper::toNiceSize(1536) != "1.5 KB")
        return Result::Error;
}
SWC_TEST_END()

SWC_END_NAMESPACE();

#endif
