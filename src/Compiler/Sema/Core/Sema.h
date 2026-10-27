// ReSharper disable CppMemberFunctionMayBeStatic
#pragma once
#include "Backend/RuntimeBuildConfig.h"
#include "Compiler/Parser/Ast/Ast.h"
#include "Compiler/Parser/Ast/AstVisit.h"
#include "Compiler/Sema/Core/NodePayload.h"
#include "Compiler/Sema/Core/SemaFrame.h"
#include "Compiler/Sema/Core/SemaNodeView.h"
#include "Compiler/Sema/Core/SemaScope.h"
#include "Compiler/Sema/Helpers/SemaEscapeTypes.h"
#include "Compiler/Sema/Symbol/IdentifierManager.h"
#include "Support/Core/Flags.h"
#include "Support/Core/PointerSet.h"
#include "Support/Core/RefTypes.h"
#include "Support/Core/Result.h"
#include "Support/Core/Utf8.h"
#include "Support/Thread/Job.h"

SWC_BEGIN_NAMESPACE();

struct CastRequest;
enum class TaskStateKind : uint8_t;
class SymbolNamespace;
class SymbolFunction;
class SymbolVariable;
class SymbolImpl;
class SymbolInterface;
class MatchContext;
class IdentifierManager;
class Sema;
class SourceFile;
struct SemaInlinePayload;

struct ScopedBreakSemaPayload
{
    AstNodeRef targetScopeRef = AstNodeRef::invalid();
};

namespace SemaGeneric
{
    void prepareGenericInstantiationContext(Sema& sema, SymbolMap* startSymMap, const SymbolImpl* impl, const SymbolInterface* itf, const AttributeList& attrs);
}

enum class SemaEscapeKind : uint8_t
{
    None,
    Static,
    Parameter,
    Local,
    Materialized, // compiler-materialized cast storage: frame lifetime, no named variable
    Temporary,
    Unknown,
    DeferredCall, // opaque-call result bound to a local: may borrow the call's arguments
};

struct SemaEscapeDetachedPayloadField
{
    const SymbolVariable* owner = nullptr;
    const SymbolVariable* field = nullptr;

    bool operator==(const SemaEscapeDetachedPayloadField&) const noexcept = default;
};

struct SemaEscapeInfo
{
    SemaEscapeKind        kind      = SemaEscapeKind::None;
    const SymbolVariable* sourceVar = nullptr;
    AstNodeRef            sourceRef = AstNodeRef::invalid();
    TypeRef               typeRef   = TypeRef::invalid();

    // All signature parameters whose storage this value may borrow. Keeping the full
    // set is required for aggregates and closures that carry more than one parameter;
    // sourceVar remains the representative origin used by local diagnostics.
    uint64_t parameterOriginsMask = 0;

    // Borrows copied from the aggregate designated by a pointer parameter. These
    // refer to its contents, not to the parameter's pointed-to slot itself.
    uint64_t parameterIndirectOriginsMask = 0;

    // Opaque-call snapshots carried by this value. Shared ownership keeps them valid
    // when nested Sema instances and control-flow alternatives exchange their state.
    SmallVector4<std::shared_ptr<const SemaEscapeDeferredCallSnapshot>> deferredCalls;

    // Owning root/field pairs replaced after an opaque accessor produced this view. The
    // accessor's final returned-payload projection decides whether each one detached it.
    SmallVector4<SemaEscapeDetachedPayloadField> detachedOwnedPayloadFields;

    // Lexical depth of the storage backing a Materialized borrow (0 = unknown).
    uint32_t sourceScopeDepth = 0;

    // This borrow refers to an owned allocation, not the owner's storage.
    // Its normal release must not imply that the callee frees a passed parameter.
    bool viaOwnedPayload = false;

    // Members of a dynamically typed payload may refer back into that payload or to
    // storage released with it. Copying a carrier member does not establish an
    // independent lifetime, unlike reading a pointer out of an ordinary container.
    bool viaErasedPayload = false;

    // Replacing the owning carrier detaches this borrow from the new allocation.
    // It still refers to the released payload, not to the owner's storage.
    bool detachedOwnedPayload = false;

    // A stored field carries its origin without becoming that origin. Escape
    // rules still apply, but freeing the carrier does not free the borrowed storage.
    bool viaStoredField = false;

    // This value is the pointer read from a parameter-designated box; indirect
    // origins identify that box exactly. Releasing it frees the contents while
    // leaving the caller's box alive.
    bool viaParameterPointee = false;

    bool hasBorrow() const { return kind != SemaEscapeKind::None; }
    bool isLocalBorrow() const { return kind == SemaEscapeKind::Local && sourceVar != nullptr; }
    bool isMaterializedBorrow() const { return kind == SemaEscapeKind::Materialized; }
    bool isTemporaryBorrow() const { return kind == SemaEscapeKind::Temporary; }
    bool isDeferredCallBorrow() const { return kind == SemaEscapeKind::DeferredCall; }

    void markStoredFieldBorrow();

    void mergeFrom(const SemaEscapeInfo& other)
    {
        if (kind == other.kind && sourceVar == other.sourceVar)
            viaErasedPayload = viaErasedPayload || other.viaErasedPayload;

        if (kind == SemaEscapeKind::Parameter && other.kind == SemaEscapeKind::Parameter)
        {
            parameterOriginsMask |= other.parameterOriginsMask;
            parameterIndirectOriginsMask |= other.parameterIndirectOriginsMask;

            // A payload route possible on either branch survives the join. Only
            // an unconditional carrier replacement can clear it on every path.
            viaOwnedPayload      = viaOwnedPayload || other.viaOwnedPayload;
            viaErasedPayload     = viaErasedPayload || other.viaErasedPayload;
            detachedOwnedPayload = detachedOwnedPayload || other.detachedOwnedPayload;

            // One direct borrow makes the merged value represent parameter storage.
            viaStoredField = viaStoredField && other.viaStoredField;

            // Naming the box's content exactly takes every alternative agreeing on it.
            viaParameterPointee = viaParameterPointee && other.viaParameterPointee;

            return;
        }

        if (kind == SemaEscapeKind::DeferredCall && other.kind == SemaEscapeKind::DeferredCall)
        {
            for (const auto& call : other.deferredCalls)
            {
                if (std::ranges::find(deferredCalls, call) == deferredCalls.end())
                    deferredCalls.push_back(call);
            }

            for (auto it = detachedOwnedPayloadFields.begin(); it != detachedOwnedPayloadFields.end();)
            {
                if (std::ranges::find(other.detachedOwnedPayloadFields, *it) == other.detachedOwnedPayloadFields.end())
                    it = detachedOwnedPayloadFields.erase(it);
                else
                    ++it;
            }

            return;
        }

        if (other.rank() > rank())
            *this = other;
    }

