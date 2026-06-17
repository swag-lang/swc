#include "pch.h"
#include "Backend/Encoder/Encoder.h"
#include "Compiler/Lexer/SourceView.h"
#include "Main/CompilerInstance.h"

SWC_BEGIN_NAMESPACE();

const uint8_t* Encoder::data() const
{
    if (!store_.size())
        return nullptr;
    return store_.ptr<uint8_t>(0);
}

uint8_t Encoder::byteAt(uint32_t index) const
{
    SWC_ASSERT(index < store_.size());
    return *(store_.ptr<uint8_t>(index));
}

void Encoder::copyTo(ByteSpanRW dst) const
{
    store_.copyTo(dst);
}

bool tryResolveDebugSourceInfo(const TaskContext& ctx, ResolvedDebugSourceInfo& outResolvedInfo, const DebugSourceInfo& debugSourceInfo)
{
    outResolvedInfo = {};
    if (!debugSourceInfo.isValid())
        return false;

    SourceCodeRef                            sourceCodeRef = debugSourceInfo.sourceCodeRef;
    CompilerInstance::ResolvedSourceLocation resolvedLocation;
    for (uint32_t i = 0; i < 8; ++i)
    {
        if (!ctx.compiler().tryResolveSourceLocation(ctx, resolvedLocation, sourceCodeRef))
            return false;

        const SourceView* srcView = resolvedLocation.codeRange.srcView;
        if (!srcView)
            break;

        const SourceCodeRef debugSourceCodeRef = srcView->debugSourceCodeRef();
        if (!debugSourceCodeRef.isValid() ||
            (debugSourceCodeRef.srcViewRef == sourceCodeRef.srcViewRef && debugSourceCodeRef.tokRef == sourceCodeRef.tokRef))
            break;

        sourceCodeRef = debugSourceCodeRef;
    }

    outResolvedInfo.codeRange  = resolvedLocation.codeRange;
    outResolvedInfo.sourceFile = ctx.compiler().owningSourceFile(resolvedLocation.codeRange.srcView);
    if (!outResolvedInfo.sourceFile)
        outResolvedInfo.sourceFile = resolvedLocation.sourceFile;
    return true;
}

void Encoder::addDebugSourceRange(const uint32_t codeStartOffset, const uint32_t codeEndOffset, const DebugSourceInfo& debugSourceInfo)
{
    if (codeEndOffset <= codeStartOffset)
        return;

    if (!debugSourceInfo.isValid())
        return;

    if (!debugSourceRanges_.empty())
    {
        EncoderDebugSourceRange& previous = debugSourceRanges_.back();
        if (previous.codeEndOffset == codeStartOffset && previous.debugSourceInfo.sameAs(debugSourceInfo))
        {
            previous.codeEndOffset = codeEndOffset;
            return;
        }
    }

    EncoderDebugSourceRange range;
    range.codeStartOffset = codeStartOffset;
    range.codeEndOffset   = codeEndOffset;
    range.debugSourceInfo = debugSourceInfo;
    debugSourceRanges_.push_back(range);
}

std::string Encoder::formatRegisterName(MicroReg reg) const
{
    if (!reg.isValid())
        return "inv";

    if (reg.isInstructionPointer())
        return "ip";
    if (reg.isNoBase())
        return "nobase";

    if (reg.isInt())
        return std::format("r{}", reg.index());
    if (reg.isFloat())
        return std::format("f{}", reg.index());
    if (reg.isVirtualInt())
        return std::format("v{}", reg.index());
    if (reg.isVirtualFloat())
        return std::format("vf{}", reg.index());

    return std::format("reg#{}", reg.packed);
}

Encoder::Encoder(TaskContext& ctx) :
    ctx_(&ctx)
{
}

void Encoder::addSymbolRelocation(uint32_t, uint32_t, uint16_t)
{
}

SWC_END_NAMESPACE();
