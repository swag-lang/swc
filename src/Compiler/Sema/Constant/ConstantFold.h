#pragma once
#include "Compiler/Lexer/Token.h"
#include "Compiler/Parser/Ast/AstNode.h"
#include "Compiler/Sema/Core/SemaNodeView.h"

SWC_BEGIN_NAMESPACE();

class Sema;
struct AstBinaryExpr;
struct AstUnaryExpr;

namespace ConstantFold
{
    Result unary(Sema& sema, ConstantRef& result, TokenId op, const AstUnaryExpr& node, const SemaNodeView& nodeView);
    Result binary(Sema& sema, ConstantRef& result, TokenId op, const AstBinaryExpr& node, const SemaNodeView& nodeLeftView, const SemaNodeView& nodeRightView);
    Result relational(Sema& sema, ConstantRef& result, TokenId op, const SemaNodeView& nodeLeftView, const SemaNodeView& nodeRightView);
    Result logical(Sema& sema, ConstantRef& result, TokenId op, const SemaNodeView& nodeLeftView, const SemaNodeView& nodeRightView);
    Result checkRightConstant(Sema& sema, TokenId op, AstNodeRef nodeRef, const SemaNodeView& nodeRightView);
}

SWC_END_NAMESPACE();
