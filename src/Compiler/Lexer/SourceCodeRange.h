#pragma once

SWC_BEGIN_NAMESPACE();

class SourceView;
class TaskContext;
struct Token;
using SourceViewRef = StrongRef<SourceView>;
using TokenRef      = StrongRef<Token>;

struct SourceCodeRange
{
    const SourceView* srcView = nullptr;
    uint32_t          offset  = 0;
    uint32_t          len     = 0;
    uint32_t          line    = 0;
    uint32_t          column  = 0;

    void fromOffset(const TaskContext& ctx, const SourceView& view, uint32_t inOffset, uint32_t inLen = 1);
};

struct SourceCodeRef
{
    SourceViewRef srcViewRef = SourceViewRef::invalid();
    TokenRef      tokRef     = TokenRef::invalid();

    bool                 isValid() const { return srcViewRef.isValid() && tokRef.isValid(); }
    static SourceCodeRef invalid() { return {}; }
};

SWC_END_NAMESPACE();
