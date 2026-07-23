#include "pch.h"
#include "Compiler/Sema/Core/Sema.h"
#include "Backend/JIT/JITExecManager.h"
#include "Compiler/Sema/Constant/ConstantManager.h"
#include "Compiler/Sema/Core/NodePayload.h"
#include "Compiler/Sema/Core/SemaJob.h"
#include "Compiler/Sema/Core/SemaNodeView.h"
#include "Compiler/Sema/Core/SemaScope.h"
#include "Compiler/Sema/Helpers/SemaCycle.h"
#include "Compiler/Sema/Helpers/SemaError.h"
#include "Compiler/Sema/Helpers/SemaEscape.h"
#include "Compiler/Sema/Helpers/SemaRuntime.h"
#include "Compiler/Sema/Symbol/Symbol.Impl.h"
#include "Compiler/Sema/Symbol/Symbols.h"
#include "Compiler/Verify.h"
#include "Main/Command/CommandLine.h"
#include "Main/CompilerInstance.h"
#include "Main/Global.h"
#include "Support/Memory/Heap.h"
#include "Support/Report/Assert.h"
#include "Support/Thread/JobManager.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    bool waitHasErrorOnLine(Sema& sema, const SourceCodeRef& waitCodeRef)
    {
        if (!waitCodeRef.isValid())
            return false;

        // Wait states are resumed later, possibly after another branch has already
        // reported an error on the same source line. In that case retrying the wait
        // only produces secondary noise, so abort the resumed node early.
        const SourceView&     srcView    = sema.srcView(waitCodeRef.srcViewRef);
        const SourceFile*     waitFile   = srcView.file();
        const SourceFile*     ownerFile  = sema.ownerSourceFile(waitCodeRef.srcViewRef);
        const SourceCodeRange tokenRange = sema.tokenCodeRange(waitCodeRef);
        return (waitFile && waitFile->hasErrorLineInRange(tokenRange.line, tokenRange.line)) ||
               (ownerFile && ownerFile->hasErrorLineInRange(tokenRange.line, tokenRange.line));
    }

    const Symbol* findPredefinedRuntimeSymbol(const Sema& sema, IdentifierManager::PredefinedName name)
    {
        const IdentifierRef        swagIdRef   = sema.idMgr().predefined(IdentifierManager::PredefinedName::Swag);
        const IdentifierRef        targetIdRef = sema.idMgr().predefined(name);
        std::vector<const Symbol*> moduleSymbols;
        sema.moduleNamespace().getAllSymbols(moduleSymbols);
        for (const Symbol* moduleSym : moduleSymbols)
        {
            if (!moduleSym || !moduleSym->isNamespace() || moduleSym->idRef() != swagIdRef)
                continue;

            std::vector<const Symbol*> namespaceSymbols;
            moduleSym->asSymMap()->getAllSymbols(namespaceSymbols);
            for (const Symbol* candidate : namespaceSymbols)
            {
                if (candidate && candidate->idRef() == targetIdRef)
                    return candidate;
            }
        }

        return nullptr;
    }

    SemaScope* remapScopeFromParent(const std::vector<std::unique_ptr<SemaScope>>& parentScopes, const std::vector<std::unique_ptr<SemaScope>>& childScopes, const SemaScope* oldScope)
    {
        if (!oldScope)
            return nullptr;

        for (size_t i = 0; i < parentScopes.size(); ++i)
        {
            if (parentScopes[i].get() == oldScope)
                return childScopes[i].get();
        }

        return nullptr;
    }

    void cleanupPendingImplRegistrations(Sema& sema, AstNodeRef nodeRef)
    {
        if (nodeRef.isInvalid())
            return;

        AstNode& node = sema.node(nodeRef);
        if (node.is(AstNodeId::Impl))
        {
            const SemaNodeView view = sema.viewSymbol(nodeRef);
            if (view.hasSymbol())
            {
                auto* sym = view.sym();
                if (sym != nullptr && sym->isImpl())
                {
                    auto& symImpl = sym->cast<SymbolImpl>();
                    if (!symImpl.isPendingRegistrationResolved())
                    {
                        const AstNodeIdInfo& info = Ast::nodeIdInfos(node.id());
                        info.semaErrorCleanup(sema, node, nodeRef);

                        if (!symImpl.isSemaCompleted())
                            symImpl.setIgnored(sema.ctx());
                    }
                }
            }
        }

        SmallVector<AstNodeRef> children;
        node.collectChildrenFromAst(children, sema.ast());
        for (const AstNodeRef childRef : children)
            cleanupPendingImplRegistrations(sema, childRef);
    }

    bool isCompilerRunFunction(const Sema& sema, const AstNode& node)
    {
        if (node.isNot(AstNodeId::CompilerFunc))
            return false;

        return sema.token(node.codeRef()).id == TokenId::CompilerRun;
    }

    bool isCompilerAstFunction(const Sema& sema, const AstNode& node)
    {
        if (node.isNot(AstNodeId::CompilerFunc) && node.isNot(AstNodeId::CompilerShortFunc))
            return false;

        return sema.token(node.codeRef()).id == TokenId::CompilerAst;
    }

}

SymbolMap* Sema::childStartSymMap(Sema& parent, NodePayload& payloadContext)
{
    inheritMissingNamespaces(parent.ctx(), payloadContext);

    // A child sema can analyze nodes stored in another payload context (for example a
    // declaration from another source view). In that case the module namespace is the
    // only stable root; the parent's current scope belongs to a different AST walk.
    if (&payloadContext != parent.nodePayloadContext_)
    {
        if (!payloadContext.moduleNamespace_)
            payloadContext.moduleNamespace_ = parent.nodePayloadContext_->moduleNamespace_;
        return &payloadContext.moduleNamespace();
    }

    if (!parent.curScope_)
        return parent.startSymMap_;

    if (parent.curScope_->isTopLevel())
        return SemaFrame::currentSymMap(parent);

    return parent.curScope_->symMap();
}

void Sema::inheritMissingNamespaces(TaskContext& ctx, NodePayload& payloadContext)
{
    if (payloadContext.moduleNamespace_ && payloadContext.fileNamespace_)
        return;

    // Generated or imported payloads may be created before their namespace pointers are
    // filled. Rehydrate them from the owning source file so later symbol registration
    // does not accidentally fall back to the caller's namespace.
    if (!payloadContext.ast_.hasSourceView())
        return;

    const SourceFile* ownerSourceFile = ctx.compiler().owningSourceFile(payloadContext.ast_.srcView());
    if (!ownerSourceFile)
        return;

    const NodePayload& ownerPayload = ownerSourceFile->nodePayloadContext();
    if (!payloadContext.moduleNamespace_ && ownerPayload.moduleNamespace_)
        payloadContext.moduleNamespace_ = ownerPayload.moduleNamespace_;
    if (!payloadContext.fileNamespace_ && ownerPayload.fileNamespace_)
        payloadContext.fileNamespace_ = ownerPayload.fileNamespace_;
}

SymbolMap* Sema::topLevelStartSymMap(TaskContext& ctx, NodePayload& payloadContext)
{
    inheritMissingNamespaces(ctx, payloadContext);
    SWC_ASSERT(payloadContext.moduleNamespace_ != nullptr);
    return payloadContext.moduleNamespace_->ownerSymMap();
}

Sema::Sema(TaskContext& ctx, NodePayload& payloadContext, bool declPass) :
    ctx_(&ctx),
    nodePayloadContext_(&payloadContext),
    startSymMap_(topLevelStartSymMap(ctx, payloadContext)),
    declPass_(declPass)
{
    visit_.start(nodePayloadContext_->ast(), nodePayloadContext_->ast().root());
    setVisitors();
    pushFrame({});
}

Sema::Sema(TaskContext& ctx, NodePayload& payloadContext, AstNodeRef root, bool declPass) :
    ctx_(&ctx),
    nodePayloadContext_(&payloadContext),
    startSymMap_(topLevelStartSymMap(ctx, payloadContext)),
    declPass_(declPass)
{
    visit_.start(nodePayloadContext_->ast(), root);
    setVisitors();
    pushFrame({});
}

Sema::Sema(TaskContext& ctx, Sema& parent, AstNodeRef root) :
    Sema(ctx, parent, root, false)
{
}

Sema::Sema(TaskContext& ctx, Sema& parent, AstNodeRef root, bool declPass) :
    Sema(ctx, parent, *parent.nodePayloadContext_, root, declPass)
{
}

Sema::Sema(TaskContext& ctx, Sema& parent, NodePayload& payloadContext, AstNodeRef root) :
    Sema(ctx, parent, payloadContext, root, false)
{
}