    // Severity order used when two may-borrow facts merge (flow joins, aggregates).
    int rank() const
    {
        switch (kind)
        {
            case SemaEscapeKind::Temporary:
                return 6;
            case SemaEscapeKind::Materialized:
                return 5;
            case SemaEscapeKind::Local:
                return 4;
            case SemaEscapeKind::Parameter:
                return 3;
            case SemaEscapeKind::DeferredCall:
                return 3;
            case SemaEscapeKind::Unknown:
                return 2;
            case SemaEscapeKind::Static:
                return 1;
            case SemaEscapeKind::None:
                return 0;
        }

        return 0;
    }
};

enum class SemaEscapeProjectionKind : uint8_t
{
    Field,
    ConstantIndex,
    AnyIndex,
};

struct SemaEscapeProjectionComponent
{
    SemaEscapeProjectionKind kind  = SemaEscapeProjectionKind::Field;
    const SymbolVariable*    field = nullptr;
    uint64_t                 index = 0;

    bool operator==(const SemaEscapeProjectionComponent&) const noexcept = default;
};

struct SemaEscapeProjection
{
    const SymbolVariable*                       root = nullptr;
    SmallVector4<SemaEscapeProjectionComponent> components;

    bool operator==(const SemaEscapeProjection& other) const noexcept
    {
        return root == other.root && components.size() == other.components.size() && std::equal(components.begin(), components.end(), other.components.begin());
    }
};

struct SemaEscapeProjectionHash
{
    size_t operator()(const SemaEscapeProjection& projection) const noexcept
    {
        size_t result = std::hash<const SymbolVariable*>{}(projection.root);

        for (const SemaEscapeProjectionComponent& component : projection.components)
        {
            const size_t value = component.kind == SemaEscapeProjectionKind::Field ? std::hash<const SymbolVariable*>{}(component.field) : std::hash<uint64_t>{}(component.index);
            result ^= value + static_cast<size_t>(component.kind) + 0x9e3779b9 + (result << 6) + (result >> 2);
        }

        return result;
    }
};

class Sema
{
    friend class SemaJob;

public:
    struct ActiveCompilerAstExpansion
    {
        Utf8            generatedCode;
        SourceCodeRange codeRange;
    };

    Sema(TaskContext& ctx, NodePayload& payloadContext, bool declPass);
    Sema(TaskContext& ctx, NodePayload& payloadContext, AstNodeRef root, bool declPass);
    Sema(TaskContext& ctx, Sema& parent, AstNodeRef root);
    Sema(TaskContext& ctx, Sema& parent, AstNodeRef root, bool declPass);
    Sema(TaskContext& ctx, Sema& parent, NodePayload& payloadContext, AstNodeRef root);
    Sema(TaskContext& ctx, Sema& parent, NodePayload& payloadContext, AstNodeRef root, bool declPass);
    ~Sema();

    JobResult exec();
    Result    execResult();

    TaskContext&            ctx() { return *(ctx_); }
    const TaskContext&      ctx() const { return *(ctx_); }
    CompilerInstance&       compiler() { return ctx().compiler(); }
    const CompilerInstance& compiler() const { return ctx().compiler(); }

    const Runtime::BuildCfg&        buildCfg() const;
    Runtime::SafetyWhat             runtimeSafetyGuards() const;
    const Runtime::BuildCfgBackend& buildCfgBackend() const { return buildCfg().backend; }
    Runtime::BuildCfgBackendKind    buildCfgBackendKind() const { return buildCfg().backendKind; }
    bool                            isNativeBuild() const { return Runtime::backendKindProducesNativeArtifact(buildCfgBackendKind()); }
    bool                            isNativeExecutableBuild() const { return buildCfgBackendKind() == Runtime::BuildCfgBackendKind::Executable; }

    SymbolFunction*       currentFunction() { return frame().currentFunction(); }
    const SymbolFunction* currentFunction() const { return frame().currentFunction(); }
    bool                  isCurrentFunction() const { return currentFunction() != nullptr; }

    // Cache repeated call dependencies to avoid taking the function lock again
    // for common callees such as runtime safety panic functions.
    bool knowsCallDependency(const SymbolFunction& owner, const SymbolFunction& callee) const
    {
        return knownCallDependencyOwner_ == &owner && knownCallDependencies_[knownCallDependencySlot(callee)] == &callee;
    }

    void noteCallDependency(const SymbolFunction& owner, const SymbolFunction& callee)
    {
        if (knownCallDependencyOwner_ != &owner)
        {
            knownCallDependencyOwner_ = &owner;
            knownCallDependencies_.fill(nullptr);
        }

        knownCallDependencies_[knownCallDependencySlot(callee)] = &callee;
    }

    bool isGlobalScope() const { return !isCurrentFunction(); }
    bool isOptimizeEnabled() const { return buildCfgBackend().optimizes(); }
    bool isConstExprRequired() const { return frame().hasContextFlag(SemaFrameContextFlagsE::RequireConstExpr); }
    bool isRunExprContext() const { return frame().hasContextFlag(SemaFrameContextFlagsE::RunExpr); }
    bool isCompilerEvalContext() const { return frame().hasContextFlag(SemaFrameContextFlagsE::CompilerEval); }
    bool isDeclPass() const { return declPass_; }
    bool enteringState() const { return visit_.enteringState(); }

    // Cheap gate for the default-initialization elision pass: set when this job
    // declares a local the pass may prove safe to leave uninitialized.
    void noteInitFlowCandidate() { hasInitFlowCandidates_ = true; }
    bool hasInitFlowCandidates() const { return hasInitFlowCandidates_; }

    ConstantManager&         cstMgr();
    const ConstantManager&   cstMgr() const;
    TypeManager&             typeMgr();
    const TypeManager&       typeMgr() const;
    TypeGen&                 typeGen();
    const TypeGen&           typeGen() const;
    IdentifierManager&       idMgr();
    const IdentifierManager& idMgr() const;

