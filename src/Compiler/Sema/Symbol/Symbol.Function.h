#pragma once
#include "Backend/JIT/JITMemory.h"
#include "Backend/Micro/MachineCode.h"
#include "Backend/Micro/MicroInstr.h"
#include "Backend/Micro/MicroReg.h"
#include "Compiler/Parser/Ast/AstNodes.h"
#include "Compiler/Sema/Generic/GenericInstanceKey.h"
#include "Compiler/Sema/Generic/GenericInstanceOrigin.h"
#include "Compiler/Sema/Helpers/SemaCloneTypes.h"
#include "Compiler/Sema/Helpers/SemaSpecOpKind.h"
#include "Compiler/Sema/Symbol/Symbol.Variable.h"
#include "Compiler/Sema/Symbol/SymbolMap.h"
#include "Support/Core/Flags.h"
#include "Support/Core/PointerSet.h"
#include "Support/Core/RefTypes.h"
#include "Support/Core/Result.h"
#include "Support/Core/Utf8.h"
#include "Support/Report/Assert.h"

SWC_BEGIN_NAMESPACE();

class GenericInstanceStorage;
class MicroBuilder;
class SymbolStruct;
class SymbolImpl;
class SymbolInterface;
class NodePayload;
class JITPatchJob;
class NativeBackendBuilder;
class TaskContext;

enum class SymbolFunctionFlagsE : uint16_t
{
    Zero                  = 0,
    Closure               = 1 << 0,
    Method                = 1 << 1,
    Fallible              = 1 << 2,
    Const                 = 1 << 3,
    Empty                 = 1 << 4,
    Attribute             = 1 << 5,
    Pure                  = 1 << 6,
    Variadic              = 1 << 7,
    UsesGlobalsToDrop     = 1 << 8,
    GenericRoot           = 1 << 9,
    GenericInstance       = 1 << 10,
    LazyBody              = 1 << 11,
    LazyBodyRunning       = 1 << 12,
    WhereConstraintFailed = 1 << 13,
    InlineLocalFunction   = 1 << 14,
    BoundToClosure        = 1 << 15, // A function literal typed by a closure binding.
};
using SymbolFunctionFlags = EnumFlags<SymbolFunctionFlagsE>;

class SymbolFunction : public SymbolMapT<SymbolKind::Function, SymbolFunctionFlagsE>
{
public:
    struct ParamField
    {
        uint8_t               paramIndex = 0;
        const SymbolVariable* field      = nullptr;

        bool operator==(const ParamField&) const noexcept = default;
    };

    static constexpr auto K = SymbolKind::Function;

    explicit SymbolFunction(const AstNode* decl, TokenRef tokRef, IdentifierRef idRef, const SymbolFlags& flags) :
        SymbolMapT(decl, tokRef, idRef, flags)
    {
    }

    ~SymbolFunction();

    TypeRef returnTypeRef() const { return returnType_; }

    SourceCodeRef codeRefIfDeclared() const noexcept
    {
        if (!decl())
            return SourceCodeRef::invalid();

        return codeRef();
    }

    TokenId intrinsicId() const
    {
        const auto* fnDecl = decl() ? decl()->safeCast<AstFunctionDecl>() : nullptr;
        return fnDecl ? fnDecl->intrinsicId : TokenId::Invalid;
    }

    void setReturnTypeRef(TypeRef typeRef) { returnType_ = typeRef; }

    RtAttributeFlags rtAttributeFlags() const;
    void             setRtAttributeFlags(RtAttributeFlags attr);

    const std::vector<SymbolVariable*>& parameters() const { return parameters_; }
    std::vector<SymbolVariable*>&       parameters() { return parameters_; }

    // RETURN bit i means the result may borrow parameter i; STORES means parameter i
    // may enter longer-lived storage. Body sema writes these before setSemaCompleted;
    // readers must wait for completion. SemaEscape::reportDeferredChecks closes opaque-call
    // chains after the final drain. Getters merge imported Swag.BorrowSummary attributes.
    uint64_t returnBorrowsParamsMask() const noexcept;

    // The result aliases the parameter's storage, rather than carrying a reference
    // to it in a separate allocation. Only this route can make freeing a returned
    // pointer release the argument's storage.
    uint64_t returnsStorageParamsMask() const noexcept;
    void     addReturnsStorageParam(size_t paramIndex) noexcept
    {
        if (paramIndex < 64)
            returnsStorageParamsMask_ |= 1ULL << paramIndex;
    }

