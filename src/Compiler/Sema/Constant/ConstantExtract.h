#pragma once
#include "Compiler/Parser/Ast/AstNode.h"

SWC_BEGIN_NAMESPACE();

class Sema;
class SymbolVariable;
class ConstantValue;

namespace ConstantExtract
{
    Result structMember(Sema& sema, const ConstantValue& cst, const SymbolVariable& symVar, ConstantRef& outCstRef, AstNodeRef nodeMemberRef);
    Result structMember(Sema& sema, const ConstantValue& cst, const SymbolVariable& symVar, AstNodeRef nodeRef, AstNodeRef nodeMemberRef);
    Result atIndex(Sema& sema, const ConstantValue& cst, int64_t constIndex, AstNodeRef nodeArgRef, ConstantRef& outCstRef);
    Result atIndex(Sema& sema, const ConstantValue& cst, int64_t constIndex, AstNodeRef nodeArgRef);
}

SWC_END_NAMESPACE();
