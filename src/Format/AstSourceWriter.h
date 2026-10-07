#pragma once
#include "Format/FormatOptions.h"
#include "Support/Core/Utf8.h"

SWC_BEGIN_NAMESPACE();

class Ast;
class SourceView;

struct FormatContext
{
    const Ast*           ast             = nullptr;
    const SourceView*    srcView         = nullptr;
    const FormatOptions* options         = nullptr;
    bool                 rewriteSyntax   = true;  // allow the rewrites that change tokens, not only whitespace
    bool                 syntaxRewritten = false; // `output` holds rewritten source that still has to be parsed and formatted
    Utf8                 output;
};

// Re-emits a parsed source file through the formatting pipeline: the token
// stream is decomposed into a FormatModel, annotated from the AST, rewritten
// by the formatting passes, and rendered back to text. A rewrite that changes
// tokens stops there and hands back the rewritten source unformatted, because
// the layout passes need an AST that matches it.
class AstSourceWriter
{
public:
    explicit AstSourceWriter(FormatContext& formatCtx);
    void write() const;

private:
    FormatContext* formatCtx_ = nullptr;
};

SWC_END_NAMESPACE();
