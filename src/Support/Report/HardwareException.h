#pragma once
#include "Support/Os/Os.h"

SWC_BEGIN_NAMESPACE();

class TaskContext;
class Utf8;

namespace HardwareException
{
    void appendSectionHeader(Utf8& outMsg, std::string_view title);
    void appendField(Utf8& outMsg, std::string_view label, std::string_view value);
    Utf8 format(const TaskContext* ctx, std::string_view title, const void* platformExceptionPointers, std::string_view extraInfo = {});
    void log(const TaskContext& ctx, std::string_view title, const void* platformExceptionPointers, std::string_view extraInfo = {});
    void print(std::string_view title, const void* platformExceptionPointers, std::string_view extraInfo = {});
}

SWC_END_NAMESPACE();
