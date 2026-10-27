#pragma once
#include "Compiler/Sema/Symbol/Symbol.h"
#include "Compiler/Sema/Type/TypeManager.h"
#include "Support/Core/RefTypes.h"

SWC_BEGIN_NAMESPACE();

class SymbolAlias : public SymbolT<SymbolKind::Alias>
{
public:
    static constexpr auto K = SymbolKind::Alias;

    explicit SymbolAlias(const AstNode* decl, TokenRef tokRef, IdentifierRef idRef, const SymbolFlags& flags) :
        SymbolT(decl, tokRef, idRef, flags)
    {
    }

    const Symbol* aliasedSymbol() const { return aliasedSymbol_; }
    void          setAliasedSymbol(const Symbol* sym) { aliasedSymbol_ = sym; }

    TypeRef underlyingTypeRef() const { return underlyingTypeRef_; }
    void    setUnderlyingTypeRef(TypeRef ref) { underlyingTypeRef_ = ref; }

    bool isStrict() const { return attributes().hasRtFlag(RtAttributeFlagsE::Strict); }

    // The strict alias an erased generic parameter ('T is Bound') is bound to in its single
    // instance. Its underlying type is the bound.
    bool isErasedParam() const { return erasedParam_; }
    void setErasedParam() { erasedParam_ = true; }

    uint64_t sizeOf(TaskContext& ctx) const { return ctx.typeMgr().get(underlyingTypeRef()).sizeOf(ctx); }
    uint32_t alignOf(TaskContext& ctx) const { return ctx.typeMgr().get(underlyingTypeRef()).alignOf(ctx); }

private:
    const Symbol* aliasedSymbol_     = nullptr;
    TypeRef       underlyingTypeRef_ = TypeRef::invalid();
    bool          erasedParam_       = false;
};

SWC_END_NAMESPACE();
