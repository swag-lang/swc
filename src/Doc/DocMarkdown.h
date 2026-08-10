#pragma once

#include "Doc/DocTypes.h"

SWC_BEGIN_NAMESPACE();

class TaskContext;

class DocMarkdown
{
public:
    static Utf8 makeAnchor(std::string_view value);
    static Utf8 renderTypeName(const DocRenderContext& renderCtx, std::string_view typeName);
    static Utf8 renderCodeBlock(const TaskContext& ctx, std::string_view code, bool swagSyntax, const DocRenderContext* renderCtx = nullptr);
    static Utf8 renderLines(const DocRenderContext& renderCtx, std::span<const Utf8> lines, uint32_t headingOffset = 0);
};

SWC_END_NAMESPACE();
