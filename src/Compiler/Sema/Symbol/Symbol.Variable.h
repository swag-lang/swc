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
    static constexpr auto K = SymbolKind::Variable;
    static constexpr uint32_t K_INVALID_PARAMETER_INDEX = 0xFFFFFFFFu;

    explicit SymbolVariable(const AstNode* decl, TokenRef tokRef, IdentifierRef idRef, const SymbolFlags& flags) :
        SymbolT(decl, tokRef, idRef, flags)
    {
    }

    uint32_t    offset() const { return offset_; }
    void        setOffset(uint32_t offset) { offset_ = offset; }
    uint32_t    parameterIndex() const { return parameterIndex_; }
    bool        hasParameterIndex() const { return parameterIndex_ != K_INVALID_PARAMETER_INDEX; }
    void        setParameterIndex(uint32_t index) { parameterIndex_ = index; }
    ConstantRef defaultValueRef() const { return defaultValueRef_; }
    void        setDefaultValueRef(ConstantRef ref) { defaultValueRef_ = ref; }

private:
    uint32_t    offset_          = 0;
    uint32_t    parameterIndex_  = K_INVALID_PARAMETER_INDEX;
    ConstantRef defaultValueRef_ = ConstantRef::invalid();
};

SWC_END_NAMESPACE();