    SourceView&        srcView(SourceViewRef srcViewRef);
    const SourceView&  srcView(SourceViewRef srcViewRef) const;
    NodePayload&       currentNodePayloadContext() { return nodePayloadContext(); }
    const NodePayload& currentNodePayloadContext() const { return nodePayloadContext(); }
    const SourceFile*  ownerSourceFile(SourceViewRef srcViewRef) const;
    NodePayload*       owningNodePayloadContext(SourceViewRef srcViewRef) const;
    AstNodeRef         ownerDeclNodeRef(SourceViewRef srcViewRef, const AstNode* decl, AstNodeRef declRef = AstNodeRef::invalid()) const;
    Sema*              tryCreateDeclSema(std::unique_ptr<Sema>& outOwnedSema, SourceViewRef srcViewRef, const AstNode* decl, AstNodeRef declRef = AstNodeRef::invalid());
    bool               usesOwningNodePayloadContext(SourceViewRef srcViewRef) const;

    Ast&              ast();
    const Ast&        ast() const;
    AstNode&          node(AstNodeRef nodeRef) { return ast().node(nodeRef); }
    const AstNode&    node(AstNodeRef nodeRef) const { return ast().node(nodeRef); }
    const Token&      token(const SourceCodeRef& codeRef) const { return srcView(codeRef.srcViewRef).token(codeRef.tokRef); }
    SourceCodeRange   tokenCodeRange(const SourceCodeRef& codeRef) const { return srcView(codeRef.srcViewRef).tokenCodeRange(ctx(), codeRef.tokRef); }
    std::string_view  tokenString(const SourceCodeRef& codeRef) const { return srcView(codeRef.srcViewRef).tokenString(codeRef.tokRef); }
    Utf8              fileName() const;
    const SourceFile* file() const;

    // Assign the next with-subject rank; see SemaScope::AutoMemberBinding::order.
    static uint64_t nextAutoMemberOrder();

    std::vector<ActiveCompilerAstExpansion>&       compilerAstExpansions() { return compilerAstExpansions_; }
    const std::vector<ActiveCompilerAstExpansion>& compilerAstExpansions() const { return compilerAstExpansions_; }

    SemaFrame&                 frame() { return frames_.back(); }
    const SemaFrame&           frame() const { return frames_.back(); }
    std::span<const SemaFrame> frames() const { return frames_; }

    void addNarrowKillAllFrames(std::span<const Symbol* const> path);
    void addNarrowFactPastBindingFrames(std::span<const Symbol* const> path, SemaNarrowFactKind kind);
    void addNarrowCaseFactPastBindingFrames(std::span<const Symbol* const> path, std::span<const ConstantRef> cases);
    bool anyFrameHasNarrowFacts() const;

    // Preserve branch facts after their body frame is popped: arm snapshots at
    // postNode(), capture snapshots now, and take consumes the saved facts once.
    void armNarrowFactCapture(AstNodeRef bodyRef);
    void captureNarrowFacts(AstNodeRef bodyRef);
    bool takeNarrowFactCapture(AstNodeRef bodyRef, SmallVector2<SemaNarrowFact>& facts);

    SemaScope*       curScopePtr() { return curScope_; }
    const SemaScope* curScopePtr() const { return curScope_; }
    SemaScope&       curScope() { return *(curScope_); }
    const SemaScope& curScope() const { return *(curScope_); }

    SemaScope*       lookupScope();
    const SemaScope* lookupScope() const;
    SemaScope*       upLookupScope() { return frame().upLookupScope(); }
    const SemaScope* upLookupScope() const { return frame().upLookupScope(); }
    SemaScope*       resolvedUpLookupScope();
    const SemaScope* resolvedUpLookupScope() const;
    static void      configureLookupFrame(SemaFrame& frame, SemaScope* lookupScope, bool ignoreRuntimeAccess = false);

    void restartCurrentNode(AstNodeRef nodeRef);
    void rebindTaskContext(TaskContext& ctx) { ctx_ = &ctx; }

    AstVisit&       visit() { return visit_; }
    const AstVisit& visit() const { return visit_; }
    AstNodeRef      curNodeRef() const { return visit_.currentNodeRef(); }
    AstNode&        curNode() { return node(curNodeRef()); }
    const AstNode&  curNode() const { return node(curNodeRef()); }

    SymbolMap*       curSymMap() { return curScope_->symMap(); }
    const SymbolMap* curSymMap() const { return curScope_->symMap(); }
    const SymbolMap* topSymMap() const { return startSymMap_; }
    const Symbol*    waiterSymbol();

    const SymbolNamespace& moduleNamespace() const { return nodePayloadContext().moduleNamespace(); }
    SymbolNamespace&       moduleNamespace() { return nodePayloadContext().moduleNamespace(); }
    void                   setModuleNamespace(SymbolNamespace& ns) { nodePayloadContext().setModuleNamespace(ns); }

    const SymbolNamespace& fileNamespace() const { return nodePayloadContext().fileNamespace(); }
    SymbolNamespace&       fileNamespace() { return nodePayloadContext().fileNamespace(); }
    void                   setFileNamespace(SymbolNamespace& ns) { nodePayloadContext().setFileNamespace(ns); }

    // Resolve only the node identity when no semantic view data is needed.
    AstNodeRef resolvedNodeRef(AstNodeRef nodeRef) const { return nodePayloadContext().getSubstituteRef(nodeRef); }

    SemaNodeView view(AstNodeRef nodeRef);
    SemaNodeView view(AstNodeRef nodeRef, EnumFlags<SemaNodeViewPartE> part);
    SemaNodeView viewStored(AstNodeRef nodeRef) { return viewStored(nodeRef, SemaNodeViewPartE::All); }
    SemaNodeView viewStored(AstNodeRef nodeRef, EnumFlags<SemaNodeViewPartE> part);

