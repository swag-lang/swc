#pragma once
#include "Compiler/Parser/Ast/AstNode.h"

SWC_BEGIN_NAMESPACE();

namespace SemaReexpandExpr
{
    inline bool isReexpandableExpr(const AstNode& node)
    {
        return node.is(AstNodeId::CallExpr) ||
               node.is(AstNodeId::IntrinsicCallExpr) ||
               node.is(AstNodeId::UnaryExpr) ||
               node.is(AstNodeId::BinaryExpr) ||
               node.is(AstNodeId::RelationalExpr) ||
               node.is(AstNodeId::IndexExpr) ||
               node.is(AstNodeId::CastExpr);
    }
}

SWC_END_NAMESPACE();
