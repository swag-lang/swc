#pragma once
#include "Backend/JIT/JITMemory.h"
#include "Backend/Micro/MachineCode.h"
#include "Backend/Micro/MicroBuilder.h"
#include "Compiler/Parser/Ast/AstNodes.h"
#include "Compiler/Sema/Generic/GenericInstanceStorage.h"
#include "Compiler/Sema/Helpers/SemaClone.h"
#include "Compiler/Sema/Helpers/SemaSpecOp.h"
#include "Compiler/Sema/Symbol/SymbolMap.h"
#include "Support/Core/Flags.h"
#include "Support/Core/RefTypes.h"
#include "Support/Core/Result.h"
#include "Support/Core/Utf8.h"
#include "Support/Report/Assert.h"

SWC_BEGIN_NAMESPACE();

class SymbolVariable;
class SymbolStruct;
class SymbolImpl;
class SymbolInterface;
class NodePayload;
class JITPatchJob;
class TaskContext;

enum class SymbolFunctionFlagsE : uint16_t
{
    Zero                   = 0,
    Closure                = 1 << 0,
    Method                 = 1 << 1,
    Throwable              = 1 << 2,
    Const                  = 1 << 3,
    Empty                  = 1 << 4,
    Attribute              = 1 << 5,
    Pure                   = 1 << 6,
    Variadic               = 1 << 7,
    UsesGvtd               = 1 << 8,
    GenericRoot            = 1 << 9,
    GenericInstance        = 1 << 10,
    LazyGenericBody        = 1 << 11,
    LazyGenericBodyRunning = 1 << 12,
    WhereConstraintFailed  = 1 << 13,
    InlineLocalFunction    = 1 << 14,
};
using SymbolFunctionFlags = EnumFlags<SymbolFunctionFlagsE>;

class SymbolFunction : public SymbolMapT<SymbolKind::Function, SymbolFunctionFlagsE>
{
public:
    static constexpr auto K = SymbolKind::Function;

    explicit SymbolFunction(const AstNode* decl, TokenRef tokRef, IdentifierRef idRef, const SymbolFlags& flags) :
        SymbolMapT(decl, tokRef, idRef, flags)
    {
    }

    TypeRef                             returnTypeRef() const { return returnType_; }
    void                                setReturnTypeRef(TypeRef typeRef) { returnType_ = typeRef; }
    RtAttributeFlags                    rtAttributeFlags() const;
    void                                setRtAttributeFlags(RtAttributeFlags attr);
    const std::vector<SymbolVariable*>& parameters() const { return parameters_; }
    std::vector<SymbolVariable*>&       parameters() { return parameters_; }

    // Per-function borrow summaries. Bit i of the RETURN mask = the returned value may
    // borrow parameter #i; bit i of the STORES mask = parameter #i may be stored into
    // storage that outlives the call (a global). Written during the body sema (before
    // setSemaCompleted); callers must gate reads on isSemaCompleted(). Grown once more
    // after the final sema drain by the summary fixpoint in
    // SemaEscape::reportDeferredChecks (transitivity across opaque-call chains).
    // Imported functions carry their summaries through the generated
    // 'Swag.BorrowSummary' attribute, OR-ed in by the getters.
    uint64_t returnBorrowsParamsMask() const noexcept;
    uint64_t storesParamsMask() const noexcept;
    void     addReturnBorrowsParam(size_t paramIndex) noexcept
    {
        if (paramIndex < 64)
            returnBorrowsParamsMask_ |= 1ULL << paramIndex;
    }
    void addStoresParam(size_t paramIndex) noexcept
    {
        if (paramIndex < 64)
            storesParamsMask_ |= 1ULL << paramIndex;
    }

    // Bit i set = the call INVALIDATES what parameter #i points to (it reaches an
    // 'IAllocator.free/realloc' with that pointer as the request address). Seeded on
    // the language allocator interface, propagated through wrappers by the summary
    // fixpoint, serialized like the other summaries.
    uint64_t freesParamsMask() const noexcept;
    void     addFreesParam(size_t paramIndex) noexcept
    {
        if (paramIndex < 64)
            freesParamsMask_ |= 1ULL << paramIndex;
    }