    SemaNodeView viewZero(AstNodeRef nodeRef) { return view(nodeRef, SemaNodeViewPartE::Zero); }
    SemaNodeView viewNode(AstNodeRef nodeRef) { return view(nodeRef, SemaNodeViewPartE::Node); }
    SemaNodeView viewType(AstNodeRef nodeRef) { return view(nodeRef, SemaNodeViewPartE::Type); }
    SemaNodeView viewConstant(AstNodeRef nodeRef) { return view(nodeRef, SemaNodeViewPartE::Constant); }
    SemaNodeView viewSymbol(AstNodeRef nodeRef) { return view(nodeRef, SemaNodeViewPartE::Symbol); }
    SemaNodeView viewTypeConstant(AstNodeRef nodeRef) { return view(nodeRef, SemaNodeViewPartE::Type | SemaNodeViewPartE::Constant); }
    SemaNodeView viewTypeSymbol(AstNodeRef nodeRef) { return view(nodeRef, SemaNodeViewPartE::Type | SemaNodeViewPartE::Symbol); }
    SemaNodeView viewNodeType(AstNodeRef nodeRef) { return view(nodeRef, SemaNodeViewPartE::Node | SemaNodeViewPartE::Type); }
    SemaNodeView viewNodeTypeConstant(AstNodeRef nodeRef) { return view(nodeRef, SemaNodeViewPartE::Node | SemaNodeViewPartE::Type | SemaNodeViewPartE::Constant); }
    SemaNodeView viewNodeTypeSymbol(AstNodeRef nodeRef) { return view(nodeRef, SemaNodeViewPartE::Node | SemaNodeViewPartE::Type | SemaNodeViewPartE::Symbol); }
    SemaNodeView viewNodeTypeConstantSymbol(AstNodeRef nodeRef) { return view(nodeRef, SemaNodeViewPartE::Node | SemaNodeViewPartE::Type | SemaNodeViewPartE::Constant | SemaNodeViewPartE::Symbol); }
    SemaNodeView viewNodeSymbolList(AstNodeRef nodeRef) { return view(nodeRef, SemaNodeViewPartE::Node | SemaNodeViewPartE::Symbol); }

    SemaNodeView curView();
    SemaNodeView curView(EnumFlags<SemaNodeViewPartE> part);

    SemaNodeView curViewZero() { return curView(SemaNodeViewPartE::Zero); }
    SemaNodeView curViewNode() { return curView(SemaNodeViewPartE::Node); }
    SemaNodeView curViewType() { return curView(SemaNodeViewPartE::Type); }
    SemaNodeView curViewConstant() { return curView(SemaNodeViewPartE::Constant); }
    SemaNodeView curViewSymbol() { return curView(SemaNodeViewPartE::Symbol); }
    SemaNodeView curViewTypeConstant() { return curView(SemaNodeViewPartE::Type | SemaNodeViewPartE::Constant); }
    SemaNodeView curViewTypeSymbol() { return curView(SemaNodeViewPartE::Type | SemaNodeViewPartE::Symbol); }
    SemaNodeView curViewNodeType() { return curView(SemaNodeViewPartE::Node | SemaNodeViewPartE::Type); }
    SemaNodeView curViewNodeTypeConstant() { return curView(SemaNodeViewPartE::Node | SemaNodeViewPartE::Type | SemaNodeViewPartE::Constant); }
    SemaNodeView curViewNodeTypeSymbol() { return curView(SemaNodeViewPartE::Node | SemaNodeViewPartE::Type | SemaNodeViewPartE::Symbol); }
    SemaNodeView curViewNodeTypeConstantSymbol() { return curView(SemaNodeViewPartE::Node | SemaNodeViewPartE::Type | SemaNodeViewPartE::Constant | SemaNodeViewPartE::Symbol); }

    void setType(AstNodeRef n, TypeRef ref) { nodePayloadContext().setType(n, ref); }
    void setConstant(AstNodeRef n, ConstantRef ref) { nodePayloadContext().setConstant(n, ref); }
    void clearConstant(AstNodeRef n) { nodePayloadContext().clearConstant(n); }
    void setSymbol(AstNodeRef n, Symbol* symbol) { nodePayloadContext().setSymbol(n, symbol); }
    void setSymbol(AstNodeRef n, const Symbol* symbol) { nodePayloadContext().setSymbol(n, symbol); }

    bool hasSubstitute(AstNodeRef n) const { return nodePayloadContext().hasSubstitute(n); }
    void setSubstitute(AstNodeRef n, AstNodeRef substNodeRef) { nodePayloadContext().setSubstitute(n, substNodeRef); }
    void recordImplicitPropagation(AstNodeRef n) { nodePayloadContext().recordImplicitPropagation(n); }

    void setSymbolList(AstNodeRef n, std::span<const Symbol*> symbols) { nodePayloadContext().setSymbolList(n, symbols); }
    void setSymbolList(AstNodeRef n, std::span<Symbol*> symbols) { nodePayloadContext().setSymbolList(n, symbols); }

    // Code generation jobs keep local lowering payloads. The table allocates
    // only on first insertion; a null lookup always means absent.
    void enableLocalLoweringPayloads() { localLoweringPayloads_.emplace(); }
    bool usesLocalLoweringPayloads() const { return localLoweringPayloads_.has_value(); }

    bool hasLoweringPayload(AstNodeRef n) const
    {
        if (localLoweringPayloads_ && localLoweringPayloads_->find(n))
            return true;

        return nodePayloadContext().hasLoweringPayload(n);
    }

    void setLoweringPayload(AstNodeRef n, void* payload)
    {
        SWC_ASSERT(payload != nullptr);

        if (localLoweringPayloads_)
        {
            localLoweringPayloads_->set(n, payload);
            return;
        }

        nodePayloadContext().setLoweringPayload(n, payload);
    }

    template<typename T>
    T* loweringPayload(AstNodeRef n) const
    {
        if (localLoweringPayloads_)
        {
            if (void* local = localLoweringPayloads_->find(n))
                return static_cast<T*>(local);
        }

        return static_cast<T*>(nodePayloadContext().getLoweringPayload(n));
    }

    template<typename T>
    T* mutableLoweringPayload(AstNodeRef n)
    {
        if (!localLoweringPayloads_)
            return static_cast<T*>(nodePayloadContext().getLoweringPayload(n));

        if (void* local = localLoweringPayloads_->find(n))
            return static_cast<T*>(local);

        void* inherited = nodePayloadContext().getLoweringPayload(n);
        if (!inherited)
            return nullptr;

        auto* payload = ctx().allocate<T>();
        *payload      = *static_cast<T*>(inherited);
        localLoweringPayloads_->set(n, payload);
        return payload;
    }

    bool                      hasInlinePayload(AstNodeRef n) const { return nodePayloadContext().hasInlinePayload(n); }
    void                      setInlinePayload(AstNodeRef n, SemaInlinePayload* payload) { nodePayloadContext().setInlinePayload(n, payload); }
    SemaInlinePayload*        inlinePayload(AstNodeRef n) const { return static_cast<SemaInlinePayload*>(nodePayloadContext().getInlinePayload(n)); }
    static SemaInlinePayload* inlinePayload(const SymbolFunction& function);

    template<typename T>
    void setInlineContextOverride(AstNodeRef n, T* payload)
    {
        nodePayloadContext().setInlineContextOverride(n, payload);
    }