    // Whether a call can observe application borrows through ambient storage or
    // unproven callbacks. Independent of explicit parameter retention effects.
    bool observesExternalBorrows() const noexcept;
    void markExternalBorrowObservation() noexcept { observesExternalBorrows_ = true; }
    void markBorrowEffectsComputed() noexcept { borrowEffectsComputed_ = true; }

    uint64_t storesParamsMask() const noexcept;
    bool     isAllocatorRelease(const TaskContext& ctx) const;

    // One-level aggregate contents reached through a pointer parameter. These
    // masks do not assert that the pointed-to aggregate slot itself is retained.
    uint64_t returnsIndirectParamsMask() const noexcept;
    uint64_t storesIndirectParamsMask() const noexcept;
    uint64_t storesIndirectIntoParamPairs() const noexcept;

    void addReturnBorrowsParam(size_t paramIndex, bool indirect = false) noexcept
    {
        if (paramIndex < 64)
            (indirect ? returnsIndirectParamsMask_ : returnBorrowsParamsMask_) |= 1ULL << paramIndex;
    }

    void addStoresParam(size_t paramIndex, bool indirect = false) noexcept
    {
        if (paramIndex < 64)
            (indirect ? storesIndirectParamsMask_ : storesParamsMask_) |= 1ULL << paramIndex;
    }

    // Bit i set = the call INVALIDATES what parameter #i points to (it reaches an
    // 'IAllocator.free/realloc' with that pointer as the request address). Seeded on
    // the language allocator interface, propagated through wrappers by the summary
    // fixpoint, serialized like the other summaries.
    //
    // The indirect mask is the same fact one dereference further: bit i set = the call
    // releases the pointer STORED in the box parameter #i designates ('Memory.delete(slot[])'),
    // and leaves the box itself alive. It is inferred from bodies and preserved in module APIs.
    uint64_t freesParamsMask() const noexcept;
    uint64_t freesIndirectParamsMask() const noexcept;
    void     addFreesParam(size_t paramIndex, bool indirect = false) noexcept
    {
        if (paramIndex >= 64)
            return;

        const uint64_t bit  = 1ULL << paramIndex;
        auto&          mask = indirect ? freesIndirectParamsMask_ : freesParamsMask_;
        if (!(mask.fetch_or(bit, std::memory_order_release) & bit))
            s_freesMaskVersion.fetch_add(1, std::memory_order_release);
    }

    // Version release-summary growth to avoid recomputing the same call-graph
    // fixpoint for every compile-time call.
    static uint64_t freesMaskVersion() noexcept { return s_freesMaskVersion.load(std::memory_order_acquire); }

    // Bit i means the result views parameter i's owned heap payload, so moving that
    // payload invalidates the result (String.toString). Fresh objects that merely hold
    // a pointer to the parameter (Wnd.addTimer) do not count; the RETURN mask tracks both.
    uint64_t returnsPayloadParamsMask() const noexcept;
    void     addReturnsPayloadParam(size_t paramIndex) noexcept
    {
        if (paramIndex < 64)
        {
            returnsPayloadParamsMask_ |= 1ULL << paramIndex;
            returnsPayloadUnknownProjectionParamsMask_ |= 1ULL << paramIndex;
        }
    }

    void addReturnsPayloadParamField(size_t paramIndex, const SymbolVariable& field)
    {
        if (paramIndex >= 64)
            return;

        returnsPayloadParamsMask_ |= 1ULL << paramIndex;

        const ParamField entry{static_cast<uint8_t>(paramIndex), &field};
        if (std::ranges::find(returnedPayloadParamFields_, entry) == returnedPayloadParamFields_.end())
            returnedPayloadParamFields_.push_back(entry);
    }

    std::span<const ParamField> returnedPayloadParamFields() const noexcept { return returnedPayloadParamFields_.span(); }
    bool                        returnsPayloadParamProjectionUnknown(size_t paramIndex) const noexcept
    {
        if (paramIndex >= 64)
            return true;

        const uint64_t bit = 1ULL << paramIndex;
        if (returnsPayloadUnknownProjectionParamsMask_ & bit)
            return true;

        const AttributeList* attrs = attributesIfAny();
        return attrs && (attrs->returnsPayloadParamsMask & bit);
    }

