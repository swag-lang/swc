#pragma once
#include "Compiler/Parser/Ast/AstNodes.h"
#include "Compiler/Sema/Symbol/SymbolMap.h"

SWC_BEGIN_NAMESPACE();

class SymbolVariable;

enum class SymbolFunctionFlagsE : uint8_t
{
    Zero      = 0,
    Closure   = 1 << 0,
    Method    = 1 << 1,
    Throwable = 1 << 2,
    Const     = 1 << 3,
    Empty     = 1 << 4,
    SpecOpValidated = 1 << 5,
};
using SymbolFunctionFlags = EnumFlags<SymbolFunctionFlagsE>;

class SymbolFunction : public SymbolMapT<SymbolKind::Function, SymbolFunctionFlagsE>
{
public:
    static constexpr auto K = SymbolKind::Function;

    explicit SymbolFunction(const AstNode* decl, TokenRef tokRef, IdentifierRef idRef, const SymbolFlags& flags) :
        SymbolMapT(decl, tokRef, idRef, flags)
    {
    }

    TypeRef                             returnTypeRef() const { return returnType_; }
    void                                setReturnTypeRef(TypeRef typeRef) { returnType_ = typeRef; }
    const std::vector<SymbolVariable*>& parameters() const { return parameters_; }
    std::vector<SymbolVariable*>&       parameters() { return parameters_; }
    void                                addParameter(SymbolVariable* sym) { parameters_.push_back(sym); }
    Utf8                                computeName(const TaskContext& ctx) const;
    bool                                deepCompare(const SymbolFunction& otherFunc) const noexcept;

    void setExtraFlags(EnumFlags<AstFunctionFlagsE> parserFlags);
    bool isClosure() const noexcept { return hasExtraFlag(SymbolFunctionFlagsE::Closure); }
    bool isMethod() const noexcept { return hasExtraFlag(SymbolFunctionFlagsE::Method); }
    bool isThrowable() const noexcept { return hasExtraFlag(SymbolFunctionFlagsE::Throwable); }
    bool isConst() const noexcept { return hasExtraFlag(SymbolFunctionFlagsE::Const); }
    bool isEmpty() const noexcept { return hasExtraFlag(SymbolFunctionFlagsE::Empty); }

private:
    std::vector<SymbolVariable*> parameters_;
    TypeRef                      returnType_ = TypeRef::invalid();
};

SWC_END_NAMESPACE();
