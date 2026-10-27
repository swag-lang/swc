#pragma once
#include "Compiler/Sema/Generic/GenericInstanceKey.h"
#include "Compiler/Sema/Generic/GenericInstanceOrigin.h"
#include "Compiler/Sema/Helpers/SemaCloneTypes.h"
#include "Compiler/Sema/Helpers/SemaSpecOpKind.h"
#include "Compiler/Sema/Symbol/SymbolMap.h"
#include "Support/Core/Flags.h"
#include "Support/Core/PointerSet.h"
#include "Support/Core/RefTypes.h"
#include "Support/Core/Result.h"
#include "Support/Core/SmallVector.h"

SWC_BEGIN_NAMESPACE();

class GenericInstanceStorage;
class SymbolVariable;
class SymbolImpl;
class SymbolFunction;
class SymbolInterface;
class Sema;
class TaskContext;
class TypeInfo;

struct SymbolStructUsingPathStep
{
    const SymbolVariable* field     = nullptr;
    bool                  isPointer = false;
};

// The tag values that make one member of a tagged union active.
struct SymbolStructTaggedCase
{
    const SymbolVariable*  member = nullptr;
    std::span<ConstantRef> values;
};

enum class SymbolStructFlagsE : uint16_t
{
    Zero                = 0,
    TypeInfo            = 1 << 0,
    GenericRoot         = 1 << 1,
    GenericInstance     = 1 << 2,
    Union               = 1 << 3,
    DefaultClassified   = 1 << 4,
    DefaultAllZero      = 1 << 5,
    DefaultRuntime      = 1 << 6,
    Tagged              = 1 << 7, // a union whose enum tag selects the active member
    DefaultRequiresInit = 1 << 8,
    Anonymous           = 1 << 9, // declared without a name, so its members are reached through the enclosing type
    OwnDynamicSlot      = 1 << 10,
    DynamicStorage      = 1 << 11,
    UsingField          = 1 << 12, // at least one field was declared with `using`; a removed field leaves it set
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

    uint64_t sizeOf() const;
    uint32_t alignment() const;

    AstNodeRef declNodeRef() const noexcept { return declNodeRef_; }
    void       setDeclNodeRef(AstNodeRef nodeRef) noexcept { declNodeRef_ = nodeRef; }

    Result canBeCompleted(Sema& sema) const;
    Result registerSpecOps(Sema& sema) const;

    void addField(SymbolVariable* sym);
    void removeIgnoredFields();

    std::vector<SymbolVariable*>&       fields() { return fields_; }
    const std::vector<SymbolVariable*>& fields() const { return fields_; }

    bool                  mayHaveUsingField() const noexcept { return hasExtraFlag(SymbolStructFlagsE::UsingField); }
    bool                  tryGetFieldIndex(size_t& outIndex, const SymbolVariable& sym) const noexcept;
    bool                  tryGetFieldIndexByName(size_t& outIndex, IdentifierRef name) const noexcept;
    const SymbolVariable* findFieldByName(IdentifierRef name) const noexcept;

    void           addImpl(Sema& sema, SymbolImpl& symImpl);
    SymbolImplList impls() const { return impls_.snapshot(); }

    template<typename F>
    void forEachImpl(const F& fn) const
    {
        impls_.forEach(fn);
    }

    std::vector<SymbolFunction*> declaredMethods() const;
    Result                       waitPendingImplMembers(Sema& sema, const SourceCodeRef& codeRef) const;
    std::vector<SymbolFunction*> methods() const;

    void              addInterface(SymbolImpl& symImpl);
    Result            addInterface(Sema& sema, SymbolImpl& symImpl);
    SymbolImplList    interfaces() const;
    const SymbolImpl* findInterfaceImpl(IdentifierRef interfaceIdRef) const;
    const SymbolImpl* findInterfaceImplOrUsingFields(const TaskContext& ctx, const SymbolInterface& itf) const;
    bool              implementsInterface(const SymbolInterface& itf) const;
    bool              implementsInterfaceOrUsingFields(Sema& sema, const SymbolInterface& itf) const;

    bool        resolveUsingFieldPath(const TaskContext& ctx, const SymbolStruct& targetStruct, SmallVector<SymbolStructUsingPathStep>& outSteps) const;
    bool        startsWith(const TaskContext& ctx, const SymbolStruct& base) const;
    static bool usingPathHasPointerStep(const SmallVector<SymbolStructUsingPathStep>& usingPath)
    {
        for (const auto& step : usingPath)
        {
            if (step.isPointer)
                return true;
        }

        return false;
    }

    Result computeLayout(TaskContext& ctx);

    bool                      isDynamic() const noexcept { return !dynamicSlotOffsets_.empty(); }
    bool                      hasOwnDynamicSlot() const noexcept { return hasExtraFlag(SymbolStructFlagsE::OwnDynamicSlot); }
    bool                      hasDynamicStorage() const noexcept { return hasExtraFlag(SymbolStructFlagsE::DynamicStorage); }
    std::span<const uint32_t> dynamicSlotOffsets() const noexcept { return dynamicSlotOffsets_; }