    // Bit (into*8 + stored) = parameter #stored may be stored into storage reachable
    // from parameter #into ('me.list = item' -> pair (item -> me)). Judged at call
    // sites where the 'into' argument provably outlives the stored one (a global).
    // Packed 8x8: parameters beyond #7 are not tracked.
    uint64_t storesIntoParamPairs() const noexcept;
    void     addStoresIntoParam(size_t intoIndex, size_t storedIndex) noexcept
    {
        if (intoIndex < 8 && storedIndex < 8)
            storesIntoParamPairs_ |= 1ULL << (intoIndex * 8 + storedIndex);
    }
    static bool hasStoresIntoPair(uint64_t pairs, size_t intoIndex, size_t storedIndex) noexcept
    {
        return intoIndex < 8 && storedIndex < 8 && (pairs & (1ULL << (intoIndex * 8 + storedIndex))) != 0;
    }
    const std::vector<SymbolVariable*>& localVariables() const { return localVariables_; }
    bool                                containsLocalVariable(const SymbolVariable& var) const noexcept { return localVariableSet_.contains(&var); }
    void                                addParameter(SymbolVariable* sym);
    bool                                tryGetParameterIndexByName(size_t& outIndex, IdentifierRef name, size_t startIndex = 0) const noexcept;
    void                                setVariadicParamFlag(TaskContext& ctx);
    void                                addLocalVariable(TaskContext& ctx, SymbolVariable* sym);
    Utf8                                computeName(const TaskContext& ctx) const;
    Utf8                                computePublicApiSymbolName(const TaskContext& ctx) const;
    bool                                supportsGeneratedModuleApiExport() const noexcept;
    bool                                supportsPublicApiForeignExport() const noexcept;
    bool                                usesStructuralTypeIdentity() const noexcept;
    uint32_t                            typeSignatureHash() const noexcept;
    bool                                sameTypeSignature(const SymbolFunction& otherFunc) const noexcept;
    bool                                sameTypeSignatureIgnoringClosure(const SymbolFunction& otherFunc) const noexcept;
    bool                                deepCompare(const SymbolFunction& otherFunc) const noexcept;
    SymbolFunctionFlags                 semanticFlags() const noexcept { return extraFlags().mask(K_SEMANTIC_FLAGS); }
    SymbolStruct*                       ownerStruct();
    const SymbolStruct*                 ownerStruct() const;

    void             setExtraFlags(EnumFlags<AstFunctionFlagsE> parserFlags);
    bool             isClosure() const noexcept { return hasExtraFlag(SymbolFunctionFlagsE::Closure); }
    bool             isMethod() const noexcept { return hasExtraFlag(SymbolFunctionFlagsE::Method); }
    bool             isThrowable() const noexcept { return hasExtraFlag(SymbolFunctionFlagsE::Throwable); }
    bool             isConst() const noexcept { return hasExtraFlag(SymbolFunctionFlagsE::Const); }
    bool             isEmpty() const noexcept { return hasExtraFlag(SymbolFunctionFlagsE::Empty); }
    bool             isAttribute() const noexcept { return hasExtraFlag(SymbolFunctionFlagsE::Attribute); }
    bool             isPure() const noexcept { return hasExtraFlag(SymbolFunctionFlagsE::Pure); }
    bool             hasVariadicParam() const noexcept { return hasExtraFlag(SymbolFunctionFlagsE::Variadic); }
    void             setPure(bool value) noexcept;
    bool             isForeign() const noexcept { return attributes().hasForeign; }
    std::string_view foreignModuleName() const { return attributes().foreignModuleName; }
    std::string_view foreignFunctionName() const { return attributes().foreignFunctionName; }
    std::string_view foreignLinkModuleName() const { return attributes().foreignLinkModuleName; }
    CallConvKind     foreignCallConvKind() const noexcept { return attributes().resolvedForeignCallConvKind(); }
    Utf8             resolveForeignFunctionName(const TaskContext& ctx) const;

    bool usesGvtd() const noexcept { return hasExtraFlag(SymbolFunctionFlagsE::UsesGvtd); }
    void setUsesGvtd() noexcept { addExtraFlag(SymbolFunctionFlagsE::UsesGvtd); }

    bool     hasInterfaceMethodSlot() const noexcept { return interfaceMethodSlot_ != K_INVALID_INTERFACE_METHOD_SLOT; }
    uint32_t interfaceMethodSlot() const noexcept { return SWC_CHECK_NOT(interfaceMethodSlot_, K_INVALID_INTERFACE_METHOD_SLOT); }
    void     setInterfaceMethodSlot(uint32_t slot) noexcept { interfaceMethodSlot_ = slot; }

