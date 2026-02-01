#pragma once
#include "Compiler/Sema/Symbol/SymbolMap.h"

SWC_BEGIN_NAMESPACE();

class SymbolFunction;

class SymbolInterface : public SymbolMapT<SymbolKind::Interface>
{
public:
    static constexpr auto K = SymbolKind::Interface;

    explicit SymbolInterface(const AstNode* decl, TokenRef tokRef, IdentifierRef idRef, const SymbolFlags& flags) :
        SymbolMapT(decl, tokRef, idRef, flags)
    {
    }

    std::vector<SymbolFunction*>&       methods() { return methods_; }
    const std::vector<SymbolFunction*>& methods() const { return methods_; }
    void                                addMethod(SymbolFunction* sym) { methods_.push_back(sym); }
    Result                              canBeCompleted(Sema& sema) const;

private:
    std::vector<SymbolFunction*> methods_;
};

SWC_END_NAMESPACE();
