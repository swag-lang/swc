#pragma once
#include "Compiler/Sema/Symbol/SymbolMap.h"

SWC_BEGIN_NAMESPACE();

class SymbolModule : public SymbolMapT<SymbolKind::Module>
{
public:
    static constexpr auto K = SymbolKind::Module;

    explicit SymbolModule(const AstNode* decl, TokenRef tokRef, IdentifierRef idRef, const SymbolFlags& flags) :
        SymbolMapT(nullptr, TokenRef::invalid(), IdentifierRef::invalid(), SymbolFlagsE::Zero)
    {
        SWC_UNSED(decl);
        SWC_UNSED(tokRef);
        SWC_UNSED(idRef);
        SWC_UNSED(flags);
    }
};

class SymbolNamespace : public SymbolMapT<SymbolKind::Namespace>
{
public:
    static constexpr auto K = SymbolKind::Namespace;

    explicit SymbolNamespace(const AstNode* decl, TokenRef tokRef, IdentifierRef idRef, const SymbolFlags& flags) :
        SymbolMapT(decl, tokRef, idRef, flags)
    {
    }
};

SWC_END_NAMESPACE();
