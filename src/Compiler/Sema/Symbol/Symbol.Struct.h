#pragma once
#include "Compiler/Sema/Helpers/SemaSpecOp.h"
#include "Compiler/Sema/Symbol/SymbolMap.h"

SWC_BEGIN_NAMESPACE();

class SymbolVariable;
class SymbolImpl;
class SymbolFunction;
class SymbolInterface;
class Sema;

enum class SymbolStructFlagsE : uint8_t
{
    Zero     = 0,
    TypeInfo = 1 << 0,
};
using SymbolStructFlags = EnumFlags<SymbolStructFlagsE>;

class SymbolStruct : public SymbolMapT<SymbolKind::Struct, SymbolStructFlagsE>
{
public:
    static constexpr SymbolKind K = SymbolKind::Struct;

    explicit SymbolStruct(const AstNode* decl, TokenRef tokRef, IdentifierRef idRef, const SymbolFlags& flags) :
        SymbolMapT(decl, tokRef, idRef, flags)
    {
    }

    SymbolStructFlags structFlags() const noexcept { return extraFlags(); }
    uint64_t          sizeOf() const { return sizeInBytes_; }
    uint32_t          alignment() const { return alignment_; }
    Result            canBeCompleted(Sema& sema) const;
    Result            registerSpecOps(Sema& sema) const;

    void                                addField(SymbolVariable* sym) { fields_.push_back(sym); }
    void                                removeIgnoredFields();
    std::vector<SymbolVariable*>&       fields() { return fields_; }
    const std::vector<SymbolVariable*>& fields() const { return fields_; }

    void                     addImpl(Sema& sema, SymbolImpl& symImpl);
    std::vector<SymbolImpl*> impls() const;

    void                     addInterface(SymbolImpl& symImpl);
    Result                   addInterface(Sema& sema, SymbolImpl& symImpl);
    std::vector<SymbolImpl*> interfaces() const;
    bool                     implementsInterface(const SymbolInterface& itf) const;
    bool                     implementsInterfaceOrUsingFields(Sema& sema, const SymbolInterface& itf) const;

    Result      computeLayout(TaskContext& ctx);
    ConstantRef computeDefaultValue(Sema& sema, TypeRef typeRef);

    SmallVector<SymbolFunction*> getSpecOp(IdentifierRef identifierRef) const;
    Result                       registerSpecOp(SymbolFunction& symFunc, SpecOpKind kind);
    const SymbolFunction*        opDrop() const { return opDrop_; }
    const SymbolFunction*        opPostCopy() const { return opPostCopy_; }
    const SymbolFunction*        opPostMove() const { return opPostMove_; }

private:
    std::vector<SymbolVariable*> fields_;
    mutable std::shared_mutex    mutexImpls_;
    std::vector<SymbolImpl*>     impls_;
    mutable std::shared_mutex    mutexInterfaces_;
    std::vector<SymbolImpl*>     interfaces_;
    mutable std::shared_mutex    mutexSpecOps_;
    std::vector<SymbolFunction*> specOps_;
    SymbolFunction*              opDrop_     = nullptr;
    SymbolFunction*              opPostCopy_ = nullptr;
    SymbolFunction*              opPostMove_ = nullptr;
    std::once_flag               defaultStructOnce_;
    ConstantRef                  defaultStructCst_ = ConstantRef::invalid();
    uint64_t                     sizeInBytes_      = 0;
    uint32_t                     alignment_        = 0;
};

SWC_END_NAMESPACE();
