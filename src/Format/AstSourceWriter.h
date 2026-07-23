#pragma once
#include "Format/FormatOptions.h"
#include "Support/Core/Utf8.h"

SWC_BEGIN_NAMESPACE();

class Ast;
class SourceView;

struct FormatContext
{
    const Ast*           ast     = nullptr;
    const SourceView*    srcView = nullptr;
    const FormatOptions* options = nullptr;
    Utf8                 output;
};

// Re-emits a parsed source file through the formatting pipeline: the token
// stream is decomposed into a FormatModel, annotated from the AST, rewritten
// by the formatting passes, and rendered back to text.
class AstSourceWriter
{
public:
    explicit AstSourceWriter(FormatContext& formatCtx);
    void write();

private:
    FormatContext* formatCtx_ = nullptr;
};

SWC_END_NAMESPACE();