    Result computeDefaultValue(Sema& sema, TypeRef typeRef, ConstantRef& outRef);

    static Result prepareDynamicMetadata(Sema& sema, TypeRef typeRef);
    static bool   typeHasDynamicStorage(const TaskContext& ctx, const TypeInfo& type) { return dynamicStorageLeafType(ctx, type) != nullptr; }
    static Result initializeDynamicIdentityBytes(Sema& sema, std::span<std::byte> bytes, const TypeInfo& originalType);

    void computeImplicitDefaultFlags(Sema& sema) const;
    bool hasImplicitAllZeroDefault() const noexcept { return hasExtraFlag(SymbolStructFlagsE::DefaultAllZero); }
    bool requiresExplicitInitialization() const noexcept { return hasExtraFlag(SymbolStructFlagsE::DefaultRequiresInit); }
    bool hasRuntimeImplicitDefault() const noexcept { return hasExtraFlag(SymbolStructFlagsE::DefaultRuntime); }

    static bool   typeHasRuntimeImplicitDefault(Sema& sema, TypeRef typeRef);
    static Result waitTypeImplicitDefaultReady(Sema& sema, TypeRef typeRef, AstNodeRef waitNodeRef);
    static bool   typeRequiresExplicitInitialization(Sema& sema, TypeRef typeRef);
    static bool   typeHasCompleteImplicitDefault(Sema& sema, TypeRef typeRef);
    static bool   typeHasAllZeroImplicitDefault(Sema& sema, TypeRef typeRef);
    static bool   fieldRequiresExplicitInitialization(Sema& sema, const SymbolVariable& field);

    static Result lowerTypeImplicitDefaultBytes(Sema& sema, std::span<std::byte> dstBytes, TypeRef typeRef);
    Result        resolveImplicitDefaultValueRef(Sema& sema, TypeRef typeRef, ConstantRef& outRef) const;

    SmallVector<SymbolFunction*> getSpecOp(IdentifierRef identifierRef) const;
    Result                       registerSpecOp(SymbolFunction& symFunc, SpecOpKind kind);

    SymbolFunction*       selfEqualsFunction(TaskContext& ctx) const;
    SymbolFunction*       opDrop();
    const SymbolFunction* opDrop() const;
    SymbolFunction*       opPostCopy();
    const SymbolFunction* opPostCopy() const;
    SymbolFunction*       opPostMove();
    const SymbolFunction* opPostMove() const;

    const SymbolFunction* effectiveOpInit(const TaskContext& ctx) const;
    const SymbolFunction* opaqueInit(const TaskContext& ctx) const;
    const SymbolFunction* effectiveOpDrop(const TaskContext& ctx) const;
    const SymbolFunction* effectiveOpPostCopy(const TaskContext& ctx) const;
    const SymbolFunction* effectiveOpPostMove(const TaskContext& ctx) const;

    bool hasConcreteLayout() const noexcept;

    // A tagged union stores its tag first and every member at one payload offset after it.
    TypeRef  taggedTypeRef() const noexcept { return taggedTypeRef_; }
    void     setTaggedTypeRef(TypeRef typeRef) noexcept { taggedTypeRef_ = typeRef; }
    uint32_t taggedPayloadOffset() const noexcept { return taggedPayloadOffset_; }
    uint32_t taggedTagSize(TaskContext& ctx) const;

    void                                    addTaggedCase(const SymbolVariable& member, std::span<ConstantRef> values);
    std::span<const SymbolStructTaggedCase> taggedCases() const noexcept { return taggedCases_; }
    std::span<const ConstantRef>            taggedCaseValues(const SymbolVariable& member) const noexcept;
    const SymbolVariable*                   taggedCaseMember(ConstantRef value) const noexcept;

    bool                         isGenericRoot() const noexcept { return hasExtraFlag(SymbolStructFlagsE::GenericRoot); }
    void                         setGenericRoot(bool value) noexcept;
    bool                         isGenericInstance() const noexcept { return hasExtraFlag(SymbolStructFlagsE::GenericInstance); }
    bool                         isUnion() const noexcept { return hasExtraFlag(SymbolStructFlagsE::Union); }
    bool                         isTagged() const noexcept { return hasExtraFlag(SymbolStructFlagsE::Tagged); }
    void                         setGenericInstance(SymbolStruct* root, const GenericInstanceOrigin& origin) noexcept;
    const GenericInstanceOrigin* genericInstanceOrigin() const noexcept;
    bool                         sameGenericFamily(const SymbolStruct& other) const noexcept;

    SymbolStruct*       genericRootOrSelf() noexcept;
    const SymbolStruct* genericRootOrSelf() const noexcept;
    SymbolStruct*       genericRootSym() noexcept;
    const SymbolStruct* genericRootSym() const noexcept;