    SpecOpKind              specOpKind() const noexcept { return specOpKind_; }
    void                    setSpecOpKind(SpecOpKind kind) noexcept { specOpKind_ = kind; }
    CallConvKind            callConvKind() const noexcept { return callConvKind_; }
    void                    setCallConvKind(CallConvKind kind) noexcept { callConvKind_ = kind; }
    MicroBuilder&           microInstrBuilder(TaskContext& ctx) noexcept;
    const MicroBuilder&     microInstrBuilder() const noexcept { return microInstrBuilder_; }
    AstNodeRef              declNodeRef() const noexcept { return declNodeRef_; }
    const NodePayload*      declNodePayloadContext() const noexcept { return declNodePayloadCtx_; }
    void                    setDeclNodeRef(AstNodeRef nodeRef) noexcept { declNodeRef_ = nodeRef; }
    void                    setDeclNodePayloadContext(const NodePayload* payloadContext) noexcept { declNodePayloadCtx_ = payloadContext; }
    uint32_t                debugStackFrameSize() const noexcept { return debugStackFrameSize_; }
    void                    setDebugStackFrameSize(uint32_t value) noexcept { debugStackFrameSize_ = value; }
    MicroReg                debugStackBaseReg() const noexcept { return debugStackBaseReg_; }
    void                    setDebugStackBaseReg(MicroReg reg) noexcept { debugStackBaseReg_ = reg; }
    bool                    tryMarkCodeGenJobScheduled() noexcept;
    void                    addCallDependency(const SymbolFunction* sym);
    void                    appendCallDependencies(SmallVector<SymbolFunction*>& out) const;
    void                    appendJitOrder(SmallVector<SymbolFunction*>& out) const;
    void*                   jitPatchAddress() const noexcept { return jitPatchedAddress_.load(std::memory_order_acquire); }
    void*                   jitEntryAddress() const noexcept { return jitEntryAddress_.load(std::memory_order_acquire); }
    void*                   jitWorkAddress() const noexcept { return jitExecMemory_.entryPoint(); }
    uint64_t                jitReadyVersion() const noexcept { return jitReadyVersion_.load(std::memory_order_acquire); }
    void                    setJitReadyVersion(uint64_t version) noexcept { jitReadyVersion_.store(version, std::memory_order_release); }
    void                    resetJitState() noexcept;
    Result                  emit(TaskContext& ctx);
    Result                  ensureClosureAdapter(TaskContext& ctx, SymbolFunction*& outAdapter);
    GenericInstanceStorage& genericInstanceStorage(const TaskContext& ctx) const noexcept;
    bool                    tryGetGenericInstanceArgs(const TaskContext& ctx, const SymbolFunction& instance, SmallVector<GenericInstanceKey>& outArgs) const;
    bool                    tryGetGenericInstanceArgs(const TaskContext& ctx, SmallVector<GenericInstanceKey>& outArgs) const;
    AstNodeRef              findGenericEvalNode(const TaskContext& ctx, const NodePayload* payloadContext, const Ast& ownerAst, AstNodeRef sourceRef, std::span<const SemaClone::ParamBinding> bindings) const;
    void                    cacheGenericEvalNode(const TaskContext& ctx, const NodePayload* payloadContext, const Ast& ownerAst, AstNodeRef sourceRef, std::span<const SemaClone::ParamBinding> bindings, AstNodeRef evalRef) const;
    std::recursive_mutex&   genericEvalRunMutex(const TaskContext& ctx) const noexcept;
    std::mutex&             lazyGenericBodyRunMutex() const noexcept { return lazyGenericBodyRunMutex_; }
    std::shared_ptr<void>*  lazyGenericBodyRunState() const noexcept;
    std::shared_ptr<void>&  ensureLazyGenericBodyRunState(const TaskContext& ctx) const noexcept;
    static Result           jitBatch(TaskContext& ctx, std::span<SymbolFunction* const> functions, const Symbol* waiterSymbol = nullptr);
    Result                  jit(TaskContext& ctx);
    const MachineCode&      loweredCode() const noexcept { return loweredMicroCode_; }
    bool                    isGenericRoot() const noexcept { return hasExtraFlag(SymbolFunctionFlagsE::GenericRoot); }
    void                    setGenericRoot(bool value) noexcept;
    bool                    isGenericInstance() const noexcept { return hasExtraFlag(SymbolFunctionFlagsE::GenericInstance); }
    void                    setGenericInstance(const TaskContext& ctx, SymbolFunction* root) noexcept;
    bool                    hasUnmaterializedGenericBody() const noexcept;
    SymbolFunction*         genericRootOrSelf() noexcept;
    const SymbolFunction*   genericRootOrSelf() const noexcept;
    SymbolFunction*         genericRootSym() noexcept;
    const SymbolFunction*   genericRootSym() const noexcept;
    const SymbolImpl*       declImplContext() const noexcept;
    const SymbolInterface*  declInterfaceContext() const noexcept;
    void                    setGenericCompletionOwner(const TaskContext& ctx) const noexcept;
    bool                    isGenericCompletionOwner(const TaskContext& ctx) const noexcept;
    bool                    isGenericCompletionActive(const TaskContext& ctx) const noexcept;
    bool                    tryStartGenericCompletion(const TaskContext& ctx) const noexcept;
    void                    finishGenericCompletion() const noexcept;
    bool                    isGenericNodeCompleted() const noexcept;
    void                    setGenericNodeCompleted() const noexcept;

private:
    struct GenericData;
    friend class JITPatchJob;

