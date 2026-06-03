#pragma once
#include "Compiler/Sema/Generic/GenericInstanceStorage.h"
#include "Compiler/Sema/Helpers/SemaClone.h"
#include "Compiler/Sema/Helpers/SemaSpecOp.h"
#include "Compiler/Sema/Symbol/SymbolMap.h"

SWC_BEGIN_NAMESPACE();

class SymbolVariable;
class SymbolImpl;
class SymbolFunction;
class SymbolInterface;
class Sema;
class TaskContext;

struct SymbolStructUsingPathStep
{
    const SymbolVariable* field     = nullptr;
    bool                  isPointer = false;
};

enum class SymbolStructFlagsE : uint8_t
{
    Zero                = 0,
    TypeInfo            = 1 << 0,
    GenericRoot         = 1 << 1,
    GenericInstance     = 1 << 2,
    Union               = 1 << 3,
    DefaultClassified   = 1 << 4,
    DefaultAllZero      = 1 << 5,
    DefaultAllUndefined = 1 << 6,
    DefaultHasUndefined = 1 << 7,
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
    uint64_t          sizeOf() const;
    uint32_t          alignment() const;
    AstNodeRef        declNodeRef() const noexcept { return declNodeRef_; }
    void              setDeclNodeRef(AstNodeRef nodeRef) noexcept { declNodeRef_ = nodeRef; }
    Result            canBeCompleted(Sema& sema) const;
    Result            registerSpecOps(Sema& sema) const;

    void                                addField(SymbolVariable* sym);
    void                                removeIgnoredFields();
    std::vector<SymbolVariable*>&       fields() { return fields_; }
    const std::vector<SymbolVariable*>& fields() const { return fields_; }
    bool                                tryGetFieldIndex(size_t& outIndex, const SymbolVariable& sym) const noexcept;

    void                         addImpl(Sema& sema, SymbolImpl& symImpl);
    std::vector<SymbolImpl*>     impls() const;
    std::vector<SymbolFunction*> declaredMethods() const;
    std::vector<SymbolFunction*> methods() const;

    void                     addInterface(SymbolImpl& symImpl);
    Result                   addInterface(Sema& sema, SymbolImpl& symImpl);
    std::vector<SymbolImpl*> interfaces() const;
    const SymbolImpl*        findInterfaceImpl(IdentifierRef interfaceIdRef) const;
    bool                     implementsInterface(const SymbolInterface& itf) const;
    bool                     implementsInterfaceOrUsingFields(Sema& sema, const SymbolInterface& itf) const;
    bool                     resolveUsingFieldPath(const TaskContext& ctx, const SymbolStruct& targetStruct, SmallVector<SymbolStructUsingPathStep>& outSteps) const;

    Result      computeLayout(TaskContext& ctx);
    ConstantRef computeDefaultValue(Sema& sema, TypeRef typeRef);
    void        computeImplicitDefaultFlags(Sema& sema) const;
    bool        hasImplicitAllZeroDefault() const noexcept { return hasExtraFlag(SymbolStructFlagsE::DefaultAllZero); }
    bool        hasImplicitAllUndefinedDefault() const noexcept { return hasExtraFlag(SymbolStructFlagsE::DefaultAllUndefined); }
    bool        hasImplicitUndefinedDefault() const noexcept { return hasExtraFlag(SymbolStructFlagsE::DefaultHasUndefined); }
    ConstantRef resolveImplicitDefaultValueRef(Sema& sema, TypeRef typeRef) const;

    SmallVector<SymbolFunction*> getSpecOp(IdentifierRef identifierRef) const;
    Result                       registerSpecOp(SymbolFunction& symFunc, SpecOpKind kind);
    SymbolFunction*              opDrop() { return opDrop_; }
    const SymbolFunction*        opDrop() const { return opDrop_; }
    SymbolFunction*              opPostCopy() { return opPostCopy_; }
    const SymbolFunction*        opPostCopy() const { return opPostCopy_; }
    SymbolFunction*              opPostMove() { return opPostMove_; }
    const SymbolFunction*        opPostMove() const { return opPostMove_; }
    const SymbolFunction*        effectiveOpInit(const TaskContext& ctx) const;
    const SymbolFunction*        effectiveOpDrop(const TaskContext& ctx) const;
    const SymbolFunction*        effectiveOpPostCopy(const TaskContext& ctx) const;
    const SymbolFunction*        effectiveOpPostMove(const TaskContext& ctx) const;
    bool                         hasConcreteLayout() const noexcept;

