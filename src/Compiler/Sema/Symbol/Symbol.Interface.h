#pragma once
#include "Compiler/Sema/Symbol/SymbolMap.h"

SWC_BEGIN_NAMESPACE();

class SymbolFunction;

class SymbolInterface : public SymbolMapT<SymbolKind::Interface>
{
public:
    static constexpr SymbolKind K = SymbolKind::Interface;

    explicit SymbolInterface(const AstNode* decl, TokenRef tokRef, IdentifierRef idRef, const SymbolFlags& flags) :
        SymbolMapT(decl, tokRef, idRef, flags)
    {
    }

    std::vector<SymbolFunction*>&       functions() { return functions_; }
    const std::vector<SymbolFunction*>& functions() const { return functions_; }
    void                                addFunction(SymbolFunction* sym);
    Result                              canBeCompleted(Sema& sema) const;

private:
    std::vector<SymbolFunction*> functions_;
};

SWC_END_NAMESPACE();
