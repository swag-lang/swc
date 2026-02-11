#pragma once
#include "Compiler/Parser/Ast/AstNodes.h"
#include "Compiler/Sema/Helpers/SemaSpecOp.h"
#include "Compiler/Sema/Symbol/SymbolMap.h"

SWC_BEGIN_NAMESPACE();

class SymbolVariable;
class SymbolStruct;

enum class SymbolFunctionFlagsE : uint8_t
{
    Zero      = 0,
    Closure   = 1 << 0,
    Method    = 1 << 1,
    Throwable = 1 << 2,
    Const     = 1 << 3,
    Empty     = 1 << 4,
    Pure      = 1 << 5,
};
using SymbolFunctionFlags = EnumFlags<SymbolFunctionFlagsE>;

class SymbolFunction : public SymbolMapT<SymbolKind::Function, SymbolFunctionFlagsE>
{
public:
    static constexpr auto K = SymbolKind::Function;

    enum class PurityState : uint8_t
    {
        Unknown,
        Pure,
        Impure,
    };

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
    SymbolStruct*                       ownerStruct();
    const SymbolStruct*                 ownerStruct() const;

    void       setExtraFlags(EnumFlags<AstFunctionFlagsE> parserFlags);
    bool       isClosure() const noexcept { return hasExtraFlag(SymbolFunctionFlagsE::Closure); }
    bool       isMethod() const noexcept { return hasExtraFlag(SymbolFunctionFlagsE::Method); }
    bool       isThrowable() const noexcept { return hasExtraFlag(SymbolFunctionFlagsE::Throwable); }
    bool       isConst() const noexcept { return hasExtraFlag(SymbolFunctionFlagsE::Const); }
    bool       isEmpty() const noexcept { return hasExtraFlag(SymbolFunctionFlagsE::Empty); }
    bool       isPure() const noexcept { return hasExtraFlag(SymbolFunctionFlagsE::Pure); }
    void       setPure(bool value) { value ? addExtraFlag(SymbolFunctionFlagsE::Pure) : removeExtraFlag(SymbolFunctionFlagsE::Pure); }
    void       resetPurity() noexcept { purityState_ = PurityState::Unknown; }
    void       markImpure() noexcept { purityState_ = PurityState::Impure; }
    bool       isImpure() const noexcept { return purityState_ == PurityState::Impure; }
    SpecOpKind specOpKind() const noexcept { return specOpKind_; }
    void       setSpecOpKind(SpecOpKind kind) noexcept { specOpKind_ = kind; }

private:
    std::vector<SymbolVariable*> parameters_;
    TypeRef                      returnType_  = TypeRef::invalid();
    SpecOpKind                   specOpKind_  = SpecOpKind::None;
    PurityState                  purityState_ = PurityState::Unknown;
};

SWC_END_NAMESPACE();
