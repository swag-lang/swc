#pragma once
#include "Parser/AstNode.h"
#include "Sema/Constant/ConstantValue.h"

SWC_BEGIN_NAMESPACE()
class Symbol;
class Sema;
class ConstantValue;
class TypeInfo;

struct SemaNodeView
{
    const AstNode*       node    = nullptr;
    const ConstantValue* cst     = nullptr;
    const TypeInfo*      type    = nullptr;
    Symbol*              sym     = nullptr;
    std::span<Symbol*>   symList = {};

    AstNodeRef  nodeRef = AstNodeRef::invalid();
    ConstantRef cstRef  = ConstantRef::invalid();
    TypeRef     typeRef = TypeRef::invalid();

    SemaNodeView(Sema& sema, AstNodeRef ref);
    void   setCstRef(Sema& sema, ConstantRef ref);
    void   getSymbols(SmallVector<Symbol*>& symbols) const;
};

SWC_END_NAMESPACE();
