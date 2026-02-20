#pragma once
#include "Support/Os/Os.h"

SWC_BEGIN_NAMESPACE();

class TaskContext;
class Utf8;

using HardwareExceptionExtraInfoFn = void (*)(Utf8& outMsg, const TaskContext& ctx, const void* userData);

namespace HardwareException
{
    void appendSectionHeader(Utf8& outMsg, std::string_view title);
    void appendFieldPrefix(Utf8& outMsg, std::string_view label);
    void appendField(Utf8& outMsg, std::string_view label, std::string_view value);
    void log(const TaskContext& ctx, std::string_view title, SWC_LP_EXCEPTION_POINTERS args, HardwareExceptionExtraInfoFn extraInfoFn = nullptr, const void* userData = nullptr);
}

SWC_END_NAMESPACE();
