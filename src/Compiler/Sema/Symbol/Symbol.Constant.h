#pragma once
#include "Compiler/Sema/Constant/ConstantValue.h"
#include "Compiler/Sema/Symbol/Symbol.h"

SWC_BEGIN_NAMESPACE();

class SymbolConstant : public SymbolT<SymbolKind::Const>
{
    ConstantRef cstRef_ = ConstantRef::invalid();

public:
    static constexpr auto K = SymbolKind::Const;

    explicit SymbolConstant(const AstNode* decl, TokenRef tokRef, IdentifierRef idRef, const SymbolFlags& flags) :
        SymbolT(decl, tokRef, idRef, flags)
    {
    }

    ConstantRef cstRef() const { return cstRef_; }
    void        setCstRef(ConstantRef cstRef) { cstRef_ = cstRef; }
};

SWC_END_NAMESPACE();
