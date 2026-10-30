#pragma once
#include "Support/Core/RefTypes.h"

SWC_BEGIN_NAMESPACE();

class TaskContext;

struct SourceCodeRange
{
    const SourceView* srcView = nullptr;

    uint32_t offset = 0;
    uint32_t len    = 0;

    uint32_t line   = 0;
    uint32_t column = 0;

    void fromOffset(const TaskContext& ctx, const SourceView& view, uint32_t inOffset, uint32_t inLen = 1);

    // The line containing the final byte, or the starting line for an empty range.
    uint32_t endLine(const TaskContext& ctx) const;
};

struct SourceCodeRef
{
    bool operator==(const SourceCodeRef&) const = default;

    SourceViewRef srcViewRef = SourceViewRef::invalid();
    TokenRef      tokRef     = TokenRef::invalid();

    bool isValid() const { return srcViewRef.isValid() && tokRef.isValid(); }

    static SourceCodeRef invalid() { return {}; }
};

#if !SWC_HAS_REF_DEBUG_INFO
static_assert(sizeof(SourceCodeRef) == 2 * sizeof(uint32_t));
#endif

SWC_END_NAMESPACE();
