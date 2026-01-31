#pragma once
#include "Parser/Ast/AstNode.h"
#include "Sema/Constant/ConstantValue.h"

SWC_BEGIN_NAMESPACE();

class ConstantValue;
class SymbolVariable;

namespace ConstantExtract
{
    Result structMember(Sema& sema, const ConstantValue& cst, const SymbolVariable& symVar, AstNodeRef nodeRef, AstNodeRef nodeMemberRef);
    Result atIndex(Sema& sema, AstNodeRef nodeArgRef, ConstantRef cstRef, int64_t constIndex);
}

SWC_END_NAMESPACE();
