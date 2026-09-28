#pragma once
#include "Compiler/Parser/Ast/Ast.h"
#include "Compiler/Parser/Ast/AstNodes.h"
#include "Support/Core/SmallVector.h"

SWC_BEGIN_NAMESPACE();

namespace SemaGeneric
{
    inline void appendQuotedGenericArgs(const AstQuotedExpr& node, SmallVector<AstNodeRef>& outArgs)
    {
        if (node.nodeSuffixRef.isValid())
            outArgs.push_back(node.nodeSuffixRef);
    }

    inline void appendQuotedGenericArgs(const Ast& ast, const AstQuotedListExpr& node, SmallVector<AstNodeRef>& outArgs)
    {
        ast.appendNodes(outArgs, node.spanChildrenRef);
    }
}

SWC_END_NAMESPACE();
