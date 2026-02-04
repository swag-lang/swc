#pragma once
#include "Compiler/Sema/Cast/Cast.h"
#include "Compiler/Sema/Core/Sema.h"
#include "Compiler/Sema/Core/SemaNodeView.h"

SWC_BEGIN_NAMESPACE();

namespace SemaBinaryOp
{
    Result checkOperandTypes(Sema& sema, AstNodeRef nodeRef, TokenId op, AstNodeRef leftRef, AstNodeRef rightRef, const SemaNodeView& leftView, const SemaNodeView& rightView);
    Result castRightToLeft(Sema& sema, TokenId op, SemaNodeView& leftView, SemaNodeView& rightView, CastKind castKind);
}

SWC_END_NAMESPACE();
