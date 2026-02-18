#pragma once
#include "Compiler/Sema/Symbol/SymbolMap.h"

SWC_BEGIN_NAMESPACE();

class SymbolModule : public SymbolMapT<SymbolKind::Module>
{
public:
    static constexpr SymbolKind K = SymbolKind::Module;

    explicit SymbolModule(const AstNode* decl, TokenRef tokRef, IdentifierRef idRef, const SymbolFlags& flags) :
        SymbolMapT(nullptr, TokenRef::invalid(), IdentifierRef::invalid(), SymbolFlagsE::Zero)
    {
        SWC_UNUSED(decl);
        SWC_UNUSED(tokRef);
        SWC_UNUSED(idRef);
        SWC_UNUSED(flags);
    }
};

class SymbolNamespace : public SymbolMapT<SymbolKind::Namespace>
{
public:
    static constexpr SymbolKind K = SymbolKind::Namespace;

    explicit SymbolNamespace(const AstNode* decl, TokenRef tokRef, IdentifierRef idRef, const SymbolFlags& flags) :
        SymbolMapT(decl, tokRef, idRef, flags)
    {
    }
};

SWC_END_NAMESPACE();