Sema::Sema(TaskContext& ctx, Sema& parent, NodePayload& payloadContext, AstNodeRef root, bool declPass) :
    ctx_(&ctx),
    nodePayloadContext_(&payloadContext),
    startSymMap_(childStartSymMap(parent, payloadContext)),
    declPass_(declPass)
{
    visit_.start(nodePayloadContext_->ast(), root);
    pushFrame(parent.frame());
    // Ancestor-derived contexts are rooted in the active visit subtree. A child sema
    // starts a fresh walk from `root`, so inheriting those markers would leak state
    // outside the original AST branch.
    frame().removeContextFlag(SemaFrameContextFlagsE::CompilerEval);
    frame().removeContextFlag(SemaFrameContextFlagsE::GeneratedTopLevel);
    frame().setSyntaxScopeNodeRef(AstNodeRef::invalid());
    frame().setCurrentNamedCompilerScope(nullptr);
    frame().setCurrentInlinePayload(nullptr);
    frame().setInlineContextRootRef(AstNodeRef::invalid());
    setVisitors();
    compilerAstExpansions_ = parent.compilerAstExpansions_;

    for (const auto& scope : parent.scopes_)
    {
        scopes_.emplace_back(std::make_unique<SemaScope>(*scope));
        if (scopes_.size() > 1)
            scopes_.back()->setParent(scopes_[scopes_.size() - 2].get());
        else
            scopes_.back()->setParent(nullptr);
    }

    for (size_t i = 0; i < parent.scopes_.size(); ++i)
        scopes_[i]->setLookupParent(remapScopeFromParent(parent.scopes_, scopes_, parent.scopes_[i]->lookupParent()));

    curScope_ = scopes_.empty() ? nullptr : scopes_.back().get();
    if (curScope_ && curScope_->isTopLevel())
        curScope_->setSymMap(startSymMap_);

    frame().setLookupScope(remapScopeFromParent(parent.scopes_, scopes_, parent.frame().lookupScope()));
    frame().setUpLookupScope(remapScopeFromParent(parent.scopes_, scopes_, parent.frame().upLookupScope()));
    variableEscapeInfos_   = parent.variableEscapeInfos_;
    projectionEscapeInfos_ = parent.projectionEscapeInfos_;
    variableScopeDepths_   = parent.variableScopeDepths_;
    escapeBranchStack_     = parent.escapeBranchStack_;
}

Sema::~Sema() = default;

const SemaEscapeInfo* Sema::variableEscapeInfo(const SymbolVariable& symVar) const
{
    const auto it = variableEscapeInfos_.find(&symVar);
    if (it == variableEscapeInfos_.end())
        return nullptr;
    return &it->second;
}

void Sema::setVariableEscapeInfo(const SymbolVariable& symVar, const SemaEscapeInfo& info)
{
    if (!info.hasBorrow())
    {
        clearVariableEscapeInfo(symVar);
        return;
    }

    std::erase_if(projectionEscapeInfos_, [&symVar](const auto& it) { return it.first.root == &symVar; });
    variableEscapeInfos_[&symVar] = info;
}

void Sema::clearVariableEscapeInfo(const SymbolVariable& symVar)
{
    variableEscapeInfos_.erase(&symVar);
    std::erase_if(projectionEscapeInfos_, [&symVar](const auto& it) { return it.first.root == &symVar; });
}

SemaEscapeInfo Sema::variableEscapeInfoIncludingProjections(const SymbolVariable& symVar) const
{
    SemaEscapeInfo result;
    if (const SemaEscapeInfo* info = variableEscapeInfo(symVar))
        result = *info;

    for (const auto& [projection, info] : projectionEscapeInfos_)
    {
        if (projection.root == &symVar)
            result.mergeFrom(info);
    }
    return result;
}

SemaEscapeInfo Sema::projectionEscapeInfoIncludingWildcards(const SemaEscapeProjection& projection) const
{
    SemaEscapeInfo result;
    for (const auto& [candidate, info] : projectionEscapeInfos_)
    {
        if (candidate.root != projection.root || candidate.components.size() != projection.components.size())
            continue;

        bool matches = true;
        for (size_t i = 0; i < projection.components.size(); ++i)
        {
            const auto& left  = projection.components[i];
            const auto& right = candidate.components[i];
            if (left == right)
                continue;
            if (left.kind == SemaEscapeProjectionKind::AnyIndex && right.kind != SemaEscapeProjectionKind::Field)
                continue;
            if (right.kind == SemaEscapeProjectionKind::AnyIndex && left.kind != SemaEscapeProjectionKind::Field)
                continue;
            matches = false;
            break;
        }

        if (matches)
            result.mergeFrom(info);
    }
    return result;
}

void Sema::setProjectionEscapeInfo(const SemaEscapeProjection& projection, const SemaEscapeInfo& info)
{
    if (!projection.root || projection.components.empty())
        return;
    if (!info.hasBorrow())
    {
        clearProjectionEscapeInfo(projection);
        return;
    }
    projectionEscapeInfos_[projection] = info;
}

void Sema::clearProjectionEscapeInfo(const SemaEscapeProjection& projection)
{
    if (!projection.root)
        return;

    std::erase_if(projectionEscapeInfos_, [&projection](const auto& it) {
        if (it.first.root != projection.root || it.first.components.size() < projection.components.size())
            return false;
        return std::equal(projection.components.begin(), projection.components.end(), it.first.components.begin());
    });
}

uint32_t Sema::variableScopeDepth(const SymbolVariable& symVar) const
{
    const auto it = variableScopeDepths_.find(&symVar);
    return it == variableScopeDepths_.end() ? 0 : it->second;
}

void Sema::setVariableScopeDepth(const SymbolVariable& symVar, uint32_t depth)
{
    if (depth)
        variableScopeDepths_[&symVar] = depth;
}

uint32_t Sema::currentScopeDepth() const
{
    uint32_t depth = 0;
    for (const SemaScope* scope = curScopePtr(); scope; scope = scope->parent())
        depth++;
    return depth;
}


namespace
{
    template<typename K, typename H>
    void mergeEscapeStates(std::unordered_map<K, SemaEscapeInfo, H>& dst, const std::unordered_map<K, SemaEscapeInfo, H>& src)
    {
        for (const auto& [key, info] : src)
        {
            auto [it, inserted] = dst.try_emplace(key, info);
            if (!inserted)
                it->second.mergeFrom(info);
        }
    }
}

void Sema::pushEscapeBranch()
{
    EscapeBranchState state;
    state.entryState           = variableEscapeInfos_;
    state.entryProjectionState = projectionEscapeInfos_;
    escapeBranchStack_.push_back(std::move(state));
}

void Sema::nextEscapeBranchAlternative()
{
    SWC_ASSERT(!escapeBranchStack_.empty());
    if (escapeBranchStack_.empty())
        return;

    // Branch-local borrow state starts from the same entry snapshot for each
    // alternative; every possible parameter, projection and deferred call survives.
    EscapeBranchState& state = escapeBranchStack_.back();
    mergeEscapeStates(state.mergedState, variableEscapeInfos_);
    mergeEscapeStates(state.mergedProjectionState, projectionEscapeInfos_);
    variableEscapeInfos_   = state.entryState;
    projectionEscapeInfos_ = state.entryProjectionState;
}

void Sema::popEscapeBranch(bool mergeEntryState)
{
    SWC_ASSERT(!escapeBranchStack_.empty());
    if (escapeBranchStack_.empty())
        return;

    EscapeBranchState& state = escapeBranchStack_.back();
    mergeEscapeStates(state.mergedState, variableEscapeInfos_);
    mergeEscapeStates(state.mergedProjectionState, projectionEscapeInfos_);
    if (mergeEntryState)
    {
        mergeEscapeStates(state.mergedState, state.entryState);
        mergeEscapeStates(state.mergedProjectionState, state.entryProjectionState);
    }

    variableEscapeInfos_   = std::move(state.mergedState);
    projectionEscapeInfos_ = std::move(state.mergedProjectionState);
    escapeBranchStack_.pop_back();
}

ConstantManager& Sema::cstMgr()
{
    return compiler().cstMgr();
}

const ConstantManager& Sema::cstMgr() const
{
    return compiler().cstMgr();
}

TypeManager& Sema::typeMgr()
{
    return compiler().typeMgr();
}

const TypeManager& Sema::typeMgr() const
{
    return compiler().typeMgr();
}

TypeGen& Sema::typeGen()
{
    return compiler().typeGen();
}

const TypeGen& Sema::typeGen() const
{
    return compiler().typeGen();
}

