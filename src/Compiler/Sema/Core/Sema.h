// ReSharper disable CppMemberFunctionMayBeStatic
#pragma once
#include "Backend/Runtime.h"
#include "Compiler/Parser/Ast/Ast.h"
#include "Compiler/Parser/Ast/AstVisit.h"
#include "Compiler/Sema/Core/NodePayload.h"
#include "Compiler/Sema/Core/SemaFrame.h"
#include "Compiler/Sema/Core/SemaNodeView.h"
#include "Compiler/Sema/Core/SemaScope.h"
#include "Compiler/Sema/Helpers/SemaEscape.h"
#include "Compiler/Sema/Symbol/IdentifierManager.h"
#include "Support/Core/Flags.h"
#include "Support/Core/RefTypes.h"
#include "Support/Core/Result.h"
#include "Support/Core/Utf8.h"
#include "Support/Thread/Job.h"

SWC_BEGIN_NAMESPACE();

struct CastRequest;
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
    // Opaque-call snapshots carried by this value. Shared ownership keeps them valid
    // when nested Sema instances and control-flow alternatives exchange their state.
    SmallVector4<std::shared_ptr<const SemaEscapeDeferredCallSnapshot>> deferredCalls;
    // Lexical depth of the storage backing a Materialized borrow (0 = unknown).
    uint32_t sourceScopeDepth = 0;

    bool hasBorrow() const { return kind != SemaEscapeKind::None; }
    bool isLocalBorrow() const { return kind == SemaEscapeKind::Local && sourceVar != nullptr; }
    bool isMaterializedBorrow() const { return kind == SemaEscapeKind::Materialized; }
    bool isTemporaryBorrow() const { return kind == SemaEscapeKind::Temporary; }
    bool isDeferredCallBorrow() const { return kind == SemaEscapeKind::DeferredCall; }

    void mergeFrom(const SemaEscapeInfo& other)
    {
        if (kind == SemaEscapeKind::Parameter && other.kind == SemaEscapeKind::Parameter)
        {
            parameterOriginsMask |= other.parameterOriginsMask;
            return;
        }

        if (kind == SemaEscapeKind::DeferredCall && other.kind == SemaEscapeKind::DeferredCall)
        {
            for (const auto& call : other.deferredCalls)
            {
                if (std::find(deferredCalls.begin(), deferredCalls.end(), call) == deferredCalls.end())
                    deferredCalls.push_back(call);
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

    TaskContext&                    ctx() { return *(ctx_); }
    const TaskContext&              ctx() const { return *(ctx_); }
    CompilerInstance&               compiler() { return ctx().compiler(); }
    const CompilerInstance&         compiler() const { return ctx().compiler(); }
    const Runtime::BuildCfg&        buildCfg() const { return compiler().buildCfg(); }
    const Runtime::BuildCfgBackend& buildCfgBackend() const { return buildCfg().backend; }
    Runtime::BuildCfgBackendKind    buildCfgBackendKind() const { return buildCfg().backendKind; }
    bool                            isNativeBuild() const { return Runtime::backendKindProducesNativeArtifact(buildCfgBackendKind()); }
    bool                            isNativeExecutableBuild() const { return buildCfgBackendKind() == Runtime::BuildCfgBackendKind::Executable; }
    SymbolFunction*                 currentFunction() { return frame().currentFunction(); }
    const SymbolFunction*           currentFunction() const { return frame().currentFunction(); }
    bool                            isCurrentFunction() const { return currentFunction() != nullptr; }
    bool                            isGlobalScope() const { return !isCurrentFunction(); }
    bool                            isOptimizeEnabled() const { return buildCfgBackend().optimize; }
    bool                            isConstExprRequired() const { return frame().hasContextFlag(SemaFrameContextFlagsE::RequireConstExpr); }
    bool                            isRunExprContext() const { return frame().hasContextFlag(SemaFrameContextFlagsE::RunExpr); }
    bool                            isCompilerEvalContext() const { return frame().hasContextFlag(SemaFrameContextFlagsE::CompilerEval); }
    bool                            isDeclPass() const { return declPass_; }
    bool                            enteringState() const { return visit_.enteringState(); }

    ConstantManager&                               cstMgr();
    const ConstantManager&                         cstMgr() const;
    TypeManager&                                   typeMgr();
    const TypeManager&                             typeMgr() const;
    TypeGen&                                       typeGen();
    const TypeGen&                                 typeGen() const;
    IdentifierManager&                             idMgr();
    const IdentifierManager&                       idMgr() const;
    SourceView&                                    srcView(SourceViewRef srcViewRef);
    const SourceView&                              srcView(SourceViewRef srcViewRef) const;
    NodePayload&                                   currentNodePayloadContext() { return nodePayloadContext(); }
    const NodePayload&                             currentNodePayloadContext() const { return nodePayloadContext(); }
    const SourceFile*                              ownerSourceFile(SourceViewRef srcViewRef) const;
    NodePayload*                                   owningNodePayloadContext(SourceViewRef srcViewRef) const;
    AstNodeRef                                     ownerDeclNodeRef(SourceViewRef srcViewRef, const AstNode* decl, AstNodeRef declRef = AstNodeRef::invalid()) const;
    Sema*                                          tryCreateDeclSema(std::unique_ptr<Sema>& outOwnedSema, SourceViewRef srcViewRef, const AstNode* decl, AstNodeRef declRef = AstNodeRef::invalid());
    bool                                           usesOwningNodePayloadContext(SourceViewRef srcViewRef) const;
    Ast&                                           ast();
    const Ast&                                     ast() const;
    AstNode&                                       node(AstNodeRef nodeRef) { return ast().node(nodeRef); }
    const AstNode&                                 node(AstNodeRef nodeRef) const { return ast().node(nodeRef); }
    const Token&                                   token(const SourceCodeRef& codeRef) const { return srcView(codeRef.srcViewRef).token(codeRef.tokRef); }
    SourceCodeRange                                tokenCodeRange(const SourceCodeRef& codeRef) const { return srcView(codeRef.srcViewRef).tokenCodeRange(ctx(), codeRef.tokRef); }
    std::string_view                               tokenString(const SourceCodeRef& codeRef) const { return srcView(codeRef.srcViewRef).tokenString(codeRef.tokRef); }
    Utf8                                           fileName() const;
    const SourceFile*                              file() const;
    std::vector<ActiveCompilerAstExpansion>&       compilerAstExpansions() { return compilerAstExpansions_; }
    const std::vector<ActiveCompilerAstExpansion>& compilerAstExpansions() const { return compilerAstExpansions_; }

    SemaFrame&                 frame() { return frames_.back(); }
    const SemaFrame&           frame() const { return frames_.back(); }
    std::span<const SemaFrame> frames() const { return frames_; }
    void                       addNullNarrowKillAllFrames(std::span<const Symbol* const> path);
    SemaScope*                 curScopePtr() { return curScope_; }
    const SemaScope*           curScopePtr() const { return curScope_; }
    SemaScope&                 curScope() { return *(curScope_); }
    const SemaScope&           curScope() const { return *(curScope_); }
    SemaScope*                 lookupScope();
    const SemaScope*           lookupScope() const;
    SemaScope*                 upLookupScope() { return frame().upLookupScope(); }
    const SemaScope*           upLookupScope() const { return frame().upLookupScope(); }
    SemaScope*                 resolvedUpLookupScope();
    const SemaScope*           resolvedUpLookupScope() const;
    static void                configureLookupFrame(SemaFrame& frame, SemaScope* lookupScope, bool ignoreRuntimeAccess = false);
    void                       restartCurrentNode(AstNodeRef nodeRef);
    void                       rebindTaskContext(TaskContext& ctx) { ctx_ = &ctx; }

    AstVisit&        visit() { return visit_; }
    const AstVisit&  visit() const { return visit_; }
    AstNodeRef       curNodeRef() const { return visit_.currentNodeRef(); }
    AstNode&         curNode() { return node(curNodeRef()); }
    const AstNode&   curNode() const { return node(curNodeRef()); }
    SymbolMap*       curSymMap() { return curScope_->symMap(); }
    const SymbolMap* curSymMap() const { return curScope_->symMap(); }
    const SymbolMap* topSymMap() const { return startSymMap_; }

    const SymbolNamespace& moduleNamespace() const { return nodePayloadContext().moduleNamespace(); }
    SymbolNamespace&       moduleNamespace() { return nodePayloadContext().moduleNamespace(); }
    void                   setModuleNamespace(SymbolNamespace& ns) { nodePayloadContext().setModuleNamespace(ns); }
    const SymbolNamespace& fileNamespace() const { return nodePayloadContext().fileNamespace(); }
    SymbolNamespace&       fileNamespace() { return nodePayloadContext().fileNamespace(); }
    void                   setFileNamespace(SymbolNamespace& ns) { nodePayloadContext().setFileNamespace(ns); }

    SemaNodeView view(AstNodeRef nodeRef);
    SemaNodeView view(AstNodeRef nodeRef, EnumFlags<SemaNodeViewPartE> part);
    SemaNodeView viewStored(AstNodeRef nodeRef) { return viewStored(nodeRef, SemaNodeViewPartE::All); }
    SemaNodeView viewStored(AstNodeRef nodeRef, EnumFlags<SemaNodeViewPartE> part);
    SemaNodeView viewZero(AstNodeRef nodeRef) { return view(nodeRef, SemaNodeViewPartE::Zero); }
    SemaNodeView viewNode(AstNodeRef nodeRef) { return view(nodeRef, SemaNodeViewPartE::Node); }
    SemaNodeView viewType(AstNodeRef nodeRef) { return view(nodeRef, SemaNodeViewPartE::Type); }
    SemaNodeView viewConstant(AstNodeRef nodeRef) { return view(nodeRef, SemaNodeViewPartE::Constant); }
    SemaNodeView viewSymbol(AstNodeRef nodeRef) { return view(nodeRef, SemaNodeViewPartE::Symbol); }
    SemaNodeView viewSymbolList(AstNodeRef nodeRef) { return view(nodeRef, SemaNodeViewPartE::Symbol); }
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
    SemaNodeView curViewSymbolList() { return curView(SemaNodeViewPartE::Symbol); }
    SemaNodeView curViewTypeConstant() { return curView(SemaNodeViewPartE::Type | SemaNodeViewPartE::Constant); }
    SemaNodeView curViewTypeSymbol() { return curView(SemaNodeViewPartE::Type | SemaNodeViewPartE::Symbol); }
    SemaNodeView curViewNodeType() { return curView(SemaNodeViewPartE::Node | SemaNodeViewPartE::Type); }
    SemaNodeView curViewNodeTypeConstant() { return curView(SemaNodeViewPartE::Node | SemaNodeViewPartE::Type | SemaNodeViewPartE::Constant); }
    SemaNodeView curViewNodeTypeSymbol() { return curView(SemaNodeViewPartE::Node | SemaNodeViewPartE::Type | SemaNodeViewPartE::Symbol); }
    SemaNodeView curViewNodeTypeConstantSymbol() { return curView(SemaNodeViewPartE::Node | SemaNodeViewPartE::Type | SemaNodeViewPartE::Constant | SemaNodeViewPartE::Symbol); }

    void setType(AstNodeRef n, TypeRef ref) { nodePayloadContext().setType(n, ref); }
    void setConstant(AstNodeRef n, ConstantRef ref) { nodePayloadContext().setConstant(n, ref); }
    void setSymbol(AstNodeRef n, Symbol* symbol) { nodePayloadContext().setSymbol(n, symbol); }
    void setSymbol(AstNodeRef n, const Symbol* symbol) { nodePayloadContext().setSymbol(n, symbol); }
    bool hasSubstitute(AstNodeRef n) const { return nodePayloadContext().hasSubstitute(n); }
    void setSubstitute(AstNodeRef n, AstNodeRef substNodeRef) { nodePayloadContext().setSubstitute(n, substNodeRef); }
    void setSymbolList(AstNodeRef n, std::span<const Symbol*> symbols) { nodePayloadContext().setSymbolList(n, symbols); }
    void setSymbolList(AstNodeRef n, std::span<Symbol*> symbols) { nodePayloadContext().setSymbolList(n, symbols); }

    void enableLocalLoweringPayloads() { localLoweringPayloads_ = std::make_unique<std::unordered_map<AstNodeRef, void*>>(); }
    bool usesLocalLoweringPayloads() const { return localLoweringPayloads_ != nullptr; }
    bool hasLoweringPayload(AstNodeRef n) const
    {
        if (localLoweringPayloads_ && localLoweringPayloads_->contains(n))
            return true;
        return nodePayloadContext().hasLoweringPayload(n);
    }

    void setLoweringPayload(AstNodeRef n, void* payload)
    {
        if (localLoweringPayloads_)
        {
            (*localLoweringPayloads_)[n] = payload;
            return;
        }

        nodePayloadContext().setLoweringPayload(n, payload);
    }

    template<typename T>
    T* loweringPayload(AstNodeRef n) const
    {
        if (localLoweringPayloads_)
        {
            const auto it = localLoweringPayloads_->find(n);
            if (it != localLoweringPayloads_->end())
                return static_cast<T*>(it->second);
        }

        return static_cast<T*>(nodePayloadContext().getLoweringPayload(n));
    }

    template<typename T>
    T* mutableLoweringPayload(AstNodeRef n)
    {
        if (!localLoweringPayloads_)
            return static_cast<T*>(nodePayloadContext().getLoweringPayload(n));

        const auto it = localLoweringPayloads_->find(n);
        if (it != localLoweringPayloads_->end())
            return static_cast<T*>(it->second);

        void* inherited = nodePayloadContext().getLoweringPayload(n);
        if (!inherited)
            return nullptr;

        auto* payload                = compiler().allocate<T>();
        *payload                     = *static_cast<T*>(inherited);
        (*localLoweringPayloads_)[n] = payload;
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

    void setResolvedCallArguments(AstNodeRef n, std::span<const ResolvedCallArgument> args) { nodePayloadContext().setResolvedCallArguments(n, args); }
    void appendResolvedCallArguments(AstNodeRef n, SmallVector<ResolvedCallArgument>& out) const { nodePayloadContext().appendResolvedCallArguments(n, out); }
    void markImplicitCodeBlockArg(AstNodeRef parentRef, AstNodeRef childRef);
    bool isImplicitCodeBlockArg(AstNodeRef parentRef, AstNodeRef childRef) const;

    const SemaEscapeInfo* variableEscapeInfo(const SymbolVariable& symVar) const;
    void                  setVariableEscapeInfo(const SymbolVariable& symVar, const SemaEscapeInfo& info);
    void                  clearVariableEscapeInfo(const SymbolVariable& symVar);
    SemaEscapeInfo        variableEscapeInfoIncludingProjections(const SymbolVariable& symVar) const;
    SemaEscapeInfo        projectionEscapeInfoIncludingWildcards(const SemaEscapeProjection& projection) const;
    void                  setProjectionEscapeInfo(const SemaEscapeProjection& projection, const SemaEscapeInfo& info);
    void                  clearProjectionEscapeInfo(const SemaEscapeProjection& projection);

    // Lexical depth of the scope a local variable is declared in (0 = unknown).
    uint32_t variableScopeDepth(const SymbolVariable& symVar) const;
    void     setVariableScopeDepth(const SymbolVariable& symVar, uint32_t depth);
    uint32_t currentScopeDepth() const;

    // Flow joins for the borrow-escape state: a branch alternative starts from the entry
    // state, and alternatives UNION at the merge point (may-borrow), so a borrow cleared
    // in only one path survives the join.
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
    bool isConstAssignBinding(const AstNode& node) const { return NodePayload::hasPayloadFlags(node, NodePayloadFlags::ConstAssignBinding); }
    bool isConstAssignBinding(AstNodeRef ref) const { return NodePayload::hasPayloadFlags(node(resolvedNodeRef(ref)), NodePayloadFlags::ConstAssignBinding); }
    bool isConstAssignBindingStored(AstNodeRef ref) const;
    void setConstAssignBinding(AstNode& node) { NodePayload::addPayloadFlags(node, NodePayloadFlags::ConstAssignBinding); }
    void setConstAssignBinding(AstNodeRef ref) { NodePayload::addPayloadFlags(node(ref), NodePayloadFlags::ConstAssignBinding); }
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

    void       pushFramePopOnPostChild(const SemaFrame& frame, AstNodeRef popAfterChildRef);
    void       pushFramePopOnPostNode(const SemaFrame& frame, AstNodeRef popNodeRef = AstNodeRef::invalid());
    SemaScope* pushScopePopOnPostChild(SemaScopeFlags flags, AstNodeRef popAfterChildRef);
    SemaScope* pushScopePopOnPostNode(SemaScopeFlags flags, AstNodeRef popNodeRef = AstNodeRef::invalid());
    void       deferPostNodeAction(AstNodeRef nodeRef, std::function<Result(Sema&, AstNodeRef)> callback);
    void       processCurrentPostNodePopsNow();

    Result      waitIdentifier(IdentifierRef idRef, const SourceCodeRef& codeRef);
    Result      waitPredefined(IdentifierManager::PredefinedName name, TypeRef& typeRef, const SourceCodeRef& codeRef);
    Result      waitRuntimeFunction(IdentifierManager::RuntimeFunctionKind kind, SymbolFunction*& symbol, const SourceCodeRef& codeRef);
    Result      waitCompilerDefined(IdentifierRef idRef, const SourceCodeRef& codeRef);
    Result      waitImplRegistrations(IdentifierRef idRef, const SourceCodeRef& codeRef);
    Result      completeLazyGenericFunction(SymbolFunction& calledFn);
    Result      waitSemaCompletedNoLazy(const Symbol* symbol, const SourceCodeRef& codeRef);
    Result      waitSemaCompleted(const Symbol* symbol, const SourceCodeRef& codeRef);
    Result      waitCodeGenPreSolved(const Symbol* symbol, const SourceCodeRef& codeRef);
    Result      waitCodeGenCompleted(const Symbol* symbol, const SourceCodeRef& codeRef);
    Result      waitDeclared(const Symbol* symbol, const SourceCodeRef& codeRef);
    Result      waitTyped(const Symbol* symbol, const SourceCodeRef& codeRef);
    Result      waitSemaCompleted(const TypeInfo* type, AstNodeRef nodeRef);
    Result      waitTypeInfoGeneration(AstNodeRef nodeRef, const SourceCodeRef& codeRef = SourceCodeRef::invalid());
    Result      makeRuntimeTypeInfo(ConstantRef& outRef, TypeRef typeRef, AstNodeRef ownerNodeRef);
    Result      prepareFunctionSignature(AstNodeRef functionRef);
    static void waitDone(TaskContext& ctx, JobClientId clientId);

private:
    friend struct SemaNodeView;
    friend void SemaGeneric::prepareGenericInstantiationContext(Sema& sema, SymbolMap* startSymMap, const SymbolImpl* impl, const SymbolInterface* itf, const AttributeList& attrs);

    bool                         hasActiveLookupScopeOverride() const;
    AstNodeRef                   resolvedNodeRef(AstNodeRef n) const { return nodePayloadContext().getSubstituteRef(n); }
    TypeRef                      typeRefOf(AstNodeRef n) const { return nodePayloadContext().getTypeRef(ctx(), resolvedNodeRef(n)); }
    ConstantRef                  constantRefOf(AstNodeRef n) const { return nodePayloadContext().getConstantRef(ctx(), resolvedNodeRef(n)); }
    TypeRef                      typeRefOfStored(AstNodeRef n) const { return nodePayloadContext().getTypeRef(ctx(), n); }
    ConstantRef                  constantRefOfStored(AstNodeRef n) const { return nodePayloadContext().getConstantRef(ctx(), n); }
    const ConstantValue&         constantOf(AstNodeRef n) const { return nodePayloadContext().getConstant(ctx(), resolvedNodeRef(n)); }
    const Symbol&                symbolOf(AstNodeRef n) const { return nodePayloadContext().getSymbol(ctx(), resolvedNodeRef(n)); }
    Symbol&                      symbolOf(AstNodeRef n) { return nodePayloadContext().getSymbol(ctx(), resolvedNodeRef(n)); }
    const Symbol&                symbolOfStored(AstNodeRef n) const { return nodePayloadContext().getSymbol(ctx(), n); }
    Symbol&                      symbolOfStored(AstNodeRef n) { return nodePayloadContext().getSymbol(ctx(), n); }
    bool                         hasType(AstNodeRef n) const { return nodePayloadContext().hasType(ctx(), resolvedNodeRef(n)); }
    bool                         hasConstant(AstNodeRef n) const { return nodePayloadContext().hasConstant(ctx(), resolvedNodeRef(n)); }
    bool                         hasSymbol(AstNodeRef n) const { return nodePayloadContext().hasSymbol(resolvedNodeRef(n)); }
    bool                         hasSymbolStored(AstNodeRef n) const { return nodePayloadContext().hasSymbol(n); }
    AstNodeRef                   getSubstituteRef(AstNodeRef n) const { return resolvedNodeRef(n); }
    bool                         hasSymbolList(AstNodeRef n) const { return nodePayloadContext().hasSymbolList(resolvedNodeRef(n)); }
    std::span<const Symbol*>     getSymbolList(AstNodeRef n) const { return nodePayloadContext().getSymbolList(resolvedNodeRef(n)); }
    std::span<Symbol*>           getSymbolList(AstNodeRef n) { return nodePayloadContext().getSymbolList(resolvedNodeRef(n)); }
    bool                         hasSymbolListStored(AstNodeRef n) const { return nodePayloadContext().hasSymbolList(n); }
    std::span<const Symbol*>     getSymbolListStored(AstNodeRef n) const { return nodePayloadContext().getSymbolList(n); }
    std::span<Symbol*>           getSymbolListStored(AstNodeRef n) { return nodePayloadContext().getSymbolList(n); }
    bool                         hasSymbolRaw(AstNodeRef n) const { return nodePayloadContext().hasSymbol(n); }
    const Symbol&                symbolOfRaw(AstNodeRef n) const { return nodePayloadContext().getSymbol(ctx(), n); }
    Symbol&                      symbolOfRaw(AstNodeRef n) { return nodePayloadContext().getSymbol(ctx(), n); }
    bool                         hasSymbolListRaw(AstNodeRef n) const { return nodePayloadContext().hasSymbolList(n); }
    std::span<Symbol*>           getSymbolListRaw(AstNodeRef n) { return nodePayloadContext().getSymbolList(n); }
    NodePayload::ResolvedSymbols resolveSymbols(AstNodeRef n) const { return nodePayloadContext().resolveSymbols(resolvedNodeRef(n)); }
    NodePayload::ResolvedSymbols resolveSymbolsStored(AstNodeRef n) const { return nodePayloadContext().resolveSymbols(n); }

    SemaScope*         pushScope(SemaScopeFlags flags);
    void               popScope();
    void               pushFrame(const SemaFrame& frame);
    void               popFrame();
    NodePayload&       nodePayloadContext() { return *(nodePayloadContext_); }
    const NodePayload& nodePayloadContext() const { return *(nodePayloadContext_); }
    static void        inheritMissingNamespaces(TaskContext& ctx, NodePayload& payloadContext);
    static SymbolMap*  topLevelStartSymMap(TaskContext& ctx, NodePayload& payloadContext);
    static SymbolMap*  childStartSymMap(Sema& parent, NodePayload& payloadContext);

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

    struct DeferredTopLevelItem
    {
        AstNodeRef               nodeRef;
        DeferredTopLevelItemKind kind;
    };

    Result runCurrentVisit();
    Result processDeferredTopLevelItems();
    Result processDeferredTopLevelNode(AstNodeRef nodeRef, uint32_t insertIndex);
    Result processPendingTopLevelCompilerRuns(uint32_t insertIndex);
    void   deferTopLevelItem(AstNodeRef nodeRef, DeferredTopLevelItemKind kind);
    void   enqueueTopLevelSemaJob(AstNodeRef nodeRef);

    void   processDeferredPopsPostChild(AstNodeRef nodeRef, AstNodeRef childRef);
    void   processDeferredPopsPostNode(AstNodeRef nodeRef);
    Result processDeferredPostNodeActions(AstNodeRef nodeRef);

    TaskContext*                                           ctx_                = nullptr;
    NodePayload*                                           nodePayloadContext_ = nullptr;
    std::unique_ptr<std::unordered_map<AstNodeRef, void*>> localLoweringPayloads_;
    struct EscapeBranchState
    {
        std::unordered_map<const SymbolVariable*, SemaEscapeInfo>                          entryState;
        std::unordered_map<const SymbolVariable*, SemaEscapeInfo>                          mergedState;
        std::unordered_map<SemaEscapeProjection, SemaEscapeInfo, SemaEscapeProjectionHash> entryProjectionState;
        std::unordered_map<SemaEscapeProjection, SemaEscapeInfo, SemaEscapeProjectionHash> mergedProjectionState;
    };

    std::unordered_map<const SymbolVariable*, SemaEscapeInfo>                          variableEscapeInfos_;
    std::unordered_map<SemaEscapeProjection, SemaEscapeInfo, SemaEscapeProjectionHash> projectionEscapeInfos_;
    std::unordered_map<const SymbolVariable*, uint32_t>                                variableScopeDepths_;
    std::vector<EscapeBranchState>                                                     escapeBranchStack_;
    AstVisit                                                                           visit_;

    std::vector<std::unique_ptr<SemaScope>> scopes_;
    SymbolMap*                              startSymMap_   = nullptr;
    SemaScope*                              curScope_      = nullptr;
    bool                                    declPass_      = false;
    bool                                    rootVisitDone_ = false;

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

    struct DeferredPostNodeAction
    {
        AstNodeRef                               nodeRef;
        std::function<Result(Sema&, AstNodeRef)> callback;
    };
    std::vector<DeferredPostNodeAction>     deferredPostNodeActions_;
    std::vector<ActiveCompilerAstExpansion> compilerAstExpansions_;
    std::vector<DeferredTopLevelItem>       deferredTopLevelItems_;
    std::vector<AstNodeRef>                 pendingTopLevelCompilerRunRefs_;
    uint32_t                                deferredTopLevelItemIndex_       = 0;
    uint32_t                                deferredTopLevelItemInsertIndex_ = 0;
    uint32_t                                pendingTopLevelCompilerRunIndex_ = 0;
    bool                                    deferTopLevelItems_              = false;
    bool                                    deferredTopLevelItemRunning_     = false;
};

SWC_END_NAMESPACE();
