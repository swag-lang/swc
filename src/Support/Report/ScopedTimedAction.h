#pragma once

#include "Main/TaskContext.h"

SWC_BEGIN_NAMESPACE();

// Tiny command/stage logger: a header line per command and one result line per stage.
namespace TimedActionLog
{
    using Clock = std::chrono::steady_clock;

    // "216 tests", "1 file", ... (grouped number + pluralized noun).
    Utf8 count(size_t value, std::string_view singular, const char* plural = nullptr);

    void printCommandHeader(const TaskContext& ctx);

    // Prints: <glyph> <label>  info • info • <elapsed since start>
    void printStage(const TaskContext& ctx, bool ok, std::string_view label, const std::vector<Utf8>& info, Clock::time_point start);
}

SWC_END_NAMESPACE();
