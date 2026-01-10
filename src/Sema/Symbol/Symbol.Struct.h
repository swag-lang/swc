#pragma once
#include "Sema/Symbol/SymbolMap.h"

SWC_BEGIN_NAMESPACE();

class SymbolVariable;
class SymbolImpl;

enum class SymbolStructFlagsE : uint8_t
{
    Zero     = 0,
    TypeInfo = 1 << 0,
};
using SymbolStructFlags = EnumFlags<SymbolStructFlagsE>;

class SymbolStruct : public SymbolMap
{
public:
    static constexpr auto K = SymbolKind::Struct;

    explicit SymbolStruct(const AstNode* decl, TokenRef tokRef, IdentifierRef idRef, const SymbolFlags& flags) :
        SymbolMap(decl, tokRef, K, idRef, flags)
    {
    }

    uint64_t                            sizeOf() const { return sizeInBytes_; }
    uint32_t                            alignment() const { return alignment_; }
    std::vector<SymbolVariable*>&       fields() { return fields_; }
    const std::vector<SymbolVariable*>& fields() const { return fields_; }
    Result                              canBeCompleted(Sema& sema) const;
    void                                computeLayout(Sema& sema);
    void                                addField(SymbolVariable* sym) { fields_.push_back(sym); }
    void                                addImpl(SymbolImpl& symImpl);
    std::vector<SymbolImpl*>            impls() const;
    SymbolStructFlags                   structFlags() const noexcept { return structFlags_; }
    bool                                hasStructFlag(SymbolStructFlagsE flag) const noexcept { return structFlags_.has(flag); }
    void                                addStructFlag(SymbolStructFlagsE fl) { structFlags_.add(fl); }

private:
    std::vector<SymbolVariable*> fields_;
    mutable std::shared_mutex    mutexImpls_;
    std::vector<SymbolImpl*>     impls_;
    uint64_t                     sizeInBytes_ = 0;
    uint32_t                     alignment_   = 0;
    SymbolStructFlags            structFlags_ = SymbolStructFlagsE::Zero;
};

SWC_END_NAMESPACE();
