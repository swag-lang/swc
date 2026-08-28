#pragma once
#include "Compiler/Lexer/SourceCodeRange.h"

SWC_BEGIN_NAMESPACE();

class SourceFile;
class TaskContext;

struct DebugSourceInfo
{
    SourceCodeRef sourceCodeRef = SourceCodeRef::invalid();
    bool          debugNoStep   = false;

    bool isValid() const { return sourceCodeRef.isValid(); }
    bool isStepVisible() const { return isValid() && !debugNoStep; }

    bool sameAs(const DebugSourceInfo& other) const
    {
        return debugNoStep == other.debugNoStep &&
               sourceCodeRef.srcViewRef == other.sourceCodeRef.srcViewRef &&
               sourceCodeRef.tokRef == other.sourceCodeRef.tokRef;
    }
};

struct EncoderDebugSourceRange
{
    uint32_t        codeStartOffset = 0;
    uint32_t        codeEndOffset   = 0;
    DebugSourceInfo debugSourceInfo;
};

struct ResolvedDebugSourceInfo
{
    SourceCodeRange   codeRange;
    const SourceFile* sourceFile = nullptr;
};

bool tryResolveDebugSourceInfo(const TaskContext& ctx, ResolvedDebugSourceInfo& outResolvedInfo, const DebugSourceInfo& debugSourceInfo);

SWC_END_NAMESPACE();
