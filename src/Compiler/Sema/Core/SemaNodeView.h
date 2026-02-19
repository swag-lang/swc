#pragma once
#include "Compiler/Parser/Ast/AstNode.h"
#include "Compiler/Sema/Constant/ConstantValue.h"

SWC_BEGIN_NAMESPACE()
class Symbol;
class Sema;
class ConstantValue;
class TypeInfo;

enum class SemaNodeViewPartE
{
    Zero       = 0,
    Node       = 1 << 0,
    Type       = 1 << 1,
    Constant   = 1 << 2,
    Symbol     = 1 << 3,
    SymbolList = 1 << 4,
    All        = Node | Type | Constant | Symbol | SymbolList,
};
using SemaNodeViewPart = EnumFlags<SemaNodeViewPartE>;

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

    SemaNodeView(Sema& sema, AstNodeRef ref, SemaNodeViewPart part = SemaNodeViewPartE::All);
    void compute(Sema& sema, AstNodeRef ref, SemaNodeViewPart part = SemaNodeViewPartE::All);
    void setCstRef(Sema& sema, ConstantRef ref);
    void getSymbols(SmallVector<Symbol*>& symbols) const;
};

SWC_END_NAMESPACE();