    void inlineContext(AstNodeRef n, void*& outPayload, void*& outOverride) const { nodePayloadContext().getInlineContext(n, outPayload, outOverride); }

    template<typename T>
    T* inlineContextOverride(AstNodeRef n) const
    {
        void* payload = nodePayloadContext().getInlineContextOverride(n);
        if (!payload)
            return nullptr;

        return static_cast<T*>(payload);
    }

    bool hasSemaPayload(AstNodeRef n) const { return nodePayloadContext().hasSemaPayload(n); }
    void clearSemaPayload(AstNodeRef n) { nodePayloadContext().clearSemaPayload(n); }

    template<typename T>
    void setSemaPayload(AstNodeRef n, T* payload)
    {
        nodePayloadContext().setSemaPayload(n, payload);
    }

    template<typename T>
    T* semaPayload(AstNodeRef n) const
    {
        void* payload = nodePayloadContext().getSemaPayload(n);
        if (!payload)
            return nullptr;

        return static_cast<T*>(payload);
    }

    // Allocate persistent semantic payloads from the compiler on first request.
    template<typename T>
    T& ensureSemaPayload(AstNodeRef n)
    {
        if (T* payload = semaPayload<T>(n))
            return *payload;

        T* payload = compiler().allocate<T>();
        setSemaPayload(n, payload);
        return *payload;
    }

    void                                setResolvedCallArguments(AstNodeRef n, std::span<const ResolvedCallArgument> args) { nodePayloadContext().setResolvedCallArguments(n, args); }
    void                                appendResolvedCallArguments(AstNodeRef n, SmallVector<ResolvedCallArgument>& out) const { nodePayloadContext().appendResolvedCallArguments(n, out); }
    ResolvedCallArgument                getResolvedCallArgument(AstNodeRef n, uint32_t index) const { return nodePayloadContext().getResolvedCallArgument(n, index); }
    std::optional<ResolvedCallArgument> tryGetResolvedCallArgument(AstNodeRef n, uint32_t index) const { return nodePayloadContext().tryGetResolvedCallArgument(n, index); }

    void markImplicitCodeBlockArg(AstNodeRef parentRef, AstNodeRef childRef);
    bool isImplicitCodeBlockArg(AstNodeRef parentRef, AstNodeRef childRef) const;

    const SemaEscapeInfo* variableEscapeInfo(const SymbolVariable& symVar) const;

    // Track local borrows for checks that start from the borrowed storage.
    using VariableEscapeInfoMap   = std::unordered_map<const SymbolVariable*, SemaEscapeInfo>;
    using ProjectionEscapeInfoMap = std::unordered_map<SemaEscapeProjection, SemaEscapeInfo, SemaEscapeProjectionHash>;

    const VariableEscapeInfoMap&   variableEscapeInfos() const { return *variableEscapeInfos_; }
    const ProjectionEscapeInfoMap& projectionEscapeInfos() const { return *projectionEscapeInfos_; }

    void setVariableEscapeInfo(const SymbolVariable& symVar, const SemaEscapeInfo& info);
    void clearVariableEscapeInfo(const SymbolVariable& symVar);
    void detachVariableOwnedPayload(const SymbolVariable& symVar);
    void detachVariableOwnedPayloadField(const SymbolVariable& symVar, const SymbolVariable& owner, const SymbolVariable& field);

    SemaEscapeInfo variableEscapeInfoIncludingProjections(const SymbolVariable& symVar) const;
    SemaEscapeInfo projectionEscapeInfoIncludingWildcards(const SemaEscapeProjection& projection) const;

    // Read one field's borrow without merging unrelated fields. Allocator
    // requests, for example, can carry distinct block and diagnostic-hint borrows.
    SemaEscapeInfo variableFieldEscapeInfo(const SymbolVariable& symVar, std::string_view fieldName) const;

    void setProjectionEscapeInfo(const SemaEscapeProjection& projection, const SemaEscapeInfo& info);
    void clearProjectionEscapeInfo(const SemaEscapeProjection& projection);

    // Storage changes are checked after the body is fully resolved by
    // SemaEscape::reportBorrowInvalidations.
    std::span<const SemaBorrowInvalidation> borrowInvalidations() const { return borrowInvalidations_.span(); }
    void                                    addBorrowInvalidation(const SemaBorrowInvalidation& record) { borrowInvalidations_.push_back(record); }
    void                                    setBorrowInvalidations(std::span<const SemaBorrowInvalidation> records)
    {
        borrowInvalidations_.clear();
        for (const SemaBorrowInvalidation& record : records)
            borrowInvalidations_.push_back(record);
    }

    // Lexical depth of the scope a local variable is declared in (0 = unknown).
    uint32_t variableScopeDepth(const SymbolVariable& symVar) const;
    void     setVariableScopeDepth(const SymbolVariable& symVar, uint32_t depth);
    uint32_t currentScopeDepth() const;

    // Orders local lifetimes by lexical depth, then by reverse declaration order.
    bool localStorageOutlives(const SymbolVariable& destination, const SymbolVariable& source) const;

    // A merged local borrow keeps the shortest lifetime, including at flow joins.
    void mergeEscapeInfo(SemaEscapeInfo& destination, const SemaEscapeInfo& source) const;

    void clearProjectionsOfRoot(const SymbolVariable& symVar);

    // Each branch starts from the entry state. Union at the join preserves
    // every possible borrow, including one cleared on only some paths.
    void pushEscapeBranch();
    void nextEscapeBranchAlternative();
    void popEscapeBranch(bool mergeEntryState);

    bool isLValue(const AstNode& node) const { return NodePayload::hasPayloadFlags(node, NodePayloadFlags::LValue); }
    bool isLValue(AstNodeRef ref) const { return NodePayload::hasPayloadFlags(node(resolvedNodeRef(ref)), NodePayloadFlags::LValue); }
    bool isLValueStored(AstNodeRef ref) const;
    void setIsLValue(AstNode& node) { NodePayload::addPayloadFlags(node, NodePayloadFlags::LValue); }
    void setIsLValue(AstNodeRef ref) { NodePayload::addPayloadFlags(node(ref), NodePayloadFlags::LValue); }
    void unsetIsLValue(AstNode& node) { NodePayload::removePayloadFlags(node, NodePayloadFlags::LValue); }
    void unsetIsLValue(AstNodeRef ref) { NodePayload::removePayloadFlags(node(ref), NodePayloadFlags::LValue); }

