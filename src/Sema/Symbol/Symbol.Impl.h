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

    SymbolStruct* symStruct() const { return symStruct_; }
    void          setSymStruct(SymbolStruct* sym) { symStruct_ = sym; }

private:
    SymbolStruct* symStruct_ = nullptr;
};

SWC_END_NAMESPACE();
