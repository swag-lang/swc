#pragma once
#include "Sema/Symbol/Symbol.h"
#include "Sema/Constant/ConstantValue.h"

SWC_BEGIN_NAMESPACE();

class SymbolConstant : public Symbol
{
    ConstantRef cstRef_ = ConstantRef::invalid();

public:
    static constexpr auto K = SymbolKind::Constant;

    explicit SymbolConstant(const AstNode* decl, TokenRef tokRef, IdentifierRef idRef, const SymbolFlags& flags) :
        Symbol(decl, tokRef, K, idRef, flags)
    {
    }

    ConstantRef cstRef() const { return cstRef_; }
    void        setCstRef(ConstantRef cstRef) { cstRef_ = cstRef; }
};

SWC_END_NAMESPACE();
