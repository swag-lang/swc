#pragma once
#include "Compiler/Parser/Ast/Ast.h"
#include "Compiler/Parser/Ast/AstNodes.h"
#include "Support/Core/SmallVector.h"

SWC_BEGIN_NAMESPACE();

namespace SemaGeneric
{
    inline constexpr std::string_view K_ARG_PREV_INDEX = "{prev-index}";

    inline void appendExplicitGenericArgs(const AstQuotedExpr& node, SmallVector<AstNodeRef>& outArgs)
    {
        if (node.nodeSuffixRef.isValid())
            outArgs.push_back(node.nodeSuffixRef);
    }

    inline void appendExplicitGenericArgs(const Ast& ast, const AstGenericArgListExpr& node, SmallVector<AstNodeRef>& outArgs)
    {
        ast.appendNodes(outArgs, node.spanChildrenRef);
    }

    inline void appendExplicitGenericArgs(const AstNode& node, const Ast& ast, SmallVector<AstNodeRef>& outArgs)
    {
        if (const auto* quotedExpr = node.safeCast<AstQuotedExpr>())
        {
            appendExplicitGenericArgs(*quotedExpr, outArgs);
            return;
        }

        if (const auto* genericArgList = node.safeCast<AstGenericArgListExpr>())
            appendExplicitGenericArgs(ast, *genericArgList, outArgs);
    }

    inline uint32_t callArgIndexFromUserIndex(uint32_t userArgIndex, AstNodeRef ufcsArg, bool prependUfcsArg = true)
    {
        return prependUfcsArg && ufcsArg.isValid() ? userArgIndex + 1 : userArgIndex;
    }
}

SWC_END_NAMESPACE();
