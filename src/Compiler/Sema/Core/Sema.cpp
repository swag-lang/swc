#include "pch.h"
#include "Compiler/Sema/Core/Sema.h"
#include "Compiler/Sema/Constant/ConstantManager.h"
#include "Compiler/Sema/Core/NodePayloadContext.h"
#include "Compiler/Sema/Core/SemaJob.h"
#include "Compiler/Sema/Core/SemaScope.h"
#include "Compiler/Sema/Helpers/SemaCycle.h"
#include "Compiler/Sema/Helpers/SemaError.h"
#include "Compiler/Sema/Symbol/Symbols.h"
#include "Main/CompilerInstance.h"
#include "Main/Global.h"
#include "Support/Memory/Heap.h"
#include "Support/Thread/JobManager.h"
#include "Wmf/Verify.h"

SWC_BEGIN_NAMESPACE();

Sema::Sema(TaskContext& ctx, NodePayloadContext& payloadContext, bool declPass) :
    ctx_(&ctx),
    nodePayloadContext_(&payloadContext),
    startSymMap_(nodePayloadContext().moduleNamespace().ownerSymMap()),
    declPass_(declPass)
{
    visit_.start(nodePayloadContext_->ast(), nodePayloadContext_->ast().root());
    setVisitors();
    pushFrame({});
}

