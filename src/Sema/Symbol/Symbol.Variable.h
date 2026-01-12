#pragma once
#include "Sema/Symbol/Symbol.h"

SWC_BEGIN_NAMESPACE();

enum class SymbolVariableFlagsE : uint8_t
{
    Zero              = 0,
    Let               = 1 << 0,
    Initialized       = 1 << 1,
    ExplicitUndefined = 1 << 2,
};
using SymbolVariableFlags = EnumFlags<SymbolVariableFlagsE>;

class SymbolVariable : public Symbol
{
public:
    static constexpr auto K = SymbolKind::Variable;

    explicit SymbolVariable(const AstNode* decl, TokenRef tokRef, IdentifierRef idRef, const SymbolFlags& flags) :
        Symbol(decl, tokRef, K, idRef, flags)
    {
    }

    uint32_t            offset() const { return offset_; }
    void                setOffset(uint32_t offset) { offset_ = offset; }
    SymbolVariableFlags varFlags() const noexcept { return varFlags_; }
    bool                hasVarFlag(SymbolVariableFlags flag) const noexcept { return varFlags_.has(flag); }
    void                addVarFlag(SymbolVariableFlags fl) { varFlags_.add(fl); }

private:
    SymbolVariableFlags varFlags_ = SymbolVariableFlagsE::Zero;
    uint32_t            offset_   = 0;
};

SWC_END_NAMESPACE();
