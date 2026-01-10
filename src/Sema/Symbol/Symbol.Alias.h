#pragma once
#include "Sema/Symbol/Symbol.h"
#include "Sema/Type/TypeManager.h"

SWC_BEGIN_NAMESPACE();

class SymbolAlias : public Symbol
{
public:
    static constexpr auto K = SymbolKind::Alias;

    explicit SymbolAlias(const AstNode* decl, TokenRef tokRef, IdentifierRef idRef, const SymbolFlags& flags) :
        Symbol(decl, tokRef, K, idRef, flags)
    {
    }

    const Symbol* aliasedSymbol() const { return aliasedSymbol_; }
    void          setAliasedSymbol(const Symbol* sym) { aliasedSymbol_ = sym; }
    TypeRef       underlyingTypeRef() const { return underlyingTypeRef_; }
    void          setUnderlyingTypeRef(TypeRef ref) { underlyingTypeRef_ = ref; }
    bool          isStrict() const { return attributes().hasFlag(AttributeFlagsE::Strict); }
    uint64_t      sizeOf(TaskContext& ctx) const { return ctx.typeMgr().get(underlyingTypeRef()).sizeOf(ctx); }

private:
    const Symbol* aliasedSymbol_     = nullptr;
    TypeRef       underlyingTypeRef_ = TypeRef::invalid();
};

SWC_END_NAMESPACE();
