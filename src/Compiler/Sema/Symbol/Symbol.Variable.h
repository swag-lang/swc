#pragma once
#include "Compiler/Sema/Symbol/Symbol.h"

SWC_BEGIN_NAMESPACE();

enum class SymbolVariableFlagsE : uint8_t
{
    Zero              = 0,
    Let               = 1 << 0,
    Initialized       = 1 << 1,
    ExplicitUndefined = 1 << 2,
    Parameter         = 1 << 3,
};
using SymbolVariableFlags = EnumFlags<SymbolVariableFlagsE>;

class SymbolVariable : public SymbolT<SymbolKind::Variable, SymbolVariableFlagsE>
{
public:
    static constexpr SymbolKind K = SymbolKind::Variable;

    explicit SymbolVariable(const AstNode* decl, TokenRef tokRef, IdentifierRef idRef, const SymbolFlags& flags) :
        SymbolT(decl, tokRef, idRef, flags)
    {
    }

    uint32_t    offset() const { return offset_; }
    void        setOffset(uint32_t offset) { offset_ = offset; }
    ConstantRef defaultValueRef() const { return defaultValueRef_; }
    void        setDefaultValueRef(ConstantRef ref) { defaultValueRef_ = ref; }

private:
    uint32_t    offset_          = 0;
    ConstantRef defaultValueRef_ = ConstantRef::invalid();
};

SWC_END_NAMESPACE();
