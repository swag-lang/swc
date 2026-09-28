#pragma once
#include "Compiler/Parser/Ast/Ast.h"
#include "Compiler/Sema/Core/Sema.h"

SWC_BEGIN_NAMESPACE();

namespace SemaAstLookup
{
    // Refs are local to an Ast; prefer the source when both ASTs contain the index.
    inline const Ast* resolveValidNodeAst(Sema& sema, const Ast& sourceAst, AstNodeRef nodeRef)
    {
        if (sourceAst.hasNode(nodeRef))
            return &sourceAst;
        if (sema.ast().hasNode(nodeRef))
            return &sema.ast();
        return nullptr;
    }

    inline const Ast* resolveValidSpanAst(Sema& sema, const Ast& sourceAst, SpanRef spanRef)
    {
        if (sourceAst.hasSpan(spanRef))
            return &sourceAst;
        if (sema.ast().hasSpan(spanRef))
            return &sema.ast();
        return nullptr;
    }
}

SWC_END_NAMESPACE();
