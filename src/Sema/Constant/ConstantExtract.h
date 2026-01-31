#pragma once
#include "Core/Result.h"
#include "Parser/Ast/AstNode.h"

SWC_BEGIN_NAMESPACE();

class ConstantValue;
struct SemaNodeView;
class SymbolVariable;

namespace ConstantExtract
{
    Result extractConstantStructMember(Sema& sema, const ConstantValue& cst, const SymbolVariable& symVar, AstNodeRef nodeRef, AstNodeRef nodeMemberRef);
    Result constantFoldIndex(Sema& sema, AstNodeRef nodeArgRef, const SemaNodeView& nodeExprView, int64_t constIndex, bool hasConstIndex);
}

SWC_END_NAMESPACE();