IdentifierManager& Sema::idMgr()
{
    return compiler().idMgr();
}

const IdentifierManager& Sema::idMgr() const
{
    return compiler().idMgr();
}

SourceView& Sema::srcView(SourceViewRef srcViewRef)
{
    return compiler().srcView(srcViewRef);
}

const SourceView& Sema::srcView(SourceViewRef srcViewRef) const
{
    return compiler().srcView(srcViewRef);
}

const SourceFile* Sema::ownerSourceFile(SourceViewRef srcViewRef) const
{
    return compiler().ownerSourceFile(srcViewRef);
}

NodePayload* Sema::owningNodePayloadContext(SourceViewRef srcViewRef) const
{
    const SourceFile* sourceFile = ownerSourceFile(srcViewRef);
    if (!sourceFile)
        return nullptr;

    return &compiler().file(sourceFile->ref()).nodePayloadContext();
}

SemaInlinePayload* Sema::inlinePayload(const SymbolFunction& function)
{
    const AstNodeRef declRef = function.declNodeRef();
    if (declRef.isInvalid())
        return nullptr;

    const NodePayload* payloadContext = function.declNodePayloadContext();
    if (!payloadContext)
        return nullptr;

    return static_cast<SemaInlinePayload*>(payloadContext->getInlinePayload(declRef));
}

AstNodeRef Sema::ownerDeclNodeRef(SourceViewRef srcViewRef, const AstNode* decl, AstNodeRef declRef) const
{
    if (declRef.isValid() || !decl)
        return declRef;

    const SourceFile* sourceFile = ownerSourceFile(srcViewRef);
    if (!sourceFile)
        return AstNodeRef::invalid();

    return decl->nodeRef(sourceFile->ast());
}

Sema* Sema::tryCreateDeclSema(std::unique_ptr<Sema>& outOwnedSema, SourceViewRef srcViewRef, const AstNode* decl, AstNodeRef declRef)
{
    NodePayload* payloadContext = owningNodePayloadContext(srcViewRef);
    if (!payloadContext || payloadContext == nodePayloadContext_)
        return nullptr;

    declRef = ownerDeclNodeRef(srcViewRef, decl, declRef);
    SWC_ASSERT(declRef.isValid());
    outOwnedSema = std::make_unique<Sema>(ctx(), *this, *payloadContext, declRef);
    return outOwnedSema.get();
}

bool Sema::usesOwningNodePayloadContext(SourceViewRef srcViewRef) const
{
    const NodePayload* payloadContext = owningNodePayloadContext(srcViewRef);
    return payloadContext != nullptr && payloadContext == nodePayloadContext_;
}

Ast& Sema::ast()
{
    return nodePayloadContext_->ast();
}

Utf8 Sema::fileName() const
{
    return ast().srcView().file()->path().string();
}

const SourceFile* Sema::file() const
{
    return ast().srcView().file();
}

SemaScope* Sema::resolvedUpLookupScope()
{
    if (auto* scope = upLookupScope())
        return scope;
    const auto* scope = lookupScope();
    return scope ? scope->lookupParent() : nullptr;
}

const SemaScope* Sema::resolvedUpLookupScope() const
{
    if (const auto* scope = upLookupScope())
        return scope;
    const auto* scope = lookupScope();
    return scope ? scope->lookupParent() : nullptr;
}

void Sema::configureLookupFrame(SemaFrame& frame, SemaScope* lookupScope, bool ignoreRuntimeAccess)
{
    frame.setLookupScope(lookupScope);
    frame.setLookupScopeOverrideNodes(nullptr);
    frame.setUpLookupScope(lookupScope ? lookupScope->lookupParent() : nullptr);
    frame.setIgnoreRuntimeAccess(ignoreRuntimeAccess);
    frame.setIgnoreRedirectedLookupSymMaps(false);
}

bool Sema::hasActiveLookupScopeOverride() const
{
    const SemaScope* scope = frame().lookupScope();
    if (!scope)
        return false;

    const auto* overrideNodes = frame().lookupScopeOverrideNodes();
    if (!overrideNodes)
        return true;
    if (overrideNodes->ast != &ast())
        return false;
    return overrideNodes->nodeRefs.contains(curNodeRef());
}

SemaScope* Sema::lookupScope()
{
    return hasActiveLookupScopeOverride() ? frame().lookupScope() : curScope_;
}

const SemaScope* Sema::lookupScope() const
{
    return hasActiveLookupScopeOverride() ? frame().lookupScope() : curScope_;
}

void Sema::restartCurrentNode(AstNodeRef nodeRef)
{
    SWC_ASSERT(nodeRef.isValid());

    const AstNodeRef previousRef = curNodeRef();
    if (previousRef != nodeRef)
    {
        for (auto& entry : deferredPopFrames_)
        {
            if (entry.onPostNode && entry.nodeRef == previousRef)
                entry.nodeRef = nodeRef;
        }

        for (auto& entry : deferredPopScopes_)
        {
            if (entry.onPostNode && entry.nodeRef == previousRef)
                entry.nodeRef = nodeRef;
        }

        for (auto& action : deferredPostNodeActions_)
        {
            if (action.nodeRef == previousRef)
                action.nodeRef = nodeRef;
        }
    }

    visit_.restartCurrentNode(nodeRef);
}

const Ast& Sema::ast() const
{
    return nodePayloadContext_->ast();
}

SemaNodeView Sema::view(AstNodeRef nodeRef)
{
    return view(nodeRef, SemaNodeViewPartE::All);
}

SemaNodeView Sema::view(AstNodeRef nodeRef, EnumFlags<SemaNodeViewPartE> part)
{
    return {*this, nodeRef, part};
}

SemaNodeView Sema::viewStored(AstNodeRef nodeRef, EnumFlags<SemaNodeViewPartE> part)
{
    return {*this, nodeRef, part, SemaNodeViewResolveE::Stored};
}

SemaNodeView Sema::curView()
{
    return curView(SemaNodeViewPartE::All);
}

SemaNodeView Sema::curView(EnumFlags<SemaNodeViewPartE> part)
{
    return view(curNodeRef(), part);
}

SemaScope* Sema::pushScope(SemaScopeFlags flags)
{
    SemaScope* parent = curScope_;
    scopes_.emplace_back(std::make_unique<SemaScope>(flags, parent));
    SemaScope* scope = scopes_.back().get();
    scope->setSymMap(parent->symMap());
    curScope_ = scope;

    if (const SemaScope* lookupScope = frame().lookupScope())
    {
        for (const SemaScope* it = parent; it; it = it->parent())
        {
            if (it != lookupScope)
                continue;

            frame().setLookupScope(scope);
            break;
        }
    }

    return scope;
}

void Sema::popScope()
{
    SWC_ASSERT(curScope_);
    if (frame().lookupScope() == curScope_)
        frame().setLookupScope(curScope_->lookupParent());
    curScope_ = curScope_->parent();
    scopes_.pop_back();
}

void Sema::pushFrame(const SemaFrame& frame)
{
    frames_.push_back(frame);
}

void Sema::addNullNarrowKillAllFrames(std::span<const Symbol* const> path)
{
    // A narrowing kill must survive the pop of every enclosing region that had proven the
    // path non-null, so it is recorded in every live frame.
    for (auto& frame : frames_)
        frame.addNullNarrowFact(path, false);
}

void Sema::popFrame()
{
    SWC_ASSERT(!frames_.empty());
    frames_.pop_back();
}

void Sema::markImplicitCodeBlockArg(AstNodeRef parentRef, AstNodeRef childRef)
{
    SWC_UNUSED(parentRef);
    if (!childRef.isValid())
        return;
    AstNodeRef blockRef = childRef;
    if (node(blockRef).is(AstNodeId::CompilerCodeBlock))
        blockRef = node(blockRef).cast<AstCompilerCodeBlock>().nodeBodyRef;
    if (blockRef.isValid() && node(blockRef).is(AstNodeId::EmbeddedBlock))
        node(blockRef).cast<AstEmbeddedBlock>().addFlag(AstEmbeddedBlockFlagsE::ImplicitCodeBlockArg);
}

