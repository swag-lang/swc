#pragma once
#include "Support/Core/Flags.h"
#include "Support/Core/RefTypes.h"
#include "Support/Core/SmallVector.h"

SWC_BEGIN_NAMESPACE()
class Symbol;
class Sema;
class ConstantValue;
class TypeInfo;
struct AstNode;

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

enum class SemaNodeViewResolveE : uint8_t
{
    Resolved,
    Stored,
};

struct SemaNodeView
{
    SemaNodeView(Sema& sema, AstNodeRef ref, SemaNodeViewPart part = SemaNodeViewPartE::All, SemaNodeViewResolveE mode = SemaNodeViewResolveE::Resolved);
    void    compute(Sema& sema, AstNodeRef ref, SemaNodeViewPart part = SemaNodeViewPartE::All, SemaNodeViewResolveE mode = SemaNodeViewResolveE::Resolved);
    void    computeInner(Sema& sema, AstNodeRef ref, SemaNodeViewPart part, SemaNodeViewResolveE mode);
    void    recompute(Sema& sema, SemaNodeViewPart part = SemaNodeViewPartE::All);
    void    getSymbols(SmallVector<Symbol*>& symbols) const;
    Symbol* singleSymbol() const;

    // A singleton span borrows this view's storage; keep the view alive while using it.
    std::span<Symbol* const> symbols() const&;
    std::span<Symbol* const> symbols() const&& = delete;

    const AstNode*           node() const;
    const AstNode*&          node();
    const ConstantValue*     cst() const;
    const ConstantValue*&    cst();
    const TypeInfo*          type() const;
    const TypeInfo*&         type();
    Symbol*                  sym() const;
    Symbol*&                 sym();
    std::span<Symbol* const> symList() const;
    std::span<Symbol*>&      symList();

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
    void assignSymbolList(std::span<Symbol*> symbols);
    bool loadResolvedSymbols(const Sema& sema, AstNodeRef targetRef, SemaNodeViewResolveE resolveMode);

    // Construction always calls computeInner, which initializes every field before resolution.
    // Primitive defaults would duplicate that initialization.
    const AstNode*       node_;
    const ConstantValue* cst_;
    const TypeInfo*      type_;
    Symbol*              sym_;
    std::span<Symbol*>   symList_ = {};
    bool                 hasSymbol_;
    bool                 hasSymList_;
    AstNodeRef           queryNodeRef_ = AstNodeRef::invalid();
    AstNodeRef           nodeRef_      = AstNodeRef::invalid();
    ConstantRef          cstRef_       = ConstantRef::invalid();
    TypeRef              typeRef_      = TypeRef::invalid();
    SemaNodeViewPart     computedPart_ = SemaNodeViewPartE::Zero;
    SemaNodeViewResolveE mode_;
};

SWC_END_NAMESPACE();