    bool isValue(const AstNode& node) const { return NodePayload::hasPayloadFlags(node, NodePayloadFlags::Value); }
    bool isValue(AstNodeRef ref) const { return NodePayload::hasPayloadFlags(node(resolvedNodeRef(ref)), NodePayloadFlags::Value); }
    bool isValueStored(AstNodeRef ref) const;
    void setIsValue(AstNode& node) { NodePayload::addPayloadFlags(node, NodePayloadFlags::Value); }
    void setIsValue(AstNodeRef ref) { NodePayload::addPayloadFlags(node(ref), NodePayloadFlags::Value); }
    void unsetIsValue(AstNode& node) { NodePayload::removePayloadFlags(node, NodePayloadFlags::Value); }
    void unsetIsValue(AstNodeRef ref) { NodePayload::removePayloadFlags(node(ref), NodePayloadFlags::Value); }

    bool isFoldedTypedConst(const AstNode& node) const { return NodePayload::hasPayloadFlags(node, NodePayloadFlags::FoldedTypedConst); }
    bool isFoldedTypedConst(AstNodeRef ref) const { return NodePayload::hasPayloadFlags(node(resolvedNodeRef(ref)), NodePayloadFlags::FoldedTypedConst); }
    bool isFoldedTypedConstStored(AstNodeRef ref) const;
    void setFoldedTypedConst(AstNode& node) { NodePayload::addPayloadFlags(node, NodePayloadFlags::FoldedTypedConst); }
    void unsetFoldedTypedConst(AstNode& node) { NodePayload::removePayloadFlags(node, NodePayloadFlags::FoldedTypedConst); }
    void unsetFoldedTypedConst(AstNodeRef ref) { NodePayload::removePayloadFlags(node(ref), NodePayloadFlags::FoldedTypedConst); }
    void setFoldedTypedConst(AstNodeRef ref) { NodePayload::addPayloadFlags(node(ref), NodePayloadFlags::FoldedTypedConst); }

    bool                  isConstAssignBinding(const AstNode& node) const { return NodePayload::hasPayloadFlags(node, NodePayloadFlags::ConstAssignBinding); }
    bool                  isConstAssignBinding(AstNodeRef ref) const { return NodePayload::hasPayloadFlags(node(resolvedNodeRef(ref)), NodePayloadFlags::ConstAssignBinding); }
    bool                  isConstAssignBindingStored(AstNodeRef ref) const;
    const SymbolVariable* constAssignSourceParameter(AstNodeRef ref) const;
    void                  setConstAssignBinding(AstNode& node) { NodePayload::addPayloadFlags(node, NodePayloadFlags::ConstAssignBinding); }
    void                  setConstAssignBinding(AstNodeRef ref) { NodePayload::addPayloadFlags(node(ref), NodePayloadFlags::ConstAssignBinding); }
    void                  setConstAssignBinding(AstNodeRef ref, const SymbolVariable* sourceParam)
    {
        NodePayload::addPayloadFlags(node(ref), NodePayloadFlags::ConstAssignBinding);
        nodePayloadContext().setConstAssignSourceParameter(ref, sourceParam);
    }

    void unsetConstAssignBinding(AstNode& node) { NodePayload::removePayloadFlags(node, NodePayloadFlags::ConstAssignBinding); }
    void unsetConstAssignBinding(AstNodeRef ref) { NodePayload::removePayloadFlags(node(ref), NodePayloadFlags::ConstAssignBinding); }

    bool isConstAssignTarget(const AstNode& node) const { return NodePayload::hasPayloadFlags(node, NodePayloadFlags::ConstAssignTarget); }
    bool isConstAssignTarget(AstNodeRef ref) const { return NodePayload::hasPayloadFlags(node(resolvedNodeRef(ref)), NodePayloadFlags::ConstAssignTarget); }
    bool isConstAssignTargetStored(AstNodeRef ref) const;
    void setConstAssignTarget(AstNode& node) { NodePayload::addPayloadFlags(node, NodePayloadFlags::ConstAssignTarget); }
    void setConstAssignTarget(AstNodeRef ref) { NodePayload::addPayloadFlags(node(ref), NodePayloadFlags::ConstAssignTarget); }
    void unsetConstAssignTarget(AstNode& node) { NodePayload::removePayloadFlags(node, NodePayloadFlags::ConstAssignTarget); }
    void unsetConstAssignTarget(AstNodeRef ref) { NodePayload::removePayloadFlags(node(ref), NodePayloadFlags::ConstAssignTarget); }

    void inheritPayloadFlags(AstNode& nodeDst, AstNodeRef srcRef) { NodePayload::propagatePayloadFlags(nodeDst, node(srcRef), NODE_PAYLOAD_FLAGS_MASK, false); }
    void inheritPayloadKindRef(AstNode& nodeDst, AstNodeRef srcRef) { NodePayload::inheritPayloadKindRef(nodeDst, node(srcRef)); }
    void inheritPayload(AstNode& nodeDst, AstNodeRef srcRef) { NodePayload::inheritPayload(nodeDst, node(srcRef)); }

    void copyResolvedCallArguments(AstNodeRef dstRef, AstNodeRef srcRef) { nodePayloadContext().copyResolvedCallArguments(dstRef, srcRef); }

    // Moving a finished local frame avoids copying its function attributes again.
    void pushFramePopOnPostChild(const SemaFrame& frame, AstNodeRef popAfterChildRef);
    void pushFramePopOnPostChild(SemaFrame&& frame, AstNodeRef popAfterChildRef);
    void pushFramePopOnPostNode(const SemaFrame& frame, AstNodeRef popNodeRef = AstNodeRef::invalid());
    void pushFramePopOnPostNode(SemaFrame&& frame, AstNodeRef popNodeRef = AstNodeRef::invalid());

    SemaScope* pushScopePopOnPostChild(SemaScopeFlags flags, AstNodeRef popAfterChildRef);
    SemaScope* pushScopePopOnPostNode(SemaScopeFlags flags, AstNodeRef popNodeRef = AstNodeRef::invalid());

    void deferPostNodeAction(AstNodeRef nodeRef, std::function<Result(Sema&, AstNodeRef)> callback);
    void processCurrentPostNodePopsNow();