    // Bit i means the call may move or release parameter i's owned heap payload through
    // IAllocator.free/realloc. Operations such as append, reserve, and clear are valid,
    // but their summaries distinguish calls that can invalidate existing payload views.
    uint64_t reallocatesParamsMask() const noexcept;
    void     addReallocatesParam(size_t paramIndex) noexcept
    {
        if (paramIndex < 64)
        {
            reallocatesParamsMask_ |= 1ULL << paramIndex;
            reallocatesUnknownProjectionParamsMask_ |= 1ULL << paramIndex;
        }
    }

    void addReallocatesParamField(size_t paramIndex, const SymbolVariable& field)
    {
        if (paramIndex >= 64)
            return;

        reallocatesParamsMask_ |= 1ULL << paramIndex;

        const ParamField entry{static_cast<uint8_t>(paramIndex), &field};
        if (std::ranges::find(reallocatedParamFields_, entry) == reallocatedParamFields_.end())
            reallocatedParamFields_.push_back(entry);
    }

    std::span<const ParamField> reallocatedParamFields() const noexcept { return reallocatedParamFields_.span(); }
    bool                        reallocatesParamProjectionUnknown(size_t paramIndex) const noexcept
    {
        if (paramIndex >= 64)
            return true;

        const uint64_t bit = 1ULL << paramIndex;
        if (reallocatesUnknownProjectionParamsMask_ & bit)
            return true;

        const AttributeList* attrs = attributesIfAny();
        return attrs && (attrs->reallocatesParamsMask & bit);
    }

    // Bit (into*8 + stored) = parameter #stored may remain in storage reachable
    // from parameter #into after the call ('me.list = item'). Judged at call
    // sites where the 'into' argument provably outlives the stored one (a global).
    // Packed 8x8: parameters beyond #7 are not tracked.
    uint64_t storesIntoParamPairs() const noexcept;
    void     addStoresIntoParam(size_t intoIndex, size_t storedIndex, bool indirect = false) noexcept
    {
        if (intoIndex < 8 && storedIndex < 8)
            (indirect ? storesIndirectIntoParamPairs_ : storesIntoParamPairs_) |= 1ULL << (intoIndex * 8 + storedIndex);
    }

    static bool hasStoresIntoPair(uint64_t pairs, size_t intoIndex, size_t storedIndex) noexcept
    {
        return intoIndex < 8 && storedIndex < 8 && (pairs & (1ULL << (intoIndex * 8 + storedIndex))) != 0;
    }

    struct PendingBorrowStore
    {
        AstNodeRef nodeRef;
        AstNodeRef leftRef;
        uint8_t    intoIndex;
        uint8_t    storedIndex;
        bool       indirect;

        bool operator==(const PendingBorrowStore&) const noexcept = default;
    };

    void addPendingBorrowStore(AstNodeRef nodeRef, AstNodeRef leftRef, size_t intoIndex, size_t storedIndex, bool indirect = false)
    {
        if (intoIndex >= 8 || storedIndex >= 8)
            return;

        const PendingBorrowStore store{nodeRef, leftRef, static_cast<uint8_t>(intoIndex), static_cast<uint8_t>(storedIndex), indirect};
        if (std::ranges::find(pendingBorrowStores_, store) == pendingBorrowStores_.end())
            pendingBorrowStores_.push_back(store);
    }

    std::vector<PendingBorrowStore> takePendingBorrowStores() { return std::exchange(pendingBorrowStores_, {}); }

    const std::vector<SymbolVariable*>& localVariables() const { return localVariables_; }
    bool                                containsLocalVariable(const SymbolVariable& var) const noexcept { return localVariableSet_.contains(&var); }
    bool                                ownsVariable(const SymbolVariable& var) const
    {
        if (var.ownerSymMap() == this)
            return true;
        if (containsLocalVariable(var))
            return true;

        const auto& params = parameters();
        const auto  index  = var.parameterIndex();
        if (index < params.size() && params[index] == &var)
            return true;

        return std::ranges::find(params, &var) != params.end();
    }

    void addParameter(SymbolVariable* sym);
    bool tryGetParameterIndexByName(size_t& outIndex, IdentifierRef name, size_t startIndex = 0) const noexcept;
    void setVariadicParamFlag(TaskContext& ctx);
    void addLocalVariable(TaskContext& ctx, SymbolVariable* sym);