bool Sema::isImplicitCodeBlockArg(AstNodeRef parentRef, AstNodeRef childRef) const
{
    if (childRef.isInvalid())
        return false;

    AstNodeRef blockRef = childRef;
    if (node(blockRef).is(AstNodeId::CompilerCodeBlock))
    {
        // A trailing code literal ('call(args) #code(a, b) { ... }') is consumed as a
        // call argument: skip it in statement position only, so its visit as an
        // argument still happens normally.
        if (parentRef.isInvalid())
            return false;
        switch (node(parentRef).id())
        {
            case AstNodeId::EmbeddedBlock:
            case AstNodeId::FunctionBody:
            case AstNodeId::SwitchCaseBody:
            case AstNodeId::TopLevelBlock:
                break;
            default:
                return false;
        }
        blockRef = node(blockRef).cast<AstCompilerCodeBlock>().nodeBodyRef;
    }

    if (blockRef.isInvalid() || node(blockRef).isNot(AstNodeId::EmbeddedBlock))
        return false;
    return node(blockRef).cast<AstEmbeddedBlock>().hasFlag(AstEmbeddedBlockFlagsE::ImplicitCodeBlockArg);
}

bool Sema::isLValueStored(AstNodeRef ref) const
{
    if (ref.isInvalid())
        return false;
    const NodePayloadFlags flags = nodePayloadContext().payloadFlagsStored(node(ref));
    return (static_cast<uint16_t>(flags) & static_cast<uint16_t>(NodePayloadFlags::LValue)) != 0;
}

bool Sema::isValueStored(AstNodeRef ref) const
{
    if (ref.isInvalid())
        return false;
    const NodePayloadFlags flags = nodePayloadContext().payloadFlagsStored(node(ref));
    return (static_cast<uint16_t>(flags) & static_cast<uint16_t>(NodePayloadFlags::Value)) != 0;
}

bool Sema::isFoldedTypedConstStored(AstNodeRef ref) const
{
    if (ref.isInvalid())
        return false;
    const NodePayloadFlags flags = nodePayloadContext().payloadFlagsStored(node(ref));
    return (static_cast<uint16_t>(flags) & static_cast<uint16_t>(NodePayloadFlags::FoldedTypedConst)) != 0;
}

bool Sema::isConstAssignBindingStored(AstNodeRef ref) const
{
    if (ref.isInvalid())
        return false;
    const NodePayloadFlags flags = nodePayloadContext().payloadFlagsStored(node(ref));
    return (static_cast<uint16_t>(flags) & static_cast<uint16_t>(NodePayloadFlags::ConstAssignBinding)) != 0;
}

const SymbolVariable* Sema::constAssignSourceParameter(AstNodeRef ref) const
{
    if (const SymbolVariable* sourceParam = nodePayloadContext().getConstAssignSourceParameter(ref))
        return sourceParam;

    const AstNodeRef resolvedRef = resolvedNodeRef(ref);
    return resolvedRef != ref ? nodePayloadContext().getConstAssignSourceParameter(resolvedRef) : nullptr;
}

bool Sema::isConstAssignTargetStored(AstNodeRef ref) const
{
    if (ref.isInvalid())
        return false;
    const NodePayloadFlags flags = nodePayloadContext().payloadFlagsStored(node(ref));
    return (static_cast<uint16_t>(flags) & static_cast<uint16_t>(NodePayloadFlags::ConstAssignTarget)) != 0;
}

void Sema::pushFramePopOnPostChild(const SemaFrame& frame, AstNodeRef popAfterChildRef)
{
    pushFrame(frame);
    const size_t before = frames_.size();
    SWC_ASSERT(before > 0);
    DeferredPopFrame entry;
    entry.nodeRef                  = curNodeRef();
    entry.childRef                 = popAfterChildRef;
    entry.onPostNode               = false;
    entry.expectedFrameCountBefore = before;
    entry.expectedFrameCountAfter  = before - 1;
    deferredPopFrames_.push_back(entry);
}

void Sema::pushFramePopOnPostNode(const SemaFrame& frame, AstNodeRef popNodeRef)
{
    pushFrame(frame);
    const size_t before = frames_.size();
    SWC_ASSERT(before > 0);
    DeferredPopFrame entry;
    entry.nodeRef                  = popNodeRef.isValid() ? popNodeRef : curNodeRef();
    entry.onPostNode               = true;
    entry.expectedFrameCountBefore = before;
    entry.expectedFrameCountAfter  = before - 1;
    deferredPopFrames_.push_back(entry);
}

void Sema::deferPostNodeAction(AstNodeRef nodeRef, std::function<Result(Sema&, AstNodeRef)> callback)
{
    SWC_ASSERT(nodeRef.isValid());
    SWC_ASSERT(callback);
    DeferredPostNodeAction action;
    action.nodeRef  = nodeRef;
    action.callback = std::move(callback);
    deferredPostNodeActions_.push_back(std::move(action));
}

void Sema::processCurrentPostNodePopsNow()
{
    processDeferredPopsPostNode(curNodeRef());
}

SemaScope* Sema::pushScopePopOnPostChild(SemaScopeFlags flags, AstNodeRef popAfterChildRef)
{
    SemaScope*   scope  = pushScope(flags);
    const size_t before = scopes_.size();
    SWC_ASSERT(before > 0);
    DeferredPopScope scopeEntry;
    scopeEntry.nodeRef                  = curNodeRef();
    scopeEntry.childRef                 = popAfterChildRef;
    scopeEntry.onPostNode               = false;
    scopeEntry.expectedScopeCountBefore = before;
    scopeEntry.expectedScopeCountAfter  = before - 1;
    deferredPopScopes_.push_back(scopeEntry);
    return scope;
}

SemaScope* Sema::pushScopePopOnPostNode(SemaScopeFlags flags, AstNodeRef popNodeRef)
{
    SemaScope*   scope  = pushScope(flags);
    const size_t before = scopes_.size();
    SWC_ASSERT(before > 0);
    DeferredPopScope scopeEntry;
    scopeEntry.nodeRef                  = popNodeRef.isValid() ? popNodeRef : curNodeRef();
    scopeEntry.onPostNode               = true;
    scopeEntry.expectedScopeCountBefore = before;
    scopeEntry.expectedScopeCountAfter  = before - 1;
    deferredPopScopes_.push_back(scopeEntry);
    return scope;
}

namespace
{
    const Symbol* guessCurrentSymbol(Sema& sema)
    {
        const AstNodeRef   n    = sema.visit().root();
        const SemaNodeView view = sema.viewSymbol(n);
        if (view.hasSymbol())
            return view.sym();
        return sema.topSymMap();
    }

    SourceCodeRef currentCodeRef(Sema& sema, AstNodeRef nodeRef)
    {
        if (!nodeRef.isValid())
            return SourceCodeRef::invalid();
        return sema.node(nodeRef).codeRef();
    }

    AstNodeRef fallbackWaitNodeRef(Sema& sema, AstNodeRef nodeRef)
    {
        if (nodeRef.isValid())
            return nodeRef;

        const AstNodeRef stateNodeRef = sema.ctx().state().nodeRef;
        if (stateNodeRef.isValid())
            return stateNodeRef;

        return sema.curNodeRef();
    }

    SourceCodeRef fallbackWaitCodeRef(Sema& sema, AstNodeRef nodeRef, const SourceCodeRef& codeRef = SourceCodeRef::invalid())
    {
        if (codeRef.isValid())
            return codeRef;

        const AstNodeRef waitNodeRef = fallbackWaitNodeRef(sema, nodeRef);
        if (waitNodeRef.isValid())
            return sema.node(waitNodeRef).codeRef();

        return sema.ctx().state().codeRef;
    }

    bool shouldAbortResumedWait(Sema& sema)
    {
        const TaskState& state = sema.ctx().state();
        if (!state.hasPauseReason())
            return false;

        // A waited symbol can become ignored because a compiler-if branch was resolved.
        // Let the current node run again so name lookup can discard that stale candidate
        // and bind an equivalent live homonym when one exists. Real dependency failures
        // are still reported by the wait helpers after the node is re-evaluated.
        if (state.waiterSymbol && state.waiterSymbol->isIgnored())
            return true;

        switch (state.kind)
        {
            case TaskStateKind::SemaWaitIdentifier:
            case TaskStateKind::SemaWaitCompilerDefined:
            case TaskStateKind::SemaWaitImplRegistrations:
                return waitHasErrorOnLine(sema, state.codeRef);

            default:
                return false;
        }
    }

    bool shouldAbortWait(Sema& sema, const Symbol* blockingSymbol = nullptr)
    {
        if (blockingSymbol != nullptr && blockingSymbol->isIgnored())
            return true;

        const Symbol* currentSymbol = guessCurrentSymbol(sema);
        return currentSymbol != nullptr && currentSymbol->isIgnored();
    }
}

