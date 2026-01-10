#pragma once
#include "Parser/AstNodes.h"
#include "Sema/Symbol/SymbolMap.h"

SWC_BEGIN_NAMESPACE();

class SymbolVariable;

enum class SymbolFunctionFlagsE : uint8_t
{
    Zero      = 0,
    Closure   = 1 << 0,
    Method    = 1 << 1,
    Throwable = 1 << 2,
    Const     = 1 << 3,
};
using SymbolFunctionFlags = EnumFlags<SymbolFunctionFlagsE>;

class SymbolFunction : public SymbolMap
{
public:
    static constexpr auto K = SymbolKind::Function;

    explicit SymbolFunction(const AstNode* decl, TokenRef tokRef, IdentifierRef idRef, const SymbolFlags& flags) :
        SymbolMap(decl, tokRef, K, idRef, flags)
    {
    }

    TypeRef                       returnType() const { return returnType_; }
    void                          setReturnType(TypeRef typeRef) { returnType_ = typeRef; }
    std::vector<SymbolVariable*>& parameters() { return parameters_; }
    void                          addParameter(SymbolVariable* sym) { parameters_.push_back(sym); }
    Utf8                          computeName(const TaskContext& ctx) const;

    SymbolFunctionFlags funcFlags() const noexcept { return funcFlags_; }
    bool                hasFuncFlag(SymbolFunctionFlagsE flag) const noexcept { return funcFlags_.has(flag); }
    void                addFuncFlag(SymbolFunctionFlagsE fl) { funcFlags_.add(fl); }
    void                addFuncFlags(SymbolFunctionFlags fl) { funcFlags_.add(fl); }
    void                setFuncFlags(EnumFlags<AstFunctionFlagsE> parserFlags);
    bool                isClosure() const noexcept { return funcFlags_.has(SymbolFunctionFlagsE::Closure); }
    bool                isMethod() const noexcept { return funcFlags_.has(SymbolFunctionFlagsE::Method); }
    bool                isThrowable() const noexcept { return funcFlags_.has(SymbolFunctionFlagsE::Throwable); }

private:
    std::vector<SymbolVariable*> parameters_;
    TypeRef                      returnType_ = TypeRef::invalid();
    SymbolFunctionFlags          funcFlags_  = SymbolFunctionFlagsE::Zero;
};

SWC_END_NAMESPACE();