    Utf8 computeName(const TaskContext& ctx) const;
    Utf8 computePublicApiBaseSymbolName(const TaskContext& ctx) const;
    Utf8 computePublicApiSymbolName(const TaskContext& ctx) const;

    bool supportsGeneratedModuleApiExport() const noexcept;
    bool supportsPublicApiForeignExport() const noexcept;

    bool     usesStructuralTypeIdentity() const noexcept;
    uint32_t typeSignatureHash() const noexcept;
    bool     sameTypeSignature(const SymbolFunction& otherFunc) const noexcept;
    bool     sameTypeSignatureIgnoringClosure(const SymbolFunction& otherFunc) const noexcept;
    bool     deepCompare(const SymbolFunction& otherFunc) const noexcept;

    SymbolFunctionFlags semanticFlags() const noexcept { return extraFlags().mask(K_SEMANTIC_FLAGS); }

    SymbolStruct*       ownerStruct();
    const SymbolStruct* ownerStruct() const;

    // The nearest enclosing function in the lexical chain, for a local or nested function.
    const SymbolFunction* parentLexicalFunction() const;

    void setExtraFlags(EnumFlags<AstFunctionFlagsE> parserFlags);

    bool isClosure() const noexcept { return hasExtraFlag(SymbolFunctionFlagsE::Closure); }
    bool isMethod() const noexcept { return hasExtraFlag(SymbolFunctionFlagsE::Method); }
    bool isFallible() const noexcept { return hasExtraFlag(SymbolFunctionFlagsE::Fallible); }
    bool isConst() const noexcept { return hasExtraFlag(SymbolFunctionFlagsE::Const); }
    bool isEmpty() const noexcept { return hasExtraFlag(SymbolFunctionFlagsE::Empty); }
    bool isEmptyNonForeign() const noexcept { return isEmpty() && !isForeign(); }
    bool isAttribute() const noexcept { return hasExtraFlag(SymbolFunctionFlagsE::Attribute); }
    bool isForeignOrEmptyOrAttribute() const noexcept { return isForeign() || isEmpty() || isAttribute(); }
    bool isPure() const noexcept { return hasExtraFlag(SymbolFunctionFlagsE::Pure); }
    bool hasVariadicParam() const noexcept { return hasExtraFlag(SymbolFunctionFlagsE::Variadic); }
    void setPure(bool value) noexcept;

    bool isForeign() const noexcept { return attributes().hasForeign; }
    bool hasFullInitialization() const noexcept { return inferredFullInitialization_ || attributes().hasRtFlag(RtAttributeFlagsE::FullInit); }
    void setInferredFullInitialization(bool value) const noexcept { inferredFullInitialization_ = value; }

    std::string_view foreignModuleName() const { return attributes().foreignModuleName; }
    std::string_view foreignFunctionName() const { return attributes().foreignFunctionName; }
    std::string_view foreignLinkModuleName() const { return attributes().foreignLinkModuleName; }
    CallConvKind     foreignCallConvKind() const noexcept { return attributes().resolvedForeignCallConvKind(); }
    Utf8             resolveForeignModuleName(const TaskContext& ctx) const;
    Utf8             resolveForeignFunctionName(const TaskContext& ctx) const;

    bool usesGlobalsToDrop() const noexcept { return hasExtraFlag(SymbolFunctionFlagsE::UsesGlobalsToDrop); }
    void setUsesGlobalsToDrop() noexcept { addExtraFlag(SymbolFunctionFlagsE::UsesGlobalsToDrop); }

    bool     hasInterfaceMethodSlot() const noexcept { return interfaceMethodSlot_ != K_INVALID_INTERFACE_METHOD_SLOT; }
    uint32_t interfaceMethodSlot() const noexcept { return SWC_CHECK_NOT(interfaceMethodSlot_, K_INVALID_INTERFACE_METHOD_SLOT); }
    void     setInterfaceMethodSlot(uint32_t slot) noexcept { interfaceMethodSlot_ = slot; }

    SpecOpKind specOpKind() const noexcept { return specOpKind_; }
    void       setSpecOpKind(SpecOpKind kind) noexcept { specOpKind_ = kind; }

    CallConvKind callConvKind() const noexcept { return callConvKind_; }
    void         setCallConvKind(CallConvKind kind) noexcept { callConvKind_ = kind; }

