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

    SemaNodeView(Sema& sema, AstNodeRef nodeRef);
    void   setCstRef(Sema& sema, ConstantRef cstRef);
    Result verifyUniqueSymbol(Sema& sema) const;
    void   getSymbols(SmallVector<Symbol*>& symbols) const;
};

SWC_END_NAMESPACE();
