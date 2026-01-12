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

class SymbolImpl : public SymbolMapT<SymbolKind::Impl>
{
public:
    static constexpr auto K = SymbolKind::Impl;

    explicit SymbolImpl(const AstNode* decl, TokenRef tokRef, IdentifierRef idRef, const SymbolFlags& flags) :
        SymbolMapT(decl, tokRef, idRef, flags)
    {
    }

    SymbolImplOwnerKind ownerKind() const { return static_cast<SymbolImplOwnerKind>(extraFlags()); }
    bool                isForStruct() const { return ownerKind() == SymbolImplOwnerKind::Struct; }
    bool                isForEnum() const { return ownerKind() == SymbolImplOwnerKind::Enum; }

    SymbolStruct* symStruct() const
    {
        SWC_ASSERT(ownerKind() == SymbolImplOwnerKind::Struct);
        return ownerStruct_;
    }

    void setSymStruct(SymbolStruct* sym)
    {
        extraFlags() = static_cast<uint8_t>(SymbolImplOwnerKind::Struct);
        ownerStruct_ = sym;
    }

    SymbolEnum* symEnum() const
    {
        SWC_ASSERT(ownerKind() == SymbolImplOwnerKind::Enum);
        return ownerEnum_;
    }

    void setSymEnum(SymbolEnum* sym)
    {
        extraFlags() = static_cast<uint8_t>(SymbolImplOwnerKind::Enum);
        ownerEnum_   = sym;
    }

private:
    union
    {
        SymbolStruct* ownerStruct_ = nullptr;
        SymbolEnum*   ownerEnum_;
    };
};

SWC_END_NAMESPACE();
