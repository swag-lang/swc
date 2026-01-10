#pragma once
#include "Sema/Symbol/SymbolMap.h"

SWC_BEGIN_NAMESPACE();

class SymbolModule : public SymbolMap
{
public:
    static constexpr auto K = SymbolKind::Module;

    explicit SymbolModule(const AstNode*, TokenRef, IdentifierRef, const SymbolFlags&) :
        SymbolMap(nullptr, TokenRef::invalid(), K, IdentifierRef::invalid(), SymbolFlagsE::Zero)
    {
    }
};

class SymbolNamespace : public SymbolMap
{
public:
    static constexpr auto K = SymbolKind::Namespace;

    explicit SymbolNamespace(const AstNode* decl, TokenRef tokRef, IdentifierRef idRef, const SymbolFlags& flags) :
        SymbolMap(decl, tokRef, K, idRef, flags)
    {
    }
};

SWC_END_NAMESPACE();
