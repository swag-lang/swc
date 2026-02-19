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
    Zero     = 0,
    Node     = 1 << 0,
    Type     = 1 << 1,
    Constant = 1 << 2,
    Symbol   = 1 << 3,
    All      = Node | Type | Constant | Symbol,
};
using SemaNodeViewPart = EnumFlags<SemaNodeViewPartE>;

struct SemaNodeView
{
    SemaNodeView(Sema& sema, AstNodeRef ref, SemaNodeViewPart part = SemaNodeViewPartE::All);
    void compute(Sema& sema, AstNodeRef ref, SemaNodeViewPart part = SemaNodeViewPartE::All);
    void recompute(Sema& sema, SemaNodeViewPart part = SemaNodeViewPartE::All);
    void getSymbols(SmallVector<Symbol*>& symbols) const;

    const AstNode*        node() const;
    const AstNode*&       node();
    const ConstantValue*  cst() const;
    const ConstantValue*& cst();
    const TypeInfo*       type() const;
    const TypeInfo*&      type();
    Symbol*               sym() const;
    Symbol*&              sym();
    std::span<Symbol*>    symList() const;
    std::span<Symbol*>&   symList();

    AstNodeRef   nodeRef() const;
    AstNodeRef&  nodeRef();
    ConstantRef  cstRef() const;
    ConstantRef& cstRef();
    TypeRef      typeRef() const;
    TypeRef&     typeRef();
    bool         hasType() const;
    bool         hasConstant() const;
    bool         hasSymbol() const;
    bool         hasSymbolList() const;

private:
    const AstNode*       node_         = nullptr;
    const ConstantValue* cst_          = nullptr;
    const TypeInfo*      type_         = nullptr;
    Symbol*              sym_          = nullptr;
    std::span<Symbol*>   symList_      = {};
    bool                 hasSymbol_    = false;
    bool                 hasSymList_   = false;
    AstNodeRef           nodeRef_      = AstNodeRef::invalid();
    ConstantRef          cstRef_       = ConstantRef::invalid();
    TypeRef              typeRef_      = TypeRef::invalid();
    SemaNodeViewPart     computedPart_ = SemaNodeViewPartE::Zero;
};

SWC_END_NAMESPACE();