Result Sema::waitIdentifier(IdentifierRef idRef, const SourceCodeRef& codeRef)
{
    if (shouldAbortWait(*this))
        return Result::Error;

    // Wait helpers store enough context for the scheduler to sleep this job and later
    // resume the same AST node. Keep the recorded source location close to the blocked
    // dependency so diagnostics point at the expression that actually needs the symbol.
    const AstNodeRef    waitNodeRef = fallbackWaitNodeRef(*this, curNodeRef());
    const SourceCodeRef waitCodeRef = fallbackWaitCodeRef(*this, waitNodeRef, codeRef);
    if (waitHasErrorOnLine(*this, waitCodeRef))
        return Result::Error;

    TaskState& wait   = ctx().state();
    wait.kind         = TaskStateKind::SemaWaitIdentifier;
    wait.nodeRef      = waitNodeRef;
    wait.codeRef      = waitCodeRef;
    wait.idRef        = idRef;
    wait.waiterSymbol = guessCurrentSymbol(*this);
    return Result::Pause;
}

Result Sema::waitPredefined(IdentifierManager::PredefinedName name, TypeRef& typeRef, const SourceCodeRef& codeRef)
{
    typeRef = typeMgr().runtimeType(name);
    if (typeRef.isValid())
        return Result::Continue;

    if (const Symbol* predefinedSym = findPredefinedRuntimeSymbol(*this, name))
    {
        SWC_RESULT(waitSemaCompleted(predefinedSym, codeRef));
        typeRef = typeMgr().runtimeType(name);
        if (typeRef.isValid())
            return Result::Continue;
    }

    return waitIdentifier(idMgr().predefined(name), codeRef);
}

Result Sema::waitRuntimeFunction(const IdentifierManager::RuntimeFunctionKind kind, SymbolFunction*& symbol, const SourceCodeRef& codeRef)
{
    const IdentifierRef idRef = idMgr().runtimeFunction(kind);
    SWC_ASSERT(idRef.isValid());

    symbol = compiler().runtimeFunctionSymbol(idRef);
    if (!symbol)
        return waitIdentifier(idRef, codeRef);

    SWC_RESULT(waitDeclared(symbol, codeRef));
    SWC_RESULT(waitTyped(symbol, codeRef));
    return Result::Continue;
}

Result Sema::waitCompilerDefined(IdentifierRef idRef, const SourceCodeRef& codeRef)
{
    if (shouldAbortWait(*this))
        return Result::Error;

    const AstNodeRef waitNodeRef = fallbackWaitNodeRef(*this, curNodeRef());
    TaskState&       wait        = ctx().state();
    wait.kind                    = TaskStateKind::SemaWaitCompilerDefined;
    wait.nodeRef                 = waitNodeRef;
    wait.codeRef                 = fallbackWaitCodeRef(*this, waitNodeRef, codeRef);
    wait.idRef                   = idRef;
    wait.waiterSymbol            = guessCurrentSymbol(*this);
    return Result::Pause;
}

Result Sema::waitImplRegistrations(IdentifierRef idRef, const SourceCodeRef& codeRef)
{
    if (shouldAbortWait(*this))
        return Result::Error;

    const AstNodeRef waitNodeRef = fallbackWaitNodeRef(*this, curNodeRef());
    TaskState&       wait        = ctx().state();
    wait.kind                    = TaskStateKind::SemaWaitImplRegistrations;
    wait.nodeRef                 = waitNodeRef;
    wait.codeRef                 = fallbackWaitCodeRef(*this, waitNodeRef, codeRef);
    wait.idRef                   = idRef;
    wait.waiterSymbol            = guessCurrentSymbol(*this);
    return Result::Pause;
}

Result Sema::waitDeclared(const Symbol* symbol, const SourceCodeRef& codeRef)
{
    if (!symbol || symbol->isDeclared())
        return Result::Continue;
    if (shouldAbortWait(*this, symbol))
        return Result::Error;
    const AstNodeRef waitNodeRef = fallbackWaitNodeRef(*this, curNodeRef());
    TaskState&       wait        = ctx().state();
    wait.kind                    = TaskStateKind::SemaWaitSymDeclared;
    wait.nodeRef                 = waitNodeRef;
    wait.codeRef                 = fallbackWaitCodeRef(*this, waitNodeRef, codeRef);
    wait.symbol                  = symbol;
    wait.waiterSymbol            = guessCurrentSymbol(*this);
    return Result::Pause;
}

Result Sema::waitTyped(const Symbol* symbol, const SourceCodeRef& codeRef)
{
    if (!symbol || symbol->isTyped())
        return Result::Continue;
    if (shouldAbortWait(*this, symbol))
        return Result::Error;
    const AstNodeRef waitNodeRef = fallbackWaitNodeRef(*this, curNodeRef());
    TaskState&       wait        = ctx().state();
    wait.kind                    = TaskStateKind::SemaWaitSymTyped;
    wait.nodeRef                 = waitNodeRef;
    wait.codeRef                 = fallbackWaitCodeRef(*this, waitNodeRef, codeRef);
    wait.symbol                  = symbol;
    wait.waiterSymbol            = guessCurrentSymbol(*this);
    return Result::Pause;
}

Result Sema::waitSemaCompletedNoLazy(const Symbol* symbol, const SourceCodeRef& codeRef)
{
    if (!symbol || symbol->isSemaCompleted())
        return Result::Continue;
    if (shouldAbortWait(*this, symbol))
        return Result::Error;
    const AstNodeRef waitNodeRef = fallbackWaitNodeRef(*this, curNodeRef());
    TaskState&       wait        = ctx().state();
    wait.kind                    = TaskStateKind::SemaWaitSymSemaCompleted;
    wait.nodeRef                 = waitNodeRef;
    wait.codeRef                 = fallbackWaitCodeRef(*this, waitNodeRef, codeRef);
    wait.symbol                  = symbol;
    wait.waiterSymbol            = guessCurrentSymbol(*this);
    return Result::Pause;
}

Result Sema::waitSemaCompleted(const Symbol* symbol, const SourceCodeRef& codeRef)
{
    if (!symbol)
        return Result::Continue;
    if (shouldAbortWait(*this, symbol))
        return Result::Error;

    if (const auto* function = symbol->safeCast<SymbolFunction>())
    {
        if (function->isGenericInstance() && function->isGenericCompletionActive(ctx()))
            return Result::Continue;
    }
    else if (const auto* ownerStruct = symbol->safeCast<SymbolStruct>())
    {
        if (ownerStruct->isGenericInstance() && ownerStruct->isGenericCompletionActive(ctx()))
            return Result::Continue;
    }

    const auto* function = symbol->safeCast<SymbolFunction>();
    if (function && !function->isSemaCompleted())
    {
        const SymbolStruct* ownerStruct = function->ownerStruct();
        if (ownerStruct && ownerStruct->isGenericInstance() && !ownerStruct->isSemaCompleted())
            return waitSemaCompleted(ownerStruct, codeRef);
    }

    if (function && function->hasExtraFlag(SymbolFunctionFlagsE::LazyGenericBody))
    {
        auto& mutableFunction = *const_cast<SymbolFunction*>(function);
        if (!function->hasExtraFlag(SymbolFunctionFlagsE::LazyGenericBodyRunning))
        {
            const Result result = completeLazyGenericFunction(mutableFunction);
            if (result != Result::Continue)
                return result;
        }

        if (mutableFunction.isSemaCompleted())
            return Result::Continue;
        if (mutableFunction.isIgnored())
            return Result::Error;
    }

    if (symbol->isSemaCompleted())
        return Result::Continue;

    return waitSemaCompletedNoLazy(symbol, codeRef);
}

Result Sema::waitCodeGenCompleted(const Symbol* symbol, const SourceCodeRef& codeRef)
{
    if (!symbol || symbol->isCodeGenCompleted())
        return Result::Continue;
    if (shouldAbortWait(*this, symbol))
        return Result::Error;
    const AstNodeRef waitNodeRef = fallbackWaitNodeRef(*this, curNodeRef());
    TaskState&       wait        = ctx().state();
    wait.kind                    = TaskStateKind::SemaWaitSymCodeGenCompleted;
    wait.nodeRef                 = waitNodeRef;
    wait.codeRef                 = fallbackWaitCodeRef(*this, waitNodeRef, codeRef);
    wait.symbol                  = symbol;
    wait.waiterSymbol            = guessCurrentSymbol(*this);
    return Result::Pause;
}

Result Sema::waitCodeGenPreSolved(const Symbol* symbol, const SourceCodeRef& codeRef)
{
    if (!symbol || symbol->isCodeGenPreSolved() || symbol->isCodeGenCompleted())
        return Result::Continue;
    if (shouldAbortWait(*this, symbol))
        return Result::Error;
    const AstNodeRef waitNodeRef = fallbackWaitNodeRef(*this, curNodeRef());
    TaskState&       wait        = ctx().state();
    wait.kind                    = TaskStateKind::SemaWaitSymCodeGenPreSolved;
    wait.nodeRef                 = waitNodeRef;
    wait.codeRef                 = fallbackWaitCodeRef(*this, waitNodeRef, codeRef);
    wait.symbol                  = symbol;
    wait.waiterSymbol            = guessCurrentSymbol(*this);
    return Result::Pause;
}

