#pragma once
#include "Compiler/Sema/Symbol/SymbolMap.h"
#include "Support/Core/RefTypes.h"
#include "Support/Core/Result.h"

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

    std::vector<SymbolFunction*>&       functions() { return functions_; }
    const std::vector<SymbolFunction*>& functions() const { return functions_; }

    void   addFunction(SymbolFunction* sym);
    Result canBeCompleted(Sema& sema) const;

    // 'interface I is Base': every implementation starts with 'Base', so an 'I' value is a
    // pointer to it. Valid once the interface is complete.
    TypeRef baseTypeRef() const { return baseTypeRef_; }
    void    setBaseTypeRef(TypeRef typeRef) { baseTypeRef_ = typeRef; }

private:
    std::vector<SymbolFunction*> functions_;
    TypeRef                      baseTypeRef_ = TypeRef::invalid();
};

SWC_END_NAMESPACE();