    Result waitIdentifier(IdentifierRef idRef, const SourceCodeRef& codeRef);
    Result waitScopedMember(IdentifierRef idRef, const SourceCodeRef& codeRef);
    Result waitAutoScopeMember(IdentifierRef idRef, TypeRef candidateTypeRef, const SourceCodeRef& codeRef);
    Result waitPredefined(IdentifierManager::PredefinedName name, TypeRef& typeRef, const SourceCodeRef& codeRef);
    Result waitRuntimeFunction(IdentifierManager::RuntimeFunctionKind kind, SymbolFunction*& symbol, const SourceCodeRef& codeRef);
    Result waitCompilerDefined(IdentifierRef idRef, const SourceCodeRef& codeRef);
    Result waitImplRegistrations(IdentifierRef idRef, const SourceCodeRef& codeRef);

    Result completeLazyFunction(SymbolFunction& calledFn);
    Result waitSemaCompletedNoLazy(const Symbol* symbol, const SourceCodeRef& codeRef);
    Result waitSemaCompleted(const Symbol* symbol, const SourceCodeRef& codeRef);
    Result waitCodeGenPreSolved(const Symbol* symbol, const SourceCodeRef& codeRef);
    Result waitCodeGenCompleted(const Symbol* symbol, const SourceCodeRef& codeRef);
    Result waitDeclared(const Symbol* symbol, const SourceCodeRef& codeRef);
    Result waitTyped(const Symbol* symbol, const SourceCodeRef& codeRef);
    Result waitConstraintsResolved(const Symbol* symbol, const SourceCodeRef& codeRef);
    Result waitSemaCompleted(const TypeInfo* type, AstNodeRef nodeRef);
    Result waitTypeInfoGeneration(std::atomic<uint64_t>& owner, uint64_t generation, AstNodeRef nodeRef);

    // Records why this job cannot go on and hands the worker back to the scheduler.
    Result parkOnSymbol(TaskStateKind kind, const Symbol* blockingSymbol, AstNodeRef nodeRef, const SourceCodeRef& codeRef);

    Result      makeRuntimeTypeInfo(ConstantRef& outRef, TypeRef typeRef, AstNodeRef ownerNodeRef);
    Result      prepareFunctionSignature(AstNodeRef functionRef);
    static void waitDone(TaskContext& ctx, JobClientId clientId);

private:
    friend struct SemaNodeView;
    friend void SemaGeneric::prepareGenericInstantiationContext(Sema& sema, SymbolMap* startSymMap, const SymbolImpl* impl, const SymbolInterface* itf, const AttributeList& attrs);

    bool hasActiveLookupScopeOverride() const;

    enum class NameScope : uint8_t
    {
        Unscoped,
        Member,
    };

    Result waitName(IdentifierRef idRef, const SourceCodeRef& codeRef, NameScope scope);

    TypeRef              typeRefOf(AstNodeRef n) const { return nodePayloadContext().getTypeRef(ctx(), resolvedNodeRef(n)); }
    ConstantRef          constantRefOf(AstNodeRef n) const { return nodePayloadContext().getConstantRef(ctx(), resolvedNodeRef(n)); }
    TypeRef              typeRefOfStored(AstNodeRef n) const { return nodePayloadContext().getTypeRef(ctx(), n); }
    ConstantRef          constantRefOfStored(AstNodeRef n) const { return nodePayloadContext().getConstantRef(ctx(), n); }
    const ConstantValue& constantOf(AstNodeRef n) const { return nodePayloadContext().getConstant(ctx(), resolvedNodeRef(n)); }
    const Symbol&        symbolOf(AstNodeRef n) const { return nodePayloadContext().getSymbol(ctx(), resolvedNodeRef(n)); }
    Symbol&              symbolOf(AstNodeRef n) { return nodePayloadContext().getSymbol(ctx(), resolvedNodeRef(n)); }
    const Symbol&        symbolOfStored(AstNodeRef n) const { return nodePayloadContext().getSymbol(ctx(), n); }
    Symbol&              symbolOfStored(AstNodeRef n) { return nodePayloadContext().getSymbol(ctx(), n); }

    bool       hasType(AstNodeRef n) const { return nodePayloadContext().hasType(ctx(), resolvedNodeRef(n)); }
    bool       hasConstant(AstNodeRef n) const { return nodePayloadContext().hasConstant(ctx(), resolvedNodeRef(n)); }
    bool       hasSymbol(AstNodeRef n) const { return nodePayloadContext().hasSymbol(resolvedNodeRef(n)); }
    bool       hasSymbolStored(AstNodeRef n) const { return nodePayloadContext().hasSymbol(n); }
    AstNodeRef getSubstituteRef(AstNodeRef n) const { return resolvedNodeRef(n); }

    bool                     hasSymbolList(AstNodeRef n) const { return nodePayloadContext().hasSymbolList(resolvedNodeRef(n)); }
    std::span<const Symbol*> getSymbolList(AstNodeRef n) const { return nodePayloadContext().getSymbolList(resolvedNodeRef(n)); }
    std::span<Symbol*>       getSymbolList(AstNodeRef n) { return nodePayloadContext().getSymbolList(resolvedNodeRef(n)); }
    bool                     hasSymbolListStored(AstNodeRef n) const { return nodePayloadContext().hasSymbolList(n); }
    std::span<const Symbol*> getSymbolListStored(AstNodeRef n) const { return nodePayloadContext().getSymbolList(n); }
    std::span<Symbol*>       getSymbolListStored(AstNodeRef n) { return nodePayloadContext().getSymbolList(n); }

    bool               hasSymbolRaw(AstNodeRef n) const { return nodePayloadContext().hasSymbol(n); }
    const Symbol&      symbolOfRaw(AstNodeRef n) const { return nodePayloadContext().getSymbol(ctx(), n); }
    Symbol&            symbolOfRaw(AstNodeRef n) { return nodePayloadContext().getSymbol(ctx(), n); }
    bool               hasSymbolListRaw(AstNodeRef n) const { return nodePayloadContext().hasSymbolList(n); }
    std::span<Symbol*> getSymbolListRaw(AstNodeRef n) { return nodePayloadContext().getSymbolList(n); }

    NodePayload::ResolvedSymbols resolveSymbols(AstNodeRef n) const { return nodePayloadContext().resolveSymbols(resolvedNodeRef(n)); }
    NodePayload::ResolvedSymbols resolveSymbolsStored(AstNodeRef n) const { return nodePayloadContext().resolveSymbols(n); }

    SemaScope* pushScope(SemaScopeFlags flags);
    void       popScope();

    void pushFrame(const SemaFrame& frame);
    void pushFrame(SemaFrame&& frame);
    void deferFramePopOnPostChild(AstNodeRef popAfterChildRef);
    void deferFramePopOnPostNode(AstNodeRef popNodeRef);
    void popFrame();

