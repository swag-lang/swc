#pragma once
#include "Compiler/Sema/Generic/GenericInstanceStorage.h"
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
    Zero            = 0,
    TypeInfo        = 1 << 0,
    GenericRoot     = 1 << 1,
    GenericInstance = 1 << 2,
};
using SymbolStructFlags = EnumFlags<SymbolStructFlagsE>;

class SymbolStruct : public SymbolMapT<SymbolKind::Struct, SymbolStructFlagsE>
{
public:
    static constexpr auto K = SymbolKind::Struct;

    explicit SymbolStruct(const AstNode* decl, TokenRef tokRef, IdentifierRef idRef, const SymbolFlags& flags) :
        SymbolMapT(decl, tokRef, idRef, flags)
    {
    }

    SymbolStructFlags structFlags() const noexcept { return extraFlags(); }
    uint64_t          sizeOf() const { return sizeInBytes_; }
    uint32_t          alignment() const { return alignment_; }
    AstNodeRef        declNodeRef() const noexcept { return declNodeRef_; }
    void              setDeclNodeRef(AstNodeRef nodeRef) noexcept { declNodeRef_ = nodeRef; }
    Result            canBeCompleted(Sema& sema) const;
    Result            registerSpecOps(Sema& sema) const;

    void                                addField(SymbolVariable* sym);
    void                                removeIgnoredFields();
    std::vector<SymbolVariable*>&       fields() { return fields_; }
    const std::vector<SymbolVariable*>& fields() const { return fields_; }

    void                     addImpl(Sema& sema, SymbolImpl& symImpl);
    std::vector<SymbolImpl*> impls() const;

    void                     addInterface(SymbolImpl& symImpl);
    Result                   addInterface(Sema& sema, SymbolImpl& symImpl);
    std::vector<SymbolImpl*> interfaces() const;
    const SymbolImpl*        findInterfaceImpl(IdentifierRef interfaceIdRef) const;
    bool                     implementsInterface(const SymbolInterface& itf) const;
    bool                     implementsInterfaceOrUsingFields(Sema& sema, const SymbolInterface& itf) const;

    Result      computeLayout(TaskContext& ctx);
    ConstantRef computeDefaultValue(Sema& sema, TypeRef typeRef);

    SmallVector<SymbolFunction*> getSpecOp(IdentifierRef identifierRef) const;
    Result                       registerSpecOp(SymbolFunction& symFunc, SpecOpKind kind);
    SymbolFunction*              opDrop() { return opDrop_; }
    const SymbolFunction*        opDrop() const { return opDrop_; }
    SymbolFunction*              opPostCopy() { return opPostCopy_; }
    const SymbolFunction*        opPostCopy() const { return opPostCopy_; }
    SymbolFunction*              opPostMove() { return opPostMove_; }
    const SymbolFunction*        opPostMove() const { return opPostMove_; }

    bool                          isGenericRoot() const noexcept { return hasExtraFlag(SymbolStructFlagsE::GenericRoot); }
    void                          setGenericRoot(bool value) noexcept;
    bool                          isGenericInstance() const noexcept { return hasExtraFlag(SymbolStructFlagsE::GenericInstance); }
    void                          setGenericInstance(SymbolStruct* root) noexcept;
    SymbolStruct*                 genericRootSym() noexcept;
    const SymbolStruct*           genericRootSym() const noexcept;
    bool                          tryGetGenericInstanceArgs(const SymbolStruct& instance, SmallVector<GenericInstanceKey>& outArgs) const;
    GenericInstanceStorage&       genericInstanceStorage() noexcept;
    const GenericInstanceStorage& genericInstanceStorage() const noexcept;
    void                          setGenericCompletionOwner(const TaskContext& ctx) noexcept;
    bool                          isGenericCompletionOwner(const TaskContext& ctx) const noexcept;
    bool                          tryStartGenericCompletion(const TaskContext& ctx) const noexcept;
    void                          finishGenericCompletion() const noexcept;
    bool                          isGenericNodeCompleted() const noexcept;
    void                          setGenericNodeCompleted() const noexcept;

private:
    struct GenericData;

    GenericData& ensureGenericData() const noexcept;
    GenericData* genericData() const noexcept;

    std::vector<SymbolVariable*>      fields_;
    mutable std::shared_mutex         mutexImpls_;
    std::vector<SymbolImpl*>          impls_;
    mutable std::shared_mutex         mutexInterfaces_;
    std::vector<SymbolImpl*>          interfaces_;
    mutable std::shared_mutex         mutexSpecOps_;
    std::vector<SymbolFunction*>      specOps_;
    std::once_flag                    defaultStructOnce_;
    SymbolFunction*                   opDrop_           = nullptr;
    SymbolFunction*                   opPostCopy_       = nullptr;
    SymbolFunction*                   opPostMove_       = nullptr;
    mutable std::atomic<GenericData*> genericData_      = nullptr;
    uint64_t                          sizeInBytes_      = 0;
    ConstantRef                       defaultStructCst_ = ConstantRef::invalid();
    uint32_t                          alignment_        = 0;
    AstNodeRef                        declNodeRef_      = AstNodeRef::invalid();
};

SWC_END_NAMESPACE();
