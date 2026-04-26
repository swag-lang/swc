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
#include "Compiler/Sema/Symbol/Symbol.Impl.h"
#include "Compiler/Sema/Symbol/Symbols.h"
#include "Compiler/Verify.h"
#include "Main/Command/CommandLine.h"
#include "Main/CompilerInstance.h"
#include "Main/Global.h"
#include "Support/Memory/Heap.h"
#include "Support/Thread/JobManager.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    bool shouldAbortWait(const Symbol* symbol = nullptr)
    {
        return symbol != nullptr && symbol->isIgnored();
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

    SemaScope* remapScopeFromParent(const std::vector<std::unique_ptr<SemaScope>>& parentScopes,
                                    const std::vector<std::unique_ptr<SemaScope>>& childScopes,
                                    const SemaScope*                               oldScope)
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
                auto* const sym = view.sym();
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
    if (&payloadContext != parent.nodePayloadContext_)
        return &payloadContext.moduleNamespace();

    if (!parent.curScope_)
        return parent.startSymMap_;

    if (parent.curScope_->isTopLevel())
        return SemaFrame::currentSymMap(parent);

    return parent.curScope_->symMap();
}

Sema::Sema(TaskContext& ctx, NodePayload& payloadContext, bool declPass) :
    ctx_(&ctx),
    nodePayloadContext_(&payloadContext),
    startSymMap_(nodePayloadContext().moduleNamespace().ownerSymMap()),
    declPass_(declPass)
{
    visit_.start(nodePayloadContext_->ast(), nodePayloadContext_->ast().root());
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
    frame().setCurrentInlinePayload(nullptr);
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
}

Sema::~Sema() = default;

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
    const auto* const scope = lookupScope();
    return scope ? scope->lookupParent() : nullptr;
}

void Sema::configureLookupFrame(SemaFrame& frame, SemaScope* lookupScope, bool ignoreRuntimeAccess)
{
    frame.setLookupScope(lookupScope);
    frame.setUpLookupScope(lookupScope ? lookupScope->lookupParent() : nullptr);
    frame.setIgnoreRuntimeAccess(ignoreRuntimeAccess);
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
    return scope;
}

void Sema::popScope()
{
    SWC_ASSERT(curScope_);
    curScope_ = curScope_->parent();
    scopes_.pop_back();
}

void Sema::pushFrame(const SemaFrame& frame)
{
    frames_.push_back(frame);
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
    if (node(childRef).is(AstNodeId::EmbeddedBlock))
        node(childRef).cast<AstEmbeddedBlock>().addFlag(AstEmbeddedBlockFlagsE::ImplicitCodeBlockArg);
}

bool Sema::isImplicitCodeBlockArg(AstNodeRef parentRef, AstNodeRef childRef) const
{
    SWC_UNUSED(parentRef);
    if (childRef.isInvalid() || node(childRef).isNot(AstNodeId::EmbeddedBlock))
        return false;
    return node(childRef).cast<AstEmbeddedBlock>().hasFlag(AstEmbeddedBlockFlagsE::ImplicitCodeBlockArg);
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
}

Result Sema::waitIdentifier(IdentifierRef idRef, const SourceCodeRef& codeRef)
{
    if (shouldAbortWait())
        return Result::Error;

    const AstNodeRef waitNodeRef = fallbackWaitNodeRef(*this, curNodeRef());
    TaskState&       wait        = ctx().state();
    wait.kind                    = TaskStateKind::SemaWaitIdentifier;
    wait.nodeRef                 = waitNodeRef;
    wait.codeRef                 = fallbackWaitCodeRef(*this, waitNodeRef, codeRef);
    wait.idRef                   = idRef;
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
    if (shouldAbortWait())
        return Result::Error;

    const AstNodeRef waitNodeRef = fallbackWaitNodeRef(*this, curNodeRef());
    TaskState&       wait        = ctx().state();
    wait.kind                    = TaskStateKind::SemaWaitCompilerDefined;
    wait.nodeRef                 = waitNodeRef;
    wait.codeRef                 = fallbackWaitCodeRef(*this, waitNodeRef, codeRef);
    wait.idRef                   = idRef;
    return Result::Pause;
}

Result Sema::waitImplRegistrations(IdentifierRef idRef, const SourceCodeRef& codeRef)
{
    if (shouldAbortWait())
        return Result::Error;

    const AstNodeRef waitNodeRef = fallbackWaitNodeRef(*this, curNodeRef());
    TaskState&       wait        = ctx().state();
    wait.kind                    = TaskStateKind::SemaWaitImplRegistrations;
    wait.nodeRef                 = waitNodeRef;
    wait.codeRef                 = fallbackWaitCodeRef(*this, waitNodeRef, codeRef);
    wait.idRef                   = idRef;
    return Result::Pause;
}

