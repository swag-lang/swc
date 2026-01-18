#include "pch.h"
#include "Sema/Core/Sema.h"
#include "Main/CompilerInstance.h"
#include "Main/Global.h"
#include "Memory/Heap.h"
#include "Sema/Constant/ConstantManager.h"
#include "Sema/Core/SemaInfo.h"
#include "Sema/Core/SemaJob.h"
#include "Sema/Core/SemaScope.h"
#include "Sema/Helpers/SemaCycle.h"
#include "Sema/Helpers/SemaError.h"
#include "Sema/Symbol/Symbols.h"
#include "Thread/JobManager.h"
#include "Wmf/Verify.h"

SWC_BEGIN_NAMESPACE();

Sema::Sema(TaskContext& ctx, SemaInfo& semInfo, bool declPass) :
    ctx_(&ctx),
    semaInfo_(&semInfo),
    startSymMap_(semaInfo().moduleNamespace().symMap()),
    declPass_(declPass)
{
    visit_.start(semaInfo_->ast(), semaInfo_->ast().root());
    setVisitors();
    pushFrame({});
}

Sema::Sema(TaskContext& ctx, const Sema& parent, AstNodeRef root) :
    ctx_(&ctx),
    semaInfo_(parent.semaInfo_),
    startSymMap_(parent.curScope_ ? parent.curScope_->symMap() : parent.startSymMap_)
{
    visit_.start(semaInfo_->ast(), root);
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
    return semaInfo_->ast();
}

Utf8 Sema::fileName() const
{
    return ast().srcView().file()->path().string();
}