    MicroBuilder&       microInstrBuilder(TaskContext& ctx);
    const MicroBuilder* microInstrBuilder() const noexcept { return microInstrBuilder_.load(std::memory_order_acquire); }
    void                releaseMicroInstrBuilder() noexcept;

    AstNodeRef         declNodeRef() const noexcept { return declNodeRef_; }
    const NodePayload* declNodePayloadContext() const noexcept { return declNodePayloadCtx_; }
    void               setDeclNodeRef(AstNodeRef nodeRef) noexcept { declNodeRef_ = nodeRef; }
    void               setDeclNodePayloadContext(const NodePayload* payloadContext) noexcept { declNodePayloadCtx_ = payloadContext; }

    uint32_t debugStackFrameSize() const noexcept { return debugStackFrameSize_; }
    void     setDebugStackFrameSize(uint32_t value) noexcept { debugStackFrameSize_ = value; }
    MicroReg debugStackBaseReg() const noexcept { return debugStackBaseReg_; }
    void     setDebugStackBaseReg(MicroReg reg) noexcept { debugStackBaseReg_ = reg; }

    bool tryMarkCodeGenJobScheduled() noexcept;

    void addCallDependency(const SymbolFunction* sym);
    void appendCallDependencies(SmallVector<SymbolFunction*>& out) const;
    bool hasCallDependencies() const;

    void addLifecycleDependency(const SymbolFunction* sym, bool observesEffects = true);
    void appendLifecycleDependencies(SmallVector<SymbolFunction*>& out) const;
    void appendLifecycleEffectDependencies(SmallVector<SymbolFunction*>& out) const;

    // Visit the cached order in place so metadata and dependency queries avoid
    // copying hundreds of pointers for every compile-time call.
    template<typename Visit>
    void visitJitOrder(Visit&& visit) const
    {
        refreshJitOrderCache();

        const std::shared_lock lock(jitOrderCacheMutex_);
        for (SymbolFunction* function : jitOrderCache_)
            visit(function);
    }

    // Stop when one dependency settles the predicate instead of scanning the whole closure.
    template<typename Pred>
    bool allInJitOrder(Pred&& pred) const
    {
        refreshJitOrderCache();

        const std::shared_lock lock(jitOrderCacheMutex_);
        for (SymbolFunction* function : jitOrderCache_)
        {
            if (!pred(function))
                return false;
        }

        return true;
    }

    // Invalidate JIT orders when call dependencies grow or functions leave code generation.
    // Unchanged graph versions reuse the cached order across compile-time calls.
    static void     noteCallGraphChanged() noexcept { s_callGraphVersion.fetch_add(1, std::memory_order_release); }
    static uint64_t callGraphVersion() noexcept { return s_callGraphVersion.load(std::memory_order_acquire); }

    // Most global graph changes lie outside a given closure. Track each function's
    // changes separately: monotonic epochs keep the closure sum unchanged exactly
    // when no member changed.
    void     noteOwnCallGraphChanged() noexcept { callGraphEpoch_.fetch_add(1, std::memory_order_release); }
    uint32_t callGraphEpoch() const noexcept { return callGraphEpoch_.load(std::memory_order_acquire); }

    // Add inlined bodies to the function's estimated code-generation cost so the native
    // backend can schedule the longest jobs first. Uses auto-inline cost units.
    void     noteInlinedCost(uint32_t cost) const noexcept { inlinedCost_.fetch_add(cost, std::memory_order_relaxed); }
    uint32_t inlinedCost() const noexcept { return inlinedCost_.load(std::memory_order_relaxed); }

    bool hasLoweredCode() const noexcept;

    // Lowered code is immutable after emission. Cache its global-init relocation offsets
    // once instead of recomputing them for every compile-time call.
    const std::vector<uint64_t>& globalInitRelocationOffsets() const;

    // Cache reachable constant-relocation targets until their constant graph changes.
    // Each entry also records whether its relocation tolerates an unresolved function.
    // Shared ownership keeps a reader's snapshot alive when another thread refreshes it.
    using ConstantJitTargetList = std::vector<std::pair<SymbolFunction*, bool>>;

    struct ConstantJitTargets
    {
        std::shared_ptr<const ConstantJitTargetList>  targets;
        SmallVector<std::pair<uint32_t, uint64_t>, 2> shardVersions;
    };

    ConstantJitTargets& constantJitTargets() const noexcept { return constantJitTargets_; }
    std::shared_mutex&  constantJitTargetsMutex() const noexcept { return constantJitTargetsMutex_; }