Result Sema::waitDeclared(const Symbol* symbol, const SourceCodeRef& codeRef)
{
    if (!symbol || symbol->isDeclared())
        return Result::Continue;
    if (shouldAbortWait(symbol))
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
    if (shouldAbortWait(symbol))
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

Result Sema::waitSemaCompleted(const Symbol* symbol, const SourceCodeRef& codeRef)
{
    if (!symbol || symbol->isSemaCompleted())
        return Result::Continue;
    if (shouldAbortWait(symbol))
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

Result Sema::waitCodeGenCompleted(const Symbol* symbol, const SourceCodeRef& codeRef)
{
    if (!symbol || symbol->isCodeGenCompleted())
        return Result::Continue;
    if (shouldAbortWait(symbol))
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
    if (shouldAbortWait(symbol))
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
    if (shouldAbortWait(blockingSymbol))
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

    Symbol* const sym = view.sym();
    // Only declaration nodes own the lifetime of their attached symbol. Use
    // sites can also carry resolved symbols (identifiers, calls, etc.), and a
    // failure while sema-ing those nodes must not invalidate the referenced
    // declaration in another parallel job.
    if (sym != nullptr && sym->decl() == &node && !sym->isSemaCompleted())
        sym->setIgnored(ctx());
}

Result Sema::preNodeChild(AstNode& node, AstNodeRef& childRef)
{
    if (curScope_->isTopLevel() && (ast().hasFlag(AstFlagsE::GlobalSkip) || !frame().globalCompilerIfEnabled()))
        return Result::SkipChildren;
    if (isImplicitCodeBlockArg(curNodeRef(), childRef))
        return Result::SkipChildren;

    const AstNodeIdInfo& info = Ast::nodeIdInfos(node.id());
    SWC_RESULT(info.semaPreNodeChild(*this, node, childRef));

    if (curScope_->isTopLevel())
    {
        const AstNode&       child       = ast().node(childRef);
        const AstNodeIdInfo& childInfo   = Ast::nodeIdInfos(child.id());
        const bool           compilerRun = isCompilerRunFunction(*this, child);
        const bool           compilerAst = isCompilerAstFunction(*this, child);

        if (!compilerAstExpansions_.empty() && (compilerRun || compilerAst))
            return Result::Continue;

        if (compilerRun)
        {
            deferTopLevelItems_ = true;
            deferTopLevelItem(childRef, DeferredTopLevelItemKind::CompilerRun);
            return Result::SkipChildren;
        }

        if (compilerAst)
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
    auto* job = heapNew<SemaJob>(ctx(), *this, nodeRef);
    compiler().global().jobMgr().enqueue(*job, JobPriority::Normal, compiler().jobClientId());
}

Result Sema::runCurrentVisit()
{
    while (true)
    {
        const AstNodeRef nodeRef = visit_.currentNodeRef();
        ctx().state().setSemaParsing(nodeRef, currentCodeRef(*this, nodeRef));

        const AstVisitResult result = visit_.step(ctx());
        if (result == AstVisitResult::Pause)
            return Result::Pause;

        if (result == AstVisitResult::Error)
        {
            // Visiting has stopped. Clean up remaining active nodes.
            if (visit_.currentNodeRef().isValid())
                errorCleanupNode(visit_.currentNodeRef(), ast().node(visit_.currentNodeRef()));
            for (size_t up = 0;; up++)
            {
                const AstNodeRef parentRef = visit_.parentNodeRef(up);
                if (parentRef.isInvalid())
                    break;
                errorCleanupNode(parentRef, ast().node(parentRef));
            }

            // A failure can stop the walk before later `impl` nodes in the same subtree are visited.
            // Resolve their pending registration bookkeeping so struct completion barriers cannot stall.
            cleanupPendingImplRegistrations(*this, visit_.root());

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
}

void Sema::waitDone(TaskContext& ctx, JobClientId clientId)
{
    auto&             jobMgr   = ctx.global().jobMgr();
    CompilerInstance& compiler = ctx.compiler();

    while (true)
    {
        jobMgr.waitAll(clientId);

        if (compiler.jitExecMgr().executePendingMainThread())
        {
            jobMgr.wakeAll(clientId);
            continue;
        }

        const Result compilerMessageResult = compiler.executePendingCompilerMessages(ctx);
        if (compilerMessageResult == Result::Pause)
        {
            jobMgr.wakeAll(clientId);
            continue;
        }

        if (compilerMessageResult == Result::Error)
            break;

        const Result afterSemanticResult = compiler.ensureCompilerMessagePass(Runtime::CompilerMsgKind::PassAfterSemantic);
        if (afterSemanticResult == Result::Pause)
        {
            jobMgr.wakeAll(clientId);
            continue;
        }

        if (afterSemanticResult == Result::Error)
            break;

        if (compiler.consumeChanged())
        {
            compiler.jitExecMgr().wakeWaiting();
            jobMgr.wakeAll(clientId);
            continue;
        }

        if (resolveCompilerDefined(ctx, clientId))
        {
            jobMgr.wakeAll(clientId);
            continue;
        }

        break;
    }

    SemaCycle sc;
    sc.check(ctx, clientId);

    if (Stats::hasError() && jobMgr.wakeAll(clientId))
        jobMgr.waitAll(clientId);

    if (!Stats::hasError() && ctx.cmdLine().command != CommandKind::Test)
    {
        for (SourceFile* f : ctx.compiler().files())
        {
            const SourceView& srcView = f->ast().srcView();
            if (srcView.mustSkip())
                continue;
            f->unitTest().verifyUntouchedExpected(ctx, srcView);
        }
    }
}

SWC_END_NAMESPACE();