    bool                          isGenericRoot() const noexcept { return hasExtraFlag(SymbolStructFlagsE::GenericRoot); }
    void                          setGenericRoot(bool value) noexcept;
    bool                          isGenericInstance() const noexcept { return hasExtraFlag(SymbolStructFlagsE::GenericInstance); }
    bool                          isUnion() const noexcept { return hasExtraFlag(SymbolStructFlagsE::Union); }
    void                          setGenericInstance(SymbolStruct* root) noexcept;
    bool                          sameGenericFamily(const SymbolStruct& other) const noexcept;
    SymbolStruct*                 genericRootOrSelf() noexcept;
    const SymbolStruct*           genericRootOrSelf() const noexcept;
    SymbolStruct*                 genericRootSym() noexcept;
    const SymbolStruct*           genericRootSym() const noexcept;
    AstNodeRef                    findGenericEvalNode(const NodePayload* payloadContext, const Ast& ownerAst, AstNodeRef sourceRef, std::span<const SemaClone::ParamBinding> bindings) const;
    void                          cacheGenericEvalNode(const NodePayload* payloadContext, const Ast& ownerAst, AstNodeRef sourceRef, std::span<const SemaClone::ParamBinding> bindings, AstNodeRef evalRef) const;
    std::recursive_mutex&         genericEvalRunMutex() const noexcept;
    bool                          tryGetGenericInstanceArgs(SmallVector<GenericInstanceKey>& outArgs) const;
    bool                          tryGetGenericInstanceArgs(const SymbolStruct& instance, SmallVector<GenericInstanceKey>& outArgs) const;
    GenericInstanceStorage&       genericInstanceStorage() noexcept;
    const GenericInstanceStorage& genericInstanceStorage() const noexcept;
    void                          setGenericCompletionOwner(const TaskContext& ctx) const noexcept;
    bool                          isGenericCompletionOwner(const TaskContext& ctx) const noexcept;
    bool                          isGenericCompletionActive(const TaskContext& ctx) const noexcept;
    bool                          tryStartGenericCompletion(const TaskContext& ctx) const noexcept;
    void                          finishGenericCompletion() const noexcept;
    bool                          isGenericNodeCompleted() const noexcept;
    void                          setGenericNodeCompleted() const noexcept;
    std::mutex&                   generatedLifecycleMutex() const noexcept { return generatedLifecycleMutex_; }
    std::mutex&                   generatedOperatorsMutex() const noexcept { return generatedOperatorsMutex_; }
    bool                          generatedLifecyclePublished() const noexcept { return generatedLifecyclePublished_.load(std::memory_order_acquire); }
    bool                          generatedOperatorsPublished() const noexcept { return generatedOperatorsPublished_.load(std::memory_order_acquire); }
    void                          publishGeneratedLifecycle() const noexcept { generatedLifecyclePublished_.store(true, std::memory_order_release); }
    void                          publishGeneratedOperators() const noexcept { generatedOperatorsPublished_.store(true, std::memory_order_release); }
    bool                          tryMarkGeneratedLifecycleFunctions() const noexcept;
    bool                          tryMarkGeneratedOperators() const noexcept;

private:
    struct GenericData;

    GenericData& ensureGenericData() const noexcept;
    GenericData* genericData() const noexcept;
    void         rebuildFieldIndexMap() noexcept;

    std::vector<SymbolVariable*>                      fields_;
    std::unordered_map<const SymbolVariable*, size_t> fieldIndexMap_;
    mutable std::shared_mutex                         mutexImpls_;
    std::vector<SymbolImpl*>                          impls_;
    std::unordered_set<SymbolImpl*>                   implsSet_;
    mutable std::shared_mutex                         mutexInterfaces_;
    std::vector<SymbolImpl*>                          interfaces_;
    std::unordered_set<SymbolImpl*>                   interfacesSet_;
    mutable std::shared_mutex                         mutexSpecOps_;
    std::vector<SymbolFunction*>                      specOps_;
    std::unordered_set<SymbolFunction*>               specOpsSet_;
    mutable std::once_flag                            implicitDefaultFlagsOnce_;
    std::once_flag                                    defaultStructOnce_;
    SymbolFunction*                                   opDrop_     = nullptr;
    SymbolFunction*                                   opPostCopy_ = nullptr;
    SymbolFunction*                                   opPostMove_ = nullptr;
    mutable std::mutex                                generatedLifecycleMutex_;
    mutable std::mutex                                generatedOperatorsMutex_;
    mutable std::atomic<GenericData*>                 genericData_                 = nullptr;
    mutable std::atomic_bool                          generatedLifecycleDone_      = false;
    mutable std::atomic_bool                          generatedOperatorsDone_      = false;
    mutable std::atomic_bool                          generatedLifecyclePublished_ = false;
    mutable std::atomic_bool                          generatedOperatorsPublished_ = false;
    uint64_t                                          sizeInBytes_                 = 0;
    ConstantRef                                       defaultStructCst_            = ConstantRef::invalid();
    uint32_t                                          alignment_                   = 0;
    AstNodeRef                                        declNodeRef_                 = AstNodeRef::invalid();
};

SWC_END_NAMESPACE();
