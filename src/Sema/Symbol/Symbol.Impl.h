#pragma once
#include "Sema/Symbol/SymbolMap.h"

SWC_BEGIN_NAMESPACE();

class SymbolStruct;
class SymbolEnum;

enum class SymbolImplOwnerKind : uint8_t
{
    Struct,
    Enum,
};

class SymbolImpl : public SymbolMap
{
public:
    static constexpr auto K = SymbolKind::Impl;

    explicit SymbolImpl(const AstNode* decl, TokenRef tokRef, IdentifierRef idRef, const SymbolFlags& flags) :
        SymbolMap(decl, tokRef, K, idRef, flags)
    {
    }

    SymbolImplOwnerKind ownerKind() const { return ownerKind_; }
    bool                isForStruct() const { return ownerKind_ == SymbolImplOwnerKind::Struct; }
    bool                isForEnum() const { return ownerKind_ == SymbolImplOwnerKind::Enum; }

    SymbolStruct* symStruct() const
    {
        SWC_ASSERT(ownerKind_ == SymbolImplOwnerKind::Struct);
        return ownerStruct_;
    }

    void setSymStruct(SymbolStruct* sym)
    {
        ownerKind_   = SymbolImplOwnerKind::Struct;
        ownerStruct_ = sym;
    }

    SymbolEnum* symEnum() const
    {
        SWC_ASSERT(ownerKind_ == SymbolImplOwnerKind::Enum);
        return ownerEnum_;
    }

    void setSymEnum(SymbolEnum* sym)
    {
        ownerKind_ = SymbolImplOwnerKind::Enum;
        ownerEnum_ = sym;
    }

private:
    union
    {
        SymbolStruct* ownerStruct_ = nullptr;
        SymbolEnum*   ownerEnum_;
    };

    SymbolImplOwnerKind ownerKind_ = SymbolImplOwnerKind::Struct;
};

SWC_END_NAMESPACE();
