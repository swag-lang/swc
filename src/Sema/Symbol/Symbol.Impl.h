#pragma once
#include "Sema/Symbol/SymbolMap.h"

SWC_BEGIN_NAMESPACE();

class SymbolStruct;

class SymbolImpl : public SymbolMap
{
public:
    static constexpr auto K = SymbolKind::Impl;

    explicit SymbolImpl(const AstNode* decl, TokenRef tokRef, IdentifierRef idRef, const SymbolFlags& flags) :
        SymbolMap(decl, tokRef, K, idRef, flags)
    {
    }

    SymbolStruct* structSym() const { return structSym_; }
    void          setStructSym(SymbolStruct* sym) { structSym_ = sym; }

private:
    SymbolStruct* structSym_ = nullptr;
};

SWC_END_NAMESPACE();