Sema::Sema(TaskContext& ctx, const Sema& parent, AstNodeRef root) :
    ctx_(&ctx),
    nodePayloadContext_(parent.nodePayloadContext_),
    startSymMap_(parent.curScope_ ? parent.curScope_->symMap() : parent.startSymMap_)
{
    visit_.start(nodePayloadContext_->ast(), root);
    pushFrame(parent.frame());
    setVisitors();

    for (const auto& scope : parent.scopes_)
    {
        scopes_.emplace_back(std::make_unique<SemaScope>(*scope));
        if (scopes_.size() > 1)
            scopes_.back()->setParent(scopes_[scopes_.size() - 2].get());
        else
            scopes_.back()->setParent(nullptr);
    }

    curScope_ = scopes_.empty() ? nullptr : scopes_.back().get();
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

const Ast& Sema::ast() const
{
    return nodePayloadContext_->ast();
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

void Sema::pushFramePopOnPostChild(const SemaFrame& frame, AstNodeRef popAfterChildRef)
{
    pushFrame(frame);
    const size_t before = frames_.size();
    SWC_ASSERT(before > 0);
    deferredPopFrames_.push_back({
        .nodeRef                  = curNodeRef(),
        .childRef                 = popAfterChildRef,
        .onPostNode               = false,
        .expectedFrameCountBefore = before,
        .expectedFrameCountAfter  = before - 1,
    });
}

void Sema::pushFramePopOnPostNode(const SemaFrame& frame, AstNodeRef popNodeRef)
{
    pushFrame(frame);
    const size_t before = frames_.size();
    SWC_ASSERT(before > 0);
    deferredPopFrames_.push_back({
        .nodeRef                  = popNodeRef.isValid() ? popNodeRef : curNodeRef(),
        .childRef                 = AstNodeRef::invalid(),
        .onPostNode               = true,
        .expectedFrameCountBefore = before,
        .expectedFrameCountAfter  = before - 1,
    });
}

void Sema::deferPostNodeAction(AstNodeRef nodeRef, std::function<Result(Sema&, AstNodeRef)> callback)
{
    SWC_ASSERT(nodeRef.isValid());
    SWC_ASSERT(callback);
    deferredPostNodeActions_.push_back({
        .nodeRef  = nodeRef,
        .callback = std::move(callback),
    });
}

SemaScope* Sema::pushScopePopOnPostChild(SemaScopeFlags flags, AstNodeRef popAfterChildRef)
{
    SemaScope*   scope  = pushScope(flags);
    const size_t before = scopes_.size();
    SWC_ASSERT(before > 0);
    deferredPopScopes_.push_back({
        .nodeRef                  = curNodeRef(),
        .childRef                 = popAfterChildRef,
        .onPostNode               = false,
        .expectedScopeCountBefore = before,
        .expectedScopeCountAfter  = before - 1,
    });
    return scope;
}

SemaScope* Sema::pushScopePopOnPostNode(SemaScopeFlags flags, AstNodeRef popNodeRef)
{
    SemaScope*   scope  = pushScope(flags);
    const size_t before = scopes_.size();
    SWC_ASSERT(before > 0);
    deferredPopScopes_.push_back({
        .nodeRef                  = popNodeRef.isValid() ? popNodeRef : curNodeRef(),
        .childRef                 = AstNodeRef::invalid(),
        .onPostNode               = true,
        .expectedScopeCountBefore = before,
        .expectedScopeCountAfter  = before - 1,
    });
    return scope;
}

namespace
{
    const Symbol* guessCurrentSymbol(Sema& sema)
    {
        const AstNodeRef n = sema.visit().root();
        if (sema.hasSymbol(n))
            return &sema.symbolOf(n);
        return sema.topSymMap();
    }
}

Result Sema::waitIdentifier(IdentifierRef idRef, const SourceCodeRef& codeRef)
{
    TaskState& wait = ctx().state();
    wait.kind       = TaskStateKind::SemaWaitIdentifier;
    wait.nodeRef    = curNodeRef();
    wait.codeRef    = codeRef;
    wait.idRef      = idRef;
    return Result::Pause;
}

Result Sema::waitPredefined(IdentifierManager::PredefinedName name, TypeRef& typeRef, const SourceCodeRef& codeRef)
{
    typeRef = typeMgr().runtimeType(name);
    if (typeRef.isValid())
        return Result::Continue;
    return waitIdentifier(idMgr().predefined(name), codeRef);
}

Result Sema::waitCompilerDefined(IdentifierRef idRef, const SourceCodeRef& codeRef)
{
    TaskState& wait = ctx().state();
    wait.kind       = TaskStateKind::SemaWaitCompilerDefined;
    wait.nodeRef    = curNodeRef();
    wait.codeRef    = codeRef;
    wait.idRef      = idRef;
    return Result::Pause;
}

Result Sema::waitImplRegistrations(IdentifierRef idRef, const SourceCodeRef& codeRef)
{
    TaskState& wait = ctx().state();
    wait.kind       = TaskStateKind::SemaWaitImplRegistrations;
    wait.nodeRef    = curNodeRef();
    wait.codeRef    = codeRef;
    wait.idRef      = idRef;
    return Result::Pause;
}

Result Sema::waitDeclared(const Symbol* symbol, const SourceCodeRef& codeRef)
{
    if (!symbol || symbol->isDeclared())
        return Result::Continue;
    TaskState& wait   = ctx().state();
    wait.kind         = TaskStateKind::SemaWaitSymDeclared;
    wait.nodeRef      = curNodeRef();
    wait.codeRef      = codeRef;
    wait.symbol       = symbol;
    wait.waiterSymbol = guessCurrentSymbol(*this);
    return Result::Pause;
}

Result Sema::waitTyped(const Symbol* symbol, const SourceCodeRef& codeRef)
{
    if (!symbol || symbol->isTyped())
        return Result::Continue;
    TaskState& wait   = ctx().state();
    wait.kind         = TaskStateKind::SemaWaitSymTyped;
    wait.nodeRef      = curNodeRef();
    wait.codeRef      = codeRef;
    wait.symbol       = symbol;
    wait.waiterSymbol = guessCurrentSymbol(*this);
    return Result::Pause;
}

Result Sema::waitSemaCompleted(const Symbol* symbol, const SourceCodeRef& codeRef)
{
    if (!symbol || symbol->isSemaCompleted())
        return Result::Continue;
    TaskState& wait   = ctx().state();
    wait.kind         = TaskStateKind::SemaWaitSymSemaCompleted;
    wait.nodeRef      = curNodeRef();
    wait.codeRef      = codeRef;
    wait.symbol       = symbol;
    wait.waiterSymbol = guessCurrentSymbol(*this);
    return Result::Pause;
}

Result Sema::waitCodeGenCompleted(const Symbol* symbol, const SourceCodeRef& codeRef)
{
    if (!symbol || symbol->isCodeGenCompleted())
        return Result::Continue;
    TaskState& wait   = ctx().state();
    wait.kind         = TaskStateKind::SemaWaitSymCodeGenCompleted;
    wait.nodeRef      = curNodeRef();
    wait.codeRef      = codeRef;
    wait.symbol       = symbol;
    wait.waiterSymbol = guessCurrentSymbol(*this);
    return Result::Pause;
}

Result Sema::waitSemaCompleted(const TypeInfo* type, AstNodeRef nodeRef)
{
    if (!type || type->isCompleted(ctx()))
        return Result::Continue;
    TaskState& wait = ctx().state();
    wait.kind       = TaskStateKind::SemaWaitTypeCompleted;
    wait.nodeRef    = nodeRef;
    if (nodeRef.isValid())
        wait.codeRef = node(nodeRef).codeRef();
    wait.symbol       = type->getNotCompletedSymbol(ctx());
    wait.waiterSymbol = guessCurrentSymbol(*this);
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
    const AstNodeIdInfo& info = Ast::nodeIdInfos(node.id());
    return info.semaPreNode(*this, node);
}

Result Sema::postNode(AstNode& node)
{
    const AstNodeRef     nodeRef = curNodeRef();
    const AstNodeIdInfo& info    = Ast::nodeIdInfos(node.id());
    const Result         result  = info.semaPostNode(*this, node);
    if (result == Result::Continue)
    {
        processDeferredPopsPostNode(nodeRef);
        if (nodeRef == curNodeRef())
            RESULT_VERIFY(processDeferredPostNodeActions(nodeRef));
    }
    return result;
}

void Sema::errorCleanupNode(AstNodeRef nodeRef, AstNode& node)
{
    const AstNodeIdInfo& info = Ast::nodeIdInfos(node.id());
    info.semaErrorCleanup(*this, node, nodeRef);
}

Result Sema::preNodeChild(AstNode& node, AstNodeRef& childRef)
{
    if (curScope_->isTopLevel() && (ast().hasFlag(AstFlagsE::GlobalSkip) || !frame().globalCompilerIfEnabled()))
        return Result::SkipChildren;

    const AstNodeIdInfo& info = Ast::nodeIdInfos(node.id());
    RESULT_VERIFY(info.semaPreNodeChild(*this, node, childRef));

    if (curScope_->isTopLevel())
    {
        const AstNode&       child     = ast().node(childRef);
        const AstNodeIdInfo& childInfo = Ast::nodeIdInfos(child.id());
        if (childInfo.hasFlag(AstNodeIdFlagsE::SemaJob))
        {
            const auto job = heapNew<SemaJob>(ctx(), *this, childRef);
            compiler().global().jobMgr().enqueue(*job, JobPriority::Normal, compiler().jobClientId());
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

Result Sema::execResult()
{
    if (!curScope_ && scopes_.empty())
    {
        scopes_.emplace_back(std::make_unique<SemaScope>(SemaScopeFlagsE::TopLevel, nullptr));
        curScope_ = scopes_.back().get();
        curScope_->setSymMap(startSymMap_);
    }

    ctx().state().reset();

    auto semaResult = Result::Continue;
    while (true)
    {
        const AstVisitResult result = visit_.step(ctx());
        if (result == AstVisitResult::Pause)
        {
            semaResult = Result::Pause;
            break;
        }

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

            semaResult = Result::Error;
            break;
        }

        if (result == AstVisitResult::Stop)
        {
            semaResult = Result::Continue;
            break;
        }
    }

    if (semaResult != Result::Pause)
        scopes_.clear();

    return semaResult;
}

JobResult Sema::exec()
{
    return execResult() == Result::Pause ? JobResult::Sleep : JobResult::Done;
}

namespace
{
    bool resolveCompilerDefined(const TaskContext& ctx, JobClientId clientId)
    {
        std::vector<Job*> jobs;
        ctx.global().jobMgr().waitingJobs(jobs, clientId);

        bool doneSomething = false;
        for (const auto job : jobs)
        {
            const TaskState& state = job->ctx().state();
            if (state.kind == TaskStateKind::SemaWaitCompilerDefined)
            {
                // @CompilerNotDefined
                const auto semaJob = job->cast<SemaJob>();
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

        if (compiler.changed())
        {
            compiler.clearChanged();
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

    for (const auto& f : ctx.compiler().files())
    {
        const SourceView& srcView = f->ast().srcView();
        if (srcView.mustSkip())
            continue;
        f->unitTest().verifyUntouchedExpected(ctx, srcView);
    }
}

SWC_END_NAMESPACE();