Result Sema::waitSemaCompleted(const TypeInfo* type, AstNodeRef nodeRef)
{
    if (!type || type->isCompleted(ctx()))
        return Result::Continue;
    const Symbol* blockingSymbol = type->getNotCompletedSymbol(ctx());
    if (shouldAbortWait(*this, blockingSymbol))
        return Result::Error;
    const AstNodeRef waitNodeRef = fallbackWaitNodeRef(*this, nodeRef);
    TaskState&       wait        = ctx().state();
    wait.kind                    = TaskStateKind::SemaWaitTypeCompleted;
    wait.nodeRef                 = waitNodeRef;
    wait.codeRef                 = fallbackWaitCodeRef(*this, waitNodeRef);
    wait.symbol                  = blockingSymbol;
    wait.waiterSymbol            = guessCurrentSymbol(*this);
    return Result::Pause;
}

Result Sema::waitTypeInfoGeneration(AstNodeRef nodeRef, const SourceCodeRef& codeRef)
{
    if (shouldAbortWait(*this))
        return Result::Error;
    const AstNodeRef waitNodeRef = fallbackWaitNodeRef(*this, nodeRef);
    TaskState&       wait        = ctx().state();
    wait.kind                    = TaskStateKind::SemaWaitTypeInfoGeneration;
    wait.nodeRef                 = waitNodeRef;
    wait.codeRef                 = fallbackWaitCodeRef(*this, waitNodeRef, codeRef);
    wait.waiterSymbol            = guessCurrentSymbol(*this);
    return Result::Pause;
}

Result Sema::makeRuntimeTypeInfo(ConstantRef& outRef, TypeRef typeRef, AstNodeRef ownerNodeRef)
{
    // Try to publish the runtime type-info without parking the worker on the shard-local
    // type-gen mutex. If another worker already owns the shard, yield cooperatively so this
    // job can make progress elsewhere instead of blocking until the owner publishes.
    const Result result = cstMgr().makeTypeInfo(*this, outRef, typeRef, ownerNodeRef, ConstantManager::TypeInfoLockMode::TryLock);
    if (result != Result::Pause)
        return result;

    // An already-pending semantic wait takes precedence over the transient cache contention.
    if (ctx().state().hasPauseReason())
        return Result::Pause;

    // Type-info cache contention is transient work sharing, not a semantic dependency.
    // The drain loop in waitDone() keeps these waiters re-driven until the shard owner publishes.
    return waitTypeInfoGeneration(ownerNodeRef);
}

void Sema::setVisitors()
{
    if (declPass_)
    {
        visit_.setPreNodeVisitor([this](AstNode& node) { return preDecl(node); });
        visit_.setPreChildVisitor([this](AstNode& node, AstNodeRef& childRef) { return preDeclChild(node, childRef); });
        visit_.setPostChildVisitor([this](AstNode& node, AstNodeRef& childRef) { return postDeclChild(node, childRef); });
        visit_.setPostNodeVisitor([this](AstNode& node) { return postDecl(node); });
    }
    else
    {
        visit_.setPreNodeVisitor([this](AstNode& node) { return preNode(node); });
        visit_.setPreChildVisitor([this](AstNode& node, AstNodeRef& childRef) { return preNodeChild(node, childRef); });
        visit_.setPostChildVisitor([this](AstNode& node, AstNodeRef& childRef) { return postNodeChild(node, childRef); });
        visit_.setPostNodeVisitor([this](AstNode& node) { return postNode(node); });
    }
}

Result Sema::preDecl(AstNode& node)
{
    const AstNodeIdInfo& info = Ast::nodeIdInfos(node.id());
    return info.semaPreDecl(*this, node);
}

Result Sema::preDeclChild(AstNode& node, AstNodeRef& childRef)
{
    const AstNodeIdInfo& info = Ast::nodeIdInfos(node.id());
    return info.semaPreDeclChild(*this, node, childRef);
}

Result Sema::postDeclChild(AstNode& node, AstNodeRef& childRef)
{
    const AstNodeIdInfo& info   = Ast::nodeIdInfos(node.id());
    const Result         result = info.semaPostDeclChild(*this, node, childRef);
    if (result == Result::Continue)
        processDeferredPopsPostChild(curNodeRef(), childRef);
    return result;
}

Result Sema::postDecl(AstNode& node)
{
    const AstNodeIdInfo& info   = Ast::nodeIdInfos(node.id());
    const Result         result = info.semaPostDecl(*this, node);
    if (result == Result::Continue)
        processDeferredPopsPostNode(curNodeRef());
    return result;
}

Result Sema::preNode(AstNode& node)
{
    const AstNodeIdInfo& info   = Ast::nodeIdInfos(node.id());
    const Result         result = info.semaPreNode(*this, node);
    if (result != Result::Continue)
        return result;

    bool      pushContextFrame = false;
    SemaFrame frame            = this->frame();
    if (node.is(AstNodeId::FunctionBody) || node.is(AstNodeId::EmbeddedBlock))
    {
        // `__uniq` is scoped to the nearest syntactic body/block, so cache that root
        // once at entry instead of rediscovering it through parent walks on demand.
        frame.setSyntaxScopeNodeRef(curNodeRef());
        pushContextFrame = true;
    }

    if (SemaRuntime::isCompilerEvalContextNode(*this, node))
    {
        // Compiler-eval availability is part of sema's dynamic context. Push it once
        // at node entry so descendants do not have to rescan the AST parent chain.
        frame.addContextFlag(SemaFrameContextFlagsE::CompilerEval);
        pushContextFrame = true;
    }

    if (!compilerAstExpansions_.empty() && node.is(AstNodeId::TopLevelBlock))
    {
        // Nested compiler-ast expansions need to know when they already run inside
        // a generated top-level subtree, without rediscovering that ancestor on demand.
        frame.addContextFlag(SemaFrameContextFlagsE::GeneratedTopLevel);
        pushContextFrame = true;
    }

    if (pushContextFrame)
        pushFramePopOnPostNode(frame);

    const SemaNodeView view = viewSymbol(curNodeRef());
    if (view.hasSymbol() && view.sym() && view.sym()->isIgnored())
        return Result::SkipChildren;

    return Result::Continue;
}

Result Sema::postNode(AstNode& node)
{
    const AstNodeRef     nodeRef = curNodeRef();
    const SemaNodeView   view    = viewSymbol(nodeRef);
    const AstNodeIdInfo& info    = Ast::nodeIdInfos(node.id());

    auto result = Result::Continue;
    if (!(view.hasSymbol() && view.sym() && view.sym()->isIgnored()))
        result = info.semaPostNode(*this, node);

    if (result == Result::Continue)
    {
        processDeferredPopsPostNode(nodeRef);
        if (nodeRef == curNodeRef())
            SWC_RESULT(processDeferredPostNodeActions(nodeRef));
    }
    return result;
}

void Sema::errorCleanupNode(AstNodeRef nodeRef, AstNode& node)
{
    const AstNodeIdInfo& info = Ast::nodeIdInfos(node.id());
    info.semaErrorCleanup(*this, node, nodeRef);

    const SemaNodeView view = viewSymbol(nodeRef);
    if (!view.hasSymbol())
        return;

    Symbol* sym = view.sym();
    // Only declaration nodes own the lifetime of their attached symbol. Use
    // sites can also carry resolved symbols (identifiers, calls, etc.), and a
    // failure while sema-ing those nodes must not invalidate the referenced
    // declaration in another parallel job.
    if (sym != nullptr && sym->decl() == &node && !sym->isSemaCompleted())
        sym->setIgnored(ctx());
}

void Sema::cleanupFailedVisit()
{
    if (visit().currentNodeRef().isValid())
        errorCleanupNode(visit().currentNodeRef(), ast().node(visit().currentNodeRef()));

    for (size_t up = 0;; up++)
    {
        const AstNodeRef parentRef = visit().parentNodeRef(up);
        if (parentRef.isInvalid())
            break;
        errorCleanupNode(parentRef, ast().node(parentRef));
    }

    // A failure can stop the walk before later `impl` nodes in the same subtree are visited.
    // Resolve their pending registration bookkeeping so struct completion barriers cannot stall.
    cleanupPendingImplRegistrations(*this, visit().root());
}