    bool  isJitWaitSatisfied(TaskStateKind kind) const noexcept;
    void* jitPatchAddress() const noexcept { return jitPatchedAddress_.load(std::memory_order_acquire); }
    void* jitEntryAddress() const noexcept { return jitEntryAddress_.load(std::memory_order_acquire); }
    void* jitWorkAddress() const noexcept { return jitState_.has(JitStateE::Prepared) ? jitExecMemory_.entryPoint() : nullptr; }

    bool ownsJitCodeAddress(const void* address) const noexcept
    {
        if (!address)
            return false;

        if (address == jitEntryAddress() || address == jitPatchAddress())
            return true;

        const auto* begin = static_cast<const std::byte*>(jitExecMemory_.entryPoint());
        return begin && address >= begin && address < begin + jitExecMemory_.size();
    }

    uint64_t jitReadyVersion() const noexcept { return jitReadyVersion_.load(std::memory_order_acquire); }
    void     setJitReadyVersion(uint64_t version) noexcept { jitReadyVersion_.store(version, std::memory_order_release); }
    void     resetJitState() noexcept;

    Result emit(TaskContext& ctx);
    Result emitOrReuse(TaskContext& ctx);
    Result ensureClosureAdapter(TaskContext& ctx, SymbolFunction*& outAdapter);

    // Registers a direct call to this function writes, as MicroInstr call clobbers. Only a leaf is
    // ever narrowed: a function whose analysis found no call, its callers wait for it, and whose
    // body was lowered without any call, so it can be emitted on a caller's behalf when its own
    // job has not got there yet: its passes read no other function.
    void     classifyLoweredBody(SmallVector<SymbolFunction*>& outDirectCallees);
    bool     isSemaLeaf() const noexcept { return hasFlag(SymbolFlagsE::SemaLeaf); }
    bool     isLoweredLeaf() const noexcept { return hasFlag(SymbolFlagsE::LoweredLeaf); }
    uint64_t callClobbers() const noexcept { return callClobbers_.load(std::memory_order_acquire); }
    void     setCallClobbers(uint64_t clobbers) noexcept { callClobbers_.store(clobbers, std::memory_order_release); }
    Result   resolveCallClobbers(TaskContext& ctx, uint64_t& outClobbers);

    GenericInstanceStorage& genericInstanceStorage(const TaskContext& ctx) const noexcept;
    bool                    tryGetGenericInstanceArgs(const TaskContext& ctx, const SymbolFunction& instance, SmallVector<GenericInstanceKey>& outArgs) const;
    bool                    tryGetGenericInstanceArgs(const TaskContext& ctx, SmallVector<GenericInstanceKey>& outArgs) const;

    AstNodeRef            findGenericEvalNode(const TaskContext& ctx, const NodePayload* payloadContext, const Ast& ownerAst, AstNodeRef sourceRef, std::span<const SemaClone::ParamBinding> bindings) const;
    void                  cacheGenericEvalNode(const TaskContext& ctx, const NodePayload* payloadContext, const Ast& ownerAst, AstNodeRef sourceRef, std::span<const SemaClone::ParamBinding> bindings, AstNodeRef evalRef) const;
    std::recursive_mutex& genericEvalRunMutex(const TaskContext& ctx) const noexcept;

    // The type an erased parameter ('T is Bound') takes in the root's single instance for
    // `boundTypeRef`. Callers hold genericEvalRunMutex.
    struct ErasedParamType
    {
        uint32_t paramIndex    = 0;
        TypeRef  boundTypeRef  = TypeRef::invalid();
        TypeRef  erasedTypeRef = TypeRef::invalid();
    };

    TypeRef findErasedParamType(const TaskContext& ctx, uint32_t paramIndex, TypeRef boundTypeRef) const;
    void    addErasedParamType(const TaskContext& ctx, const ErasedParamType& entry) const;

    // A root whose every generic parameter is erased has exactly one instance. That instance
    // is compiled with the module that declares it and published like a plain function.
    bool            isErasedGenericRoot() const noexcept;
    void            setErasedGenericRoot(const TaskContext& ctx) const noexcept;
    bool            isErasedGenericInstance() const noexcept;
    SymbolFunction* erasedInstance() const noexcept;
    void            setErasedInstance(const TaskContext& ctx, SymbolFunction* instance) const noexcept;