const Ast& Sema::ast() const
{
    return semaInfo_->ast();
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

Result Sema::waitIdentifier(IdentifierRef idRef, SourceViewRef srcViewRef, TokenRef tokRef)
{
    TaskState& wait = ctx().state();
    wait.kind       = TaskStateKind::SemaWaitIdentifier;
    wait.nodeRef    = curNodeRef();
    wait.srcViewRef = srcViewRef;
    wait.tokRef     = tokRef;
    wait.idRef      = idRef;
    return Result::Pause;
}

Result Sema::waitCompilerDefined(IdentifierRef idRef, SourceViewRef srcViewRef, TokenRef tokRef)
{
    TaskState& wait = ctx().state();
    wait.kind       = TaskStateKind::SemaWaitCompilerDefined;
    wait.nodeRef    = curNodeRef();
    wait.srcViewRef = srcViewRef;
    wait.tokRef     = tokRef;
    wait.idRef      = idRef;
    return Result::Pause;
}

Result Sema::waitDeclared(const Symbol* symbol, SourceViewRef srcViewRef, TokenRef tokRef)
{
    TaskState& wait   = ctx().state();
    wait.kind         = TaskStateKind::SemaWaitSymDeclared;
    wait.nodeRef      = curNodeRef();
    wait.srcViewRef   = srcViewRef;
    wait.tokRef       = tokRef;
    wait.symbol       = symbol;
    wait.waiterSymbol = guessCurrentSymbol(*this);
    return Result::Pause;
}

Result Sema::waitTyped(const Symbol* symbol, SourceViewRef srcViewRef, TokenRef tokRef)
{
    TaskState& wait   = ctx().state();
    wait.kind         = TaskStateKind::SemaWaitSymTyped;
    wait.nodeRef      = curNodeRef();
    wait.srcViewRef   = srcViewRef;
    wait.tokRef       = tokRef;
    wait.symbol       = symbol;
    wait.waiterSymbol = guessCurrentSymbol(*this);
    return Result::Pause;
}

Result Sema::waitCompleted(const Symbol* symbol, SourceViewRef srcViewRef, TokenRef tokRef)
{
    TaskState& wait   = ctx().state();
    wait.kind         = TaskStateKind::SemaWaitSymCompleted;
    wait.nodeRef      = curNodeRef();
    wait.srcViewRef   = srcViewRef;
    wait.tokRef       = tokRef;
    wait.symbol       = symbol;
    wait.waiterSymbol = guessCurrentSymbol(*this);
    return Result::Pause;
}

Result Sema::waitCompleted(const TypeInfo* type, AstNodeRef nodeRef)
{
    TaskState& wait   = ctx().state();
    wait.kind         = TaskStateKind::SemaWaitTypeCompleted;
    wait.nodeRef      = nodeRef;
    wait.symbol       = type->getSymbolDependency(ctx());
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
    pushDebugInfo();
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
    const AstNodeIdInfo& info = Ast::nodeIdInfos(node.id());
    return info.semaPostDeclChild(*this, node, childRef);
}

Result Sema::postDecl(AstNode& node)
{
    const AstNodeIdInfo& info   = Ast::nodeIdInfos(node.id());
    const Result         result = info.semaPostDecl(*this, node);
    popDebugInfo(node, result);
    return result;
}

Result Sema::preNode(AstNode& node)
{
    pushDebugInfo();
    const AstNodeIdInfo& info = Ast::nodeIdInfos(node.id());
    return info.semaPreNode(*this, node);
}

Result Sema::postNode(AstNode& node)
{
    const AstNodeIdInfo& info   = Ast::nodeIdInfos(node.id());
    const Result         result = info.semaPostNode(*this, node);
    popDebugInfo(node, result);
    return result;
}

Result Sema::preNodeChild(AstNode& node, AstNodeRef& childRef)
{
    if (curScope_->isTopLevel())
    {
        const AstNode&       child = ast().node(childRef);
        const AstNodeIdInfo& info  = Ast::nodeIdInfos(child.id());
        if (info.hasFlag(AstNodeIdFlagsE::SemaJob))
        {
            const auto job = heapNew<SemaJob>(ctx(), *this, childRef);
            compiler().global().jobMgr().enqueue(*job, JobPriority::Normal, compiler().jobClientId());
            return Result::SkipChildren;
        }
    }

    const AstNodeIdInfo& info = Ast::nodeIdInfos(node.id());
    return info.semaPreNodeChild(*this, node, childRef);
}

Result Sema::postNodeChild(AstNode& node, AstNodeRef& childRef)
{
    const AstNodeIdInfo& info = Ast::nodeIdInfos(node.id());
    return info.semaPostNodeChild(*this, node, childRef);
}

void Sema::pushDebugInfo()
{
#if SWC_HAS_SEMA_DEBUG_INFO
    if (enteringState())
    {
        nodeStack_.push_back({.scopeCount = scopes_.size(), .frameCount = frames_.size()});
    }
#endif
}

void Sema::popDebugInfo(const AstNode& node, Result result)
{
#if SWC_HAS_SEMA_DEBUG_INFO
    if (result == Result::Continue && node.isNot(AstNodeId::File) && node.isNot(AstNodeId::CompilerGlobal))
    {
        SWC_ASSERT(!nodeStack_.empty());
        const auto& last = nodeStack_.back();
        SWC_ASSERT(scopes_.size() == last.scopeCount);
        SWC_ASSERT(frames_.size() == last.frameCount);
        nodeStack_.pop_back();
    }
#endif
}

JobResult Sema::exec()
{
    if (!curScope_ && scopes_.empty())
    {
        scopes_.emplace_back(std::make_unique<SemaScope>(SemaScopeFlagsE::TopLevel, nullptr));
        curScope_ = scopes_.back().get();
        curScope_->setSymMap(startSymMap_);
    }

    ctx().state().reset();

    JobResult jobResult;
    while (true)
    {
        const AstVisitResult result = visit_.step(ctx());
        if (result == AstVisitResult::Pause)
        {
            jobResult = JobResult::Sleep;
            break;
        }

        if (result == AstVisitResult::Error)
        {
            jobResult = JobResult::Done;
            break;
        }

        if (result == AstVisitResult::Stop)
        {
            jobResult = JobResult::Done;
            break;
        }
    }

    if (jobResult == JobResult::Done)
        scopes_.clear();

    return jobResult;
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