    static constexpr SymbolFunctionFlags K_SEMANTIC_FLAGS = SymbolFunctionFlagsE::Closure |
                                                            SymbolFunctionFlagsE::Method |
                                                            SymbolFunctionFlagsE::Throwable |
                                                            SymbolFunctionFlagsE::Const |
                                                            SymbolFunctionFlagsE::Empty |
                                                            SymbolFunctionFlagsE::Attribute |
                                                            SymbolFunctionFlagsE::Pure |
                                                            SymbolFunctionFlagsE::Variadic;

    bool         hasLoweredCode() const noexcept;
    bool         hasJitPreparedAddress() const noexcept { return jitWorkAddress() != nullptr; }
    bool         hasJitPatchedAddress() const noexcept { return jitPatchAddress() != nullptr; }
    bool         hasJitEntryAddress() const noexcept { return jitEntryAddress() != nullptr; }
    bool         tryMarkJitPatchJobScheduled() noexcept;
    GenericData& ensureGenericData(const TaskContext& ctx) const noexcept;
    GenericData* genericData() const noexcept;
    Result       jitMaterialize(TaskContext& ctx);
    bool         jitPrepare(TaskContext& ctx);
    Result       jitPatch(TaskContext& ctx);
    void         jitFinalize(TaskContext& ctx);

    static constexpr uint32_t K_INVALID_INTERFACE_METHOD_SLOT  = 0xFFFFFFFFu;
    static constexpr uint8_t  K_INVALID_RT_ATTRIBUTE_BIT_INDEX = 0xFFu;

    std::vector<SymbolVariable*>              parameters_;
    std::vector<SymbolVariable*>              localVariables_;
    std::unordered_set<const SymbolVariable*> localVariableSet_;
    std::vector<SymbolFunction*>              callDependencies_;
    std::unordered_set<SymbolFunction*>       callDependencySet_;
    uint32_t                                  numComputedLocals_       = 0;
    uint32_t                                  localStackOffset_        = 0;
    uint64_t                                  returnBorrowsParamsMask_ = 0;
    uint64_t                                  storesParamsMask_        = 0;
    uint64_t                                  storesIntoParamPairs_    = 0;
    uint64_t                                  freesParamsMask_         = 0;
    TypeRef                                   returnType_              = TypeRef::invalid();
    uint8_t                                   rtAttributeBitIndex_     = K_INVALID_RT_ATTRIBUTE_BIT_INDEX;
    SpecOpKind                                specOpKind_              = SpecOpKind::None;
    CallConvKind                              callConvKind_            = CallConvKind::Swag;
    AstNodeRef                                declNodeRef_             = AstNodeRef::invalid();
    const NodePayload*                        declNodePayloadCtx_      = nullptr;
    uint32_t                                  interfaceMethodSlot_     = K_INVALID_INTERFACE_METHOD_SLOT;
    uint32_t                                  debugStackFrameSize_     = 0;
    MicroReg                                  debugStackBaseReg_       = MicroReg::invalid();

    MicroBuilder                         microInstrBuilder_;
    MachineCode                          loweredMicroCode_;
    mutable std::shared_mutex            callDependenciesMutex_;
    mutable std::mutex                   closureAdapterMutex_;
    mutable std::mutex                   lazyGenericBodyRunMutex_;
    mutable std::atomic<SymbolFunction*> closureAdapterPublished_ = nullptr;
    std::mutex                           emitMutex_;
    JITMemory                            jitExecMemory_;
    std::atomic<void*>                   jitPatchedAddress_    = nullptr;
    std::atomic<void*>                   jitEntryAddress_      = nullptr;
    std::atomic_bool                     jitPatchJobScheduled_ = false;
    std::atomic<uint64_t>                jitReadyVersion_{0};
    mutable std::atomic<GenericData*>    genericData_ = nullptr;
};

SWC_END_NAMESPACE();