    std::shared_mutex&     lazyBodyRunMutex() const noexcept { return lazyBodyRunMutex_; }
    std::shared_ptr<void>* lazyBodyRunState() const noexcept;
    std::shared_ptr<void>& ensureLazyBodyRunState(const TaskContext& ctx) const noexcept;

    static Result jitBatch(TaskContext& ctx, std::span<SymbolFunction* const> functions, const Symbol* waiterSymbol = nullptr);
    Result        jit(TaskContext& ctx);

    const MachineCode& loweredCode() const noexcept { return loweredMicroCode_; }

    const GenericInstanceOrigin* genericInstanceOrigin() const noexcept;

    bool isGenericRoot() const noexcept { return hasExtraFlag(SymbolFunctionFlagsE::GenericRoot); }
    void setGenericRoot(bool value) noexcept;
    bool isGenericInstance() const noexcept { return hasExtraFlag(SymbolFunctionFlagsE::GenericInstance); }
    void setGenericInstance(const TaskContext& ctx, SymbolFunction* root, const GenericInstanceOrigin& origin) noexcept;
    bool hasUnmaterializedGenericBody() const noexcept;

    SymbolFunction*       genericRootOrSelf() noexcept;
    const SymbolFunction* genericRootOrSelf() const noexcept;
    SymbolFunction*       genericRootSym() noexcept;
    const SymbolFunction* genericRootSym() const noexcept;

    const SymbolImpl*      declImplContext() const noexcept;
    const SymbolInterface* declInterfaceContext() const noexcept;

    void setGenericCompletionOwner(const TaskContext& ctx) const noexcept;
    bool isGenericCompletionOwner(const TaskContext& ctx) const noexcept;
    bool isGenericCompletionActive(const TaskContext& ctx) const noexcept;
    bool tryStartGenericCompletion(const TaskContext& ctx) const noexcept;
    void finishGenericCompletion() const noexcept;
    bool isGenericNodeCompleted() const noexcept;
    void setGenericNodeCompleted() const noexcept;

private:
    struct GenericData;

    friend class JITPatchJob;
    friend class CompilerInstance;

    enum class JitStateE : uint8_t
    {
        Zero              = 0,
        PatchJobScheduled = 1 << 0,
        Prepared          = 1 << 1,
    };

    static constexpr SymbolFunctionFlags K_SEMANTIC_FLAGS = SymbolFunctionFlagsE::Closure |
                                                            SymbolFunctionFlagsE::Method |
                                                            SymbolFunctionFlagsE::Fallible |
                                                            SymbolFunctionFlagsE::Const |
                                                            SymbolFunctionFlagsE::Empty |
                                                            SymbolFunctionFlagsE::Attribute |
                                                            SymbolFunctionFlagsE::Pure |
                                                            SymbolFunctionFlagsE::Variadic;

    bool hasJitPreparedAddress() const noexcept { return jitWorkAddress() != nullptr; }
    bool hasJitPatchedAddress() const noexcept { return jitPatchAddress() != nullptr; }
    bool hasJitEntryAddress() const noexcept { return jitEntryAddress() != nullptr; }
    bool tryMarkJitPatchJobScheduled() noexcept;

    GenericData& ensureGenericData(const TaskContext& ctx) const noexcept;
    GenericData* genericData() const noexcept;

    Result emitLowered(TaskContext& ctx, NativeBackendBuilder* nativeCache);
    Result narrowCallClobbers(TaskContext& ctx, MicroBuilder& builder);
    Result jitMaterialize(TaskContext& ctx);
    bool   jitPrepare(TaskContext& ctx);
    Result jitPatch(TaskContext& ctx);
    void   jitFinalize(TaskContext& ctx);

    static constexpr uint32_t K_INVALID_INTERFACE_METHOD_SLOT  = 0xFFFFFFFFu;
    static constexpr uint8_t  K_INVALID_RT_ATTRIBUTE_BIT_INDEX = 0xFFu;

    std::vector<SymbolVariable*>     parameters_;
    std::vector<SymbolVariable*>     localVariables_;
    PointerSet<const SymbolVariable> localVariableSet_;

    void refreshJitOrderCache() const;

    static inline std::atomic<uint64_t> s_freesMaskVersion{0};
    static inline std::atomic<uint64_t> s_callGraphVersion{0};