    AstNodeRef            findGenericEvalNode(const NodePayload* payloadContext, const Ast& ownerAst, AstNodeRef sourceRef, std::span<const SemaClone::ParamBinding> bindings) const;
    void                  cacheGenericEvalNode(const NodePayload* payloadContext, const Ast& ownerAst, AstNodeRef sourceRef, std::span<const SemaClone::ParamBinding> bindings, AstNodeRef evalRef) const;
    std::recursive_mutex& genericEvalRunMutex() const noexcept;

    bool                          tryGetGenericInstanceArgs(SmallVector<GenericInstanceKey>& outArgs) const;
    bool                          tryGetGenericInstanceArgs(const SymbolStruct& instance, SmallVector<GenericInstanceKey>& outArgs) const;
    GenericInstanceStorage&       genericInstanceStorage() noexcept;
    const GenericInstanceStorage& genericInstanceStorage() const noexcept;

    void setGenericCompletionOwner(const TaskContext& ctx) const noexcept;
    bool isGenericCompletionOwner(const TaskContext& ctx) const noexcept;
    bool isGenericCompletionActive(const TaskContext& ctx) const noexcept;
    bool tryStartGenericCompletion(const TaskContext& ctx) const noexcept;
    void finishGenericCompletion() const noexcept;
    bool isGenericNodeCompleted() const noexcept;
    void setGenericNodeCompleted() const noexcept;

    std::shared_mutex& generatedLifecycleMutex() const noexcept { return generatedLifecycleMutex_; }
    std::shared_mutex& generatedOperatorsMutex() const noexcept { return generatedOperatorsMutex_; }
    std::shared_mutex& generatedEqualityMutex() const noexcept { return generatedEqualityMutex_; }

    bool generatedLifecyclePublished() const noexcept { return generatedLifecyclePublished_.load(std::memory_order_acquire); }
    bool generatedOperatorsPublished() const noexcept { return generatedOperatorsPublished_.load(std::memory_order_acquire); }
    bool generatedEqualityPublished() const noexcept { return generatedEqualityPublished_.load(std::memory_order_acquire); }

    void publishGeneratedLifecycle() const noexcept { generatedLifecyclePublished_.store(true, std::memory_order_release); }
    void publishGeneratedOperators() const noexcept { generatedOperatorsPublished_.store(true, std::memory_order_release); }
    void publishGeneratedEquality() const noexcept { generatedEqualityPublished_.store(true, std::memory_order_release); }

    bool tryMarkGeneratedLifecycleFunctions() const noexcept;
    bool tryMarkGeneratedOperators() const noexcept;
    bool tryMarkGeneratedEquality() const noexcept;

    bool exportsRuntimeMethods(const TaskContext& ctx) const;

private:
    struct GenericData;

    GenericData& ensureGenericData() const noexcept;
    GenericData* genericData() const noexcept;

    void rebuildFieldIndexMap() noexcept;

    // Resolves the contained struct through aliases and array layers, if it carries dynamic identity.
    static const TypeInfo* dynamicStorageLeafType(const TaskContext& ctx, const TypeInfo& rootType);

    std::vector<SymbolVariable*> fields_;
    std::vector<uint32_t>        dynamicSlotOffsets_;

    std::unordered_map<const SymbolVariable*, size_t> fieldIndexMap_;

    SymbolImplChain impls_;

    mutable std::shared_mutex mutexInterfaces_;
    std::vector<SymbolImpl*>  interfaces_;
    PointerSet<SymbolImpl>    interfacesSet_;

    mutable std::shared_mutex    mutexSpecOps_;
    std::vector<SymbolFunction*> specOps_;
    PointerSet<SymbolFunction>   specOpsSet_;

    mutable std::once_flag implicitDefaultFlagsOnce_;
    std::once_flag         defaultStructOnce_;

    std::atomic<SymbolFunction*> opDrop_     = nullptr;
    std::atomic<SymbolFunction*> opPostCopy_ = nullptr;
    std::atomic<SymbolFunction*> opPostMove_ = nullptr;

    mutable std::shared_mutex generatedLifecycleMutex_;
    mutable std::shared_mutex generatedOperatorsMutex_;
    mutable std::shared_mutex generatedEqualityMutex_;

    mutable std::atomic<GenericData*> genericData_ = nullptr;

    mutable std::atomic_bool generatedLifecycleDone_ = false;
    mutable std::atomic_bool generatedOperatorsDone_ = false;
    mutable std::atomic_bool generatedEqualityDone_  = false;

    mutable std::atomic_bool generatedLifecyclePublished_ = false;
    mutable std::atomic_bool generatedOperatorsPublished_ = false;
    mutable std::atomic_bool generatedEqualityPublished_  = false;

    std::vector<SymbolStructTaggedCase> taggedCases_;
    TypeRef                             taggedTypeRef_       = TypeRef::invalid();
    uint32_t                            taggedPayloadOffset_ = 0;

    std::atomic<uint64_t> sizeInBytes_      = 0;
    ConstantRef           defaultStructCst_ = ConstantRef::invalid();
    std::atomic<uint32_t> alignment_        = 0;

    AstNodeRef declNodeRef_ = AstNodeRef::invalid();
};

SWC_END_NAMESPACE();