Result Sema::preNodeChild(AstNode& node, AstNodeRef& childRef)
{
    if (curScope_->isTopLevel() && !frame().globalCompilerIfEnabled())
        return Result::SkipChildren;
    if (isImplicitCodeBlockArg(curNodeRef(), childRef))
        return Result::SkipChildren;

    const AstNodeIdInfo& info = Ast::nodeIdInfos(node.id());
    SWC_RESULT(info.semaPreNodeChild(*this, node, childRef));

    if (curScope_->isTopLevel())
    {
        const AstNode&       child                 = ast().node(childRef);
        const AstNodeIdInfo& childInfo             = Ast::nodeIdInfos(child.id());
        const bool           compilerRun           = isCompilerRunFunction(*this, child);
        const bool           compilerAst           = isCompilerAstFunction(*this, child);
        const bool           deferCompilerTopLevel = !curScope_->isImpl();

        if (!compilerAstExpansions_.empty())
        {
            const bool generatedTopLevelContext = frame().hasContextFlag(SemaFrameContextFlagsE::GeneratedTopLevel);

            // Nested generated top-level blocks now receive their own decl pass before
            // the full pass reaches this point. That restores the same symbol visibility
            // contract as regular files, so their declaration jobs can stay deferred.
            if ((deferCompilerTopLevel && (compilerRun || compilerAst)) || (!generatedTopLevelContext && childInfo.hasFlag(AstNodeIdFlagsE::SemaJob)))
                return Result::Continue;
        }

        if (deferCompilerTopLevel && compilerRun)
        {
            deferTopLevelItems_ = true;
            deferTopLevelItem(childRef, DeferredTopLevelItemKind::CompilerRun);
            return Result::SkipChildren;
        }

        if (deferCompilerTopLevel && compilerAst)
        {
            deferTopLevelItems_ = true;
            deferTopLevelItem(childRef, DeferredTopLevelItemKind::CompilerAst);
            return Result::SkipChildren;
        }

        if (childInfo.hasFlag(AstNodeIdFlagsE::SemaJob))
        {
            if (deferTopLevelItems_)
                deferTopLevelItem(childRef, DeferredTopLevelItemKind::SemaJob);
            else
                enqueueTopLevelSemaJob(childRef);
            return Result::SkipChildren;
        }
    }

    return Result::Continue;
}

Result Sema::postNodeChild(AstNode& node, AstNodeRef& childRef)
{
    const AstNodeIdInfo& info   = Ast::nodeIdInfos(node.id());
    const Result         result = info.semaPostNodeChild(*this, node, childRef);
    if (result == Result::Continue)
        processDeferredPopsPostChild(curNodeRef(), childRef);
    return result;
}

void Sema::processDeferredPopsPostChild(AstNodeRef nodeRef, AstNodeRef childRef)
{
    // Process in reverse order (stack-like) so nested registrations are handled correctly.
    while (!deferredPopFrames_.empty())
    {
        const auto& last = deferredPopFrames_.back();
        if (last.onPostNode || last.nodeRef != nodeRef || last.childRef != childRef)
            break;
        SWC_ASSERT(frames_.size() == last.expectedFrameCountBefore);
        SWC_ASSERT(last.expectedFrameCountAfter + 1 == last.expectedFrameCountBefore);
        popFrame();
        SWC_ASSERT(frames_.size() == last.expectedFrameCountAfter);
        deferredPopFrames_.pop_back();
    }

    while (!deferredPopScopes_.empty())
    {
        const auto& last = deferredPopScopes_.back();
        if (last.onPostNode || last.nodeRef != nodeRef || last.childRef != childRef)
            break;
        SWC_ASSERT(scopes_.size() == last.expectedScopeCountBefore);
        SWC_ASSERT(last.expectedScopeCountAfter + 1 == last.expectedScopeCountBefore);
        popScope();
        SWC_ASSERT(scopes_.size() == last.expectedScopeCountAfter);
        deferredPopScopes_.pop_back();
    }
}

void Sema::processDeferredPopsPostNode(AstNodeRef nodeRef)
{
    while (!deferredPopFrames_.empty())
    {
        const auto& last = deferredPopFrames_.back();
        if (!last.onPostNode || last.nodeRef != nodeRef)
            break;
        SWC_ASSERT(frames_.size() == last.expectedFrameCountBefore);
        popFrame();
        SWC_ASSERT(frames_.size() == last.expectedFrameCountAfter);
        deferredPopFrames_.pop_back();
    }

    while (!deferredPopScopes_.empty())
    {
        const auto& last = deferredPopScopes_.back();
        if (!last.onPostNode || last.nodeRef != nodeRef)
            break;
        SWC_ASSERT(scopes_.size() == last.expectedScopeCountBefore);
        popScope();
        SWC_ASSERT(scopes_.size() == last.expectedScopeCountAfter);
        deferredPopScopes_.pop_back();
    }
}

Result Sema::processDeferredPostNodeActions(AstNodeRef nodeRef)
{
    while (!deferredPostNodeActions_.empty())
    {
        const auto& last = deferredPostNodeActions_.back();
        if (last.nodeRef != nodeRef)
            break;

        const Result res = last.callback(*this, nodeRef);
        if (res != Result::Continue)
            return res;

        deferredPostNodeActions_.pop_back();
    }

    return Result::Continue;
}

void Sema::deferTopLevelItem(AstNodeRef nodeRef, DeferredTopLevelItemKind kind)
{
    DeferredTopLevelItem item;
    item.nodeRef = nodeRef;
    item.kind    = kind;

    if (!deferredTopLevelItemRunning_)
    {
        deferredTopLevelItems_.push_back(item);
        return;
    }

    const auto insertIt = deferredTopLevelItems_.begin() + deferredTopLevelItemInsertIndex_;
    deferredTopLevelItems_.insert(insertIt, item);
    deferredTopLevelItemInsertIndex_++;
}

void Sema::enqueueTopLevelSemaJob(AstNodeRef nodeRef)
{
    auto* job = compiler().makeJob<SemaJob>(ctx(), *this, nodeRef);
    compiler().global().jobMgr().enqueue(*job, JobPriority::Normal, compiler().jobClientId());
}

Result Sema::runCurrentVisit()
{
    while (true)
    {
        const AstNodeRef nodeRef = visit_.currentNodeRef();
        ctx().state().setSemaParsing(nodeRef, currentCodeRef(*this, nodeRef));

        // AstVisit owns the pre/post traversal cursor. Sema only translates its pause,
        // error and stop states into job-level results, which keeps resumable semantic
        // analysis localized to the visitor.
        const AstVisitResult result = visit_.step(ctx());
        if (result == AstVisitResult::Pause)
            return Result::Pause;

        if (result == AstVisitResult::Error)
        {
            cleanupFailedVisit();
            return Result::Error;
        }

        if (result == AstVisitResult::Stop)
            return Result::Continue;
    }
}

Result Sema::processDeferredTopLevelNode(AstNodeRef nodeRef, uint32_t insertIndex)
{
    if (!deferredTopLevelItemRunning_)
    {
        visit_.start(ast(), nodeRef);
        deferredTopLevelItemRunning_     = true;
        deferredTopLevelItemInsertIndex_ = insertIndex;
    }

    const Result result = runCurrentVisit();
    if (result != Result::Continue)
        return result;

    deferredTopLevelItemRunning_ = false;
    return Result::Continue;
}

Result Sema::processPendingTopLevelCompilerRuns(uint32_t insertIndex)
{
    while (pendingTopLevelCompilerRunIndex_ < pendingTopLevelCompilerRunRefs_.size())
    {
        const AstNodeRef nodeRef = pendingTopLevelCompilerRunRefs_[pendingTopLevelCompilerRunIndex_];
        SWC_RESULT(processDeferredTopLevelNode(nodeRef, insertIndex));
        pendingTopLevelCompilerRunIndex_++;
    }

    pendingTopLevelCompilerRunRefs_.clear();
    pendingTopLevelCompilerRunIndex_ = 0;

    return Result::Continue;
}