    mutable std::vector<SymbolFunction*> jitOrderCache_;
    mutable std::atomic<uint64_t>        jitOrderCacheVersion_  = 0;
    mutable uint64_t                     jitOrderCacheEpochSum_ = 0;
    std::atomic<uint32_t>                callGraphEpoch_        = 0;
    mutable std::atomic<uint32_t>        inlinedCost_           = 0;
    mutable std::shared_mutex            jitOrderCacheMutex_;

    mutable std::vector<uint64_t> globalInitOffsetsCache_;
    mutable std::atomic<bool>     globalInitOffsetsComputed_ = false;
    mutable std::mutex            globalInitOffsetsMutex_;

    mutable ConstantJitTargets constantJitTargets_;
    mutable std::shared_mutex  constantJitTargetsMutex_;

    std::vector<SymbolFunction*> callDependencies_;
    PointerSet<SymbolFunction>   callDependencySet_;

    std::unique_ptr<std::vector<SymbolFunction*>> lifecycleDependencies_;
    std::unique_ptr<std::vector<SymbolFunction*>> lifecycleEffectDependencies_;

    uint32_t numComputedLocals_ = 0;
    uint32_t localStackOffset_  = 0;

    uint64_t returnBorrowsParamsMask_  = 0;
    uint64_t returnsStorageParamsMask_ = 0;
    bool     observesExternalBorrows_  = false;
    bool     borrowEffectsComputed_    = false;

    uint64_t storesParamsMask_     = 0;
    uint64_t storesIntoParamPairs_ = 0;

    uint64_t returnsIndirectParamsMask_    = 0;
    uint64_t storesIndirectParamsMask_     = 0;
    uint64_t storesIndirectIntoParamPairs_ = 0;

    std::vector<PendingBorrowStore> pendingBorrowStores_;

    std::atomic<uint64_t> freesParamsMask_         = 0;
    std::atomic<uint64_t> freesIndirectParamsMask_ = 0;

    uint64_t reallocatesParamsMask_                  = 0;
    uint64_t reallocatesUnknownProjectionParamsMask_ = 0;

    uint64_t returnsPayloadParamsMask_                  = 0;
    uint64_t returnsPayloadUnknownProjectionParamsMask_ = 0;

    SmallVector4<ParamField> reallocatedParamFields_;
    SmallVector4<ParamField> returnedPayloadParamFields_;

    TypeRef      returnType_                 = TypeRef::invalid();
    uint8_t      rtAttributeBitIndex_        = K_INVALID_RT_ATTRIBUTE_BIT_INDEX;
    mutable bool inferredFullInitialization_ = false;

    SpecOpKind   specOpKind_   = SpecOpKind::None;
    CallConvKind callConvKind_ = CallConvKind::Swag;

    AstNodeRef         declNodeRef_        = AstNodeRef::invalid();
    const NodePayload* declNodePayloadCtx_ = nullptr;

    uint32_t interfaceMethodSlot_ = K_INVALID_INTERFACE_METHOD_SLOT;

    uint32_t debugStackFrameSize_ = 0;
    MicroReg debugStackBaseReg_   = MicroReg::invalid();

    // Created when code generation starts and dropped once the function is lowered: most
    // functions a program imports are never generated, and a lowered one keeps its machine code.
    std::atomic<MicroBuilder*> microInstrBuilder_ = nullptr;
    MachineCode                loweredMicroCode_;
    std::atomic<uint64_t>      callClobbers_       = MicroInstr::K_CALL_CLOBBERS_ALL;
    bool                       nativeCacheChecked_ = false;
    bool                       nativeCacheHit_     = false;

    mutable std::shared_mutex            callDependenciesMutex_;
    mutable std::shared_mutex            closureAdapterMutex_;
    mutable std::shared_mutex            lazyBodyRunMutex_;
    mutable std::atomic<SymbolFunction*> closureAdapterPublished_ = nullptr;
    std::shared_mutex                    emitMutex_;

    JITMemory                          jitExecMemory_;
    mutable std::atomic<void*>         jitPatchedAddress_ = nullptr;
    mutable std::atomic<void*>         jitEntryAddress_   = nullptr;
    mutable AtomicEnumFlags<JitStateE> jitState_;
    std::atomic<uint64_t>              jitReadyVersion_{0};

    mutable std::atomic<GenericData*> genericData_ = nullptr;
};

SWC_END_NAMESPACE();
