#include "pch.h"
#include "Support/Report/HardwareException.h"
#include "Support/Report/Assert.h"

SWC_BEGIN_NAMESPACE();

void HardwareException::appendSectionHeader(Utf8& outMsg, const std::string_view title)
{
    outMsg += "\n";
    outMsg += title;
    outMsg += ":";
    outMsg += "\n";
    outMsg += "---------------------------------\n";
}

void HardwareException::appendField(Utf8& outMsg, const std::string_view label, const std::string_view value)
{
    constexpr uint32_t kFieldWidth = 24;
    SWC_ASSERT(!label.empty());
    SWC_ASSERT(label.back() != ':');
    outMsg += label;
    outMsg += ":";
    uint32_t used = static_cast<uint32_t>(label.size()) + 1;
    while (used < kFieldWidth)
    {
        outMsg += " ";
        ++used;
    }
    outMsg += value;
    outMsg += "\n";
}

SWC_END_NAMESPACE();