Result Sema::processDeferredTopLevelItems()
{
    while (deferredTopLevelItemIndex_ < deferredTopLevelItems_.size())
    {
        const DeferredTopLevelItem item = deferredTopLevelItems_[deferredTopLevelItemIndex_];
        switch (item.kind)
        {
            case DeferredTopLevelItemKind::SemaJob:
            {
                enqueueTopLevelSemaJob(item.nodeRef);
                deferredTopLevelItemIndex_++;
                break;
            }

            case DeferredTopLevelItemKind::CompilerRun:
            {
                pendingTopLevelCompilerRunRefs_.push_back(item.nodeRef);
                deferredTopLevelItemIndex_++;
                break;
            }

            case DeferredTopLevelItemKind::CompilerAst:
            {
                // Top-level #ast expansion must observe all earlier top-level #run output.
                // Flush queued compiler runs before expanding the AST item, but keep later
                // items in the queue so nested insertions preserve source order.
                if (!pendingTopLevelCompilerRunRefs_.empty())
                {
                    SWC_RESULT(processPendingTopLevelCompilerRuns(deferredTopLevelItemIndex_));
                    break;
                }

                SWC_RESULT(processDeferredTopLevelNode(item.nodeRef, deferredTopLevelItemIndex_ + 1));
                deferredTopLevelItemIndex_++;
                break;
            }
        }
    }

    if (!pendingTopLevelCompilerRunRefs_.empty())
        SWC_RESULT(processPendingTopLevelCompilerRuns(static_cast<uint32_t>(deferredTopLevelItems_.size())));

    return Result::Continue;
}

Result Sema::execResult()
{
    if (!curScope_ && scopes_.empty())
    {
        scopes_.emplace_back(std::make_unique<SemaScope>(SemaScopeFlagsE::TopLevel, nullptr));
        curScope_ = scopes_.back().get();
        curScope_->setSymMap(startSymMap_);
    }

    if (shouldAbortResumedWait(*this))
    {
        cleanupFailedVisit();
        ctx().state().setNone();
        scopes_.clear();
        return Result::Error;
    }

    ctx().state().setNone();

    auto semaResult = Result::Continue;
    if (!rootVisitDone_)
    {
        semaResult = runCurrentVisit();
        if (semaResult == Result::Continue)
            rootVisitDone_ = true;
    }

    if (semaResult == Result::Continue)
        semaResult = processDeferredTopLevelItems();

    if (semaResult != Result::Pause)
        scopes_.clear();

    return semaResult;
}

JobResult Sema::exec()
{
    return Job::toJobResult(ctx(), execResult());
}

namespace
{
    bool resolveCompilerDefined(const TaskContext& ctx, JobClientId clientId)
    {
        std::vector<Job*> jobs;
        ctx.global().jobMgr().waitingJobs(jobs, clientId);

        bool doneSomething = false;
        for (Job* job : jobs)
        {
            const TaskState& state = job->ctx().state();
            if (state.kind == TaskStateKind::SemaWaitCompilerDefined)
            {
                // @CompilerNotDefined
                auto* semaJob = job->cast<SemaJob>();
                semaJob->sema().setConstant(state.nodeRef, semaJob->sema().cstMgr().cstFalse());
                doneSomething = true;
            }
        }

        return doneSomething;
    }

    bool hasPausedLazyGenericBodyWait(const TaskContext& ctx, JobClientId clientId)
    {
        std::vector<Job*> jobs;
        ctx.global().jobMgr().waitingJobs(jobs, clientId);

        for (Job* job : jobs)
        {
            const TaskState& state    = job->ctx().state();
            const auto*      function = state.symbol ? state.symbol->safeCast<SymbolFunction>() : nullptr;
            if (!function)
                continue;
            if (function->isSemaCompleted() || function->isIgnored())
                continue;
            if (!function->hasExtraFlag(SymbolFunctionFlagsE::LazyGenericBody))
                continue;
            if (function->hasExtraFlag(SymbolFunctionFlagsE::LazyGenericBodyRunning))
                continue;
            return true;
        }

        return false;
    }

    bool hasPausedTypeInfoGenWait(const TaskContext& ctx, JobClientId clientId)
    {
        std::vector<Job*> jobs;
        ctx.global().jobMgr().waitingJobs(jobs, clientId);

        for (Job* job : jobs)
        {
            if (job->ctx().state().kind == TaskStateKind::SemaWaitTypeInfoGeneration)
                return true;
        }

        return false;
    }
}

void Sema::waitDone(TaskContext& ctx, JobClientId clientId)
{
    auto&             jobMgr   = ctx.global().jobMgr();
    CompilerInstance& compiler = ctx.compiler();
    SWC_DEV_LOOP_GUARD(loopGuard, 100000, "Sema::waitDone");
    constexpr uint32_t maxPausedLazyGenericWakes = 1024;
    uint32_t           pausedLazyGenericWakes    = 0;
    constexpr uint32_t maxPausedTypeInfoGenWakes = 1024;
    uint32_t           pausedTypeInfoGenWakes    = 0;

    while (true)
    {
        SWC_DEV_LOOP_TICK(loopGuard);
        jobMgr.waitAll(clientId);

        // Main-thread work can unblock semantic jobs without any worker finishing: JIT
        // execution, compiler messages, lazy generic bodies, and type-info publication
        // all feed back into the same wait graph.
        if (compiler.jitExecMgr().executePendingMainThread())
        {
            SWC_DEV_LOOP_RESET(loopGuard);
            pausedLazyGenericWakes = 0;
            pausedTypeInfoGenWakes = 0;
            jobMgr.wakeAll(clientId);
            continue;
        }

        const Result compilerMessageResult = compiler.executePendingCompilerMessages(ctx);
        if (compilerMessageResult == Result::Pause)
        {
            SWC_DEV_LOOP_RESET(loopGuard);
            pausedLazyGenericWakes = 0;
            pausedTypeInfoGenWakes = 0;
            jobMgr.wakeAll(clientId);
            continue;
        }

        if (compilerMessageResult == Result::Error)
            break;

        const Result afterSemanticResult = compiler.ensureCompilerMessagePass(Runtime::CompilerMsgKind::PassAfterSemantic);
        if (afterSemanticResult == Result::Pause)
        {
            SWC_DEV_LOOP_RESET(loopGuard);
            pausedLazyGenericWakes = 0;
            pausedTypeInfoGenWakes = 0;
            jobMgr.wakeAll(clientId);
            continue;
        }

        if (afterSemanticResult == Result::Error)
            break;

        if (compiler.consumeChanged())
        {
            SWC_DEV_LOOP_RESET(loopGuard);
            pausedLazyGenericWakes = 0;
            pausedTypeInfoGenWakes = 0;
            compiler.jitExecMgr().wakeWaiting();
            jobMgr.wakeAll(clientId);
            continue;
        }

        if (resolveCompilerDefined(ctx, clientId))
        {
            SWC_DEV_LOOP_RESET(loopGuard);
            pausedLazyGenericWakes = 0;
            pausedTypeInfoGenWakes = 0;
            jobMgr.wakeAll(clientId);
            continue;
        }

        if (pausedLazyGenericWakes < maxPausedLazyGenericWakes && hasPausedLazyGenericBodyWait(ctx, clientId))
        {
            pausedLazyGenericWakes++;
            SWC_DEV_LOOP_RESET(loopGuard);
            jobMgr.wakeAll(clientId);
            continue;
        }

        // A job parked on type-info generation is waiting on transient shard-lock contention,
        // not a semantic dependency: the owning worker publishes and clears it. Re-drive these
        // waiters (bounded, to still surface a genuine cycle) instead of breaking out and
        // letting SemaCycle misreport the contention as an unresolvable dependency.
        if (pausedTypeInfoGenWakes < maxPausedTypeInfoGenWakes && hasPausedTypeInfoGenWait(ctx, clientId))
        {
            pausedTypeInfoGenWakes++;
            SWC_DEV_LOOP_RESET(loopGuard);
            jobMgr.wakeAll(clientId);
            continue;
        }
        break;
    }

    SemaCycle sc;
    sc.check(ctx, clientId);

    compiler.jitExecMgr().completeWaitingOnIgnoredDependency();

    // Main-thread JIT waits only surface the outer "wait for JIT completion" state in JobManager.
    // If cycle resolution just invalidated one of the JIT item's hidden dependencies, give it one
    // final retry before draining the awakened sema jobs.
    if (compiler.jitExecMgr().wakeWaiting())
        compiler.jitExecMgr().executePendingMainThread();

    if (jobMgr.wakeAll(clientId))
        jobMgr.waitAll(clientId);

    // Every sema job of this wave is done: the per-function borrow summaries are final,
    // so the call sites that snapshotted their argument borrows can be judged now.
    SemaEscape::reportDeferredChecks(ctx);

    if (!Stats::hasError() && ctx.cmdLine().command != CommandKind::Test)
    {
        for (SourceFile* f : ctx.compiler().files())
        {
            if (!f->ast().hasSourceView())
                continue;

            const SourceView& srcView = f->ast().srcView();
            if (srcView.mustSkip())
                continue;
            f->unitTest().verifyUntouchedExpected(ctx, srcView);
        }
    }
}

SWC_END_NAMESPACE();