    NodePayload&       nodePayloadContext() { return *(nodePayloadContext_); }
    const NodePayload& nodePayloadContext() const { return *(nodePayloadContext_); }

    static void       inheritMissingNamespaces(TaskContext& ctx, NodePayload& payloadContext);
    static SymbolMap* topLevelStartSymMap(TaskContext& ctx, NodePayload& payloadContext);
    static SymbolMap* childStartSymMap(Sema& parent, NodePayload& payloadContext);

    void   setVisitors();
    Result preDecl(AstNode& node);
    Result preDeclChild(AstNode& node, AstNodeRef& childRef);
    Result postDeclChild(AstNode& node, AstNodeRef& childRef);
    Result postDecl(AstNode& node);

    Result preNode(AstNode& node);
    Result postNode(AstNode& node);
    Result preNodeChild(AstNode& node, AstNodeRef& childRef);
    Result postNodeChild(AstNode& node, AstNodeRef& childRef);

    void errorCleanupNode(AstNodeRef nodeRef, AstNode& node);
    void cleanupFailedVisit();

    enum class DeferredTopLevelItemKind : uint8_t
    {
        SemaJob,
        CompilerRun,
        CompilerAst,
    };

    // Deferred items outlive the enclosing walk, so nested items retain its
    // frame context. Top-level items can reuse the current base frame.
    struct DeferredTopLevelItem
    {
        AstNodeRef                       nodeRef;
        DeferredTopLevelItemKind         kind;
        std::shared_ptr<const SemaFrame> frame;
    };

    Result runCurrentVisit();
    Result processDeferredTopLevelItems();
    Result processDeferredTopLevelNode(const DeferredTopLevelItem& item, uint32_t insertIndex);
    Result processPendingTopLevelCompilerRuns(uint32_t insertIndex);
    void   deferTopLevelItem(AstNodeRef nodeRef, DeferredTopLevelItemKind kind);
    void   enqueueTopLevelSemaJob(AstNodeRef nodeRef);

    void   processDeferredPopsPostChild(AstNodeRef nodeRef, AstNodeRef childRef);
    void   processDeferredPopsPostNode(AstNodeRef nodeRef);
    Result processDeferredPostNodeActions(AstNodeRef nodeRef);

    TaskContext*                             ctx_                = nullptr;
    NodePayload*                             nodePayloadContext_ = nullptr;
    std::optional<RefPointerMap<AstNodeRef>> localLoweringPayloads_;

    struct EscapeBranchState
    {
        // Share each alternative's entry state and copy only on mutation.
        // Create merged maps lazily: even an empty map would allocate.
        std::shared_ptr<VariableEscapeInfoMap>   entryState;
        std::shared_ptr<ProjectionEscapeInfoMap> entryProjectionState;
        std::optional<VariableEscapeInfoMap>     mergedState;
        std::optional<ProjectionEscapeInfoMap>   mergedProjectionState;
    };

    SmallVector4<SemaBorrowInvalidation> borrowInvalidations_;

    // Branch snapshots share their maps until a writer changes a fact. Empty
    // maps are shared across all semas, including declaration and codegen jobs.
    static const std::shared_ptr<VariableEscapeInfoMap>&   emptyVariableEscapeInfos();
    static const std::shared_ptr<ProjectionEscapeInfoMap>& emptyProjectionEscapeInfos();
    VariableEscapeInfoMap&                                 mutableVariableEscapeInfos();
    ProjectionEscapeInfoMap&                               mutableProjectionEscapeInfos();

    std::shared_ptr<VariableEscapeInfoMap>   variableEscapeInfos_   = emptyVariableEscapeInfos();
    std::shared_ptr<ProjectionEscapeInfoMap> projectionEscapeInfos_ = emptyProjectionEscapeInfos();

    // Only a function body records scope depths; the map exists once one is recorded.
    std::optional<std::unordered_map<const SymbolVariable*, uint32_t>> variableScopeDepths_;
    std::vector<EscapeBranchState>                                     escapeBranchStack_;

    AstVisit visit_;

    SemaScopeArena            scopeArena_;
    std::vector<SemaScopePtr> scopes_;
    SymbolMap*                startSymMap_ = nullptr;
    SemaScope*                curScope_    = nullptr;

    bool declPass_              = false;
    bool rootVisitDone_         = false;
    bool hasInitFlowCandidates_ = false;

    static size_t                         knownCallDependencySlot(const SymbolFunction& callee) { return (reinterpret_cast<uintptr_t>(&callee) * 0x9E3779B97F4A7C15ull) >> 60; }
    const SymbolFunction*                 knownCallDependencyOwner_ = nullptr;
    std::array<const SymbolFunction*, 16> knownCallDependencies_    = {};

    std::vector<SemaFrame> frames_;

    struct DeferredPopFrame
    {
        AstNodeRef nodeRef;
        AstNodeRef childRef;
        bool       onPostNode = false;
        size_t     expectedFrameCountBefore;
        size_t     expectedFrameCountAfter;
    };

    struct DeferredPopScope
    {
        AstNodeRef nodeRef;
        AstNodeRef childRef;
        bool       onPostNode = false;
        size_t     expectedScopeCountBefore;
        size_t     expectedScopeCountAfter;
    };

    std::vector<DeferredPopFrame> deferredPopFrames_;
    std::vector<DeferredPopScope> deferredPopScopes_;

    struct NarrowFactCapture
    {
        AstNodeRef                   nodeRef = AstNodeRef::invalid();
        SmallVector2<SemaNarrowFact> facts;
        bool                         filled = false;
    };

    std::vector<NarrowFactCapture> narrowFactCaptures_;

    struct DeferredPostNodeAction
    {
        AstNodeRef                               nodeRef;
        std::function<Result(Sema&, AstNodeRef)> callback;
    };

    std::vector<DeferredPostNodeAction>     deferredPostNodeActions_;
    std::vector<ActiveCompilerAstExpansion> compilerAstExpansions_;

    std::vector<DeferredTopLevelItem> deferredTopLevelItems_;
    std::vector<DeferredTopLevelItem> pendingTopLevelCompilerRuns_;
    uint32_t                          deferredTopLevelItemIndex_       = 0;
    uint32_t                          deferredTopLevelItemInsertIndex_ = 0;
    uint32_t                          pendingTopLevelCompilerRunIndex_ = 0;
    bool                              deferTopLevelItems_              = false;
    bool                              deferredTopLevelItemRunning_     = false;
};

SWC_END_NAMESPACE();
