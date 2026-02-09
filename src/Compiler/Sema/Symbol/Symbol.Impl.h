#pragma once
#include "Compiler/Sema/Symbol/SymbolMap.h"

SWC_BEGIN_NAMESPACE();

class SymbolStruct;
class SymbolEnum;

enum class SymbolImplFlagsE : uint8_t
{
    Zero                        = 0,
    ForStruct                   = 1 << 0,
    ForEnum                     = 1 << 1,
    PendingRegistrationResolved = 1 << 7,
};
using SymbolImplFlags = EnumFlags<SymbolImplFlagsE>;

class SymbolImpl : public SymbolMapT<SymbolKind::Impl, SymbolImplFlagsE>
{
public:
    static constexpr auto K = SymbolKind::Impl;

    explicit SymbolImpl(const AstNode* decl, TokenRef tokRef, IdentifierRef idRef, const SymbolFlags& flags) :
        SymbolMapT(decl, tokRef, idRef, flags)
    {
    }

    bool isForStruct() const noexcept { return hasExtraFlag(SymbolImplFlagsE::ForStruct); }
    bool isForEnum() const noexcept { return hasExtraFlag(SymbolImplFlagsE::ForEnum); }
    bool isPendingRegistrationResolved() const noexcept { return hasExtraFlag(SymbolImplFlagsE::PendingRegistrationResolved); }
    void setPendingRegistrationResolved() noexcept { addExtraFlag(SymbolImplFlagsE::PendingRegistrationResolved); }

    SymbolStruct* symStruct() const;
    void          setSymStruct(SymbolStruct* sym);
    SymbolEnum*   symEnum() const;
    void          setSymEnum(SymbolEnum* sym);

    void addFunction(const TaskContext& ctx, SymbolFunction* sym);

private:
    std::vector<SymbolFunction*> specOps_;

    union
    {
        SymbolStruct* ownerStruct_ = nullptr;
        SymbolEnum*   ownerEnum_;
    };
};

SWC_END_NAMESPACE();
