#pragma once

SWC_BEGIN_NAMESPACE();

class SourceView;
class CompilerInstance;
class SourceFile;
class TaskContext;
using SourceViewRef = StrongRef<SourceView>;
struct Token;
using TokenRef = StrongRef<Token>;

struct SourceCodeLocation
{
    const SourceView* srcView = nullptr;
    uint32_t          offset  = 0;
    uint32_t          len     = 0;
    uint32_t          line    = 0;
    uint32_t          column  = 0;

    void fromOffset(const TaskContext& ctx, const SourceView& view, uint32_t inOffset, uint32_t inLen = 1);
};

struct SourceLocation
{
    SourceViewRef srcViewRef = SourceViewRef::invalid();
    TokenRef      tokRef     = TokenRef::invalid();

    bool                  isValid() const { return srcViewRef.isValid() && tokRef.isValid(); }
    static SourceLocation invalid() { return {}; }
};

SWC_END_NAMESPACE();
