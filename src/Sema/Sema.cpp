#include "pch.h"
#include "Sema/Sema.h"
#include "Helpers/SemaError.h"
#include "Main/CompilerInstance.h"
#include "Main/Global.h"
#include "Memory/Heap.h"
#include "Report/DiagnosticDef.h"
#include "Sema/Helpers/SemaInfo.h"
#include "Sema/Helpers/SemaJob.h"
#include "Sema/Helpers/SemaScope.h"
#include "Symbol/LookupResult.h"
#include "Symbol/Symbols.h"
#include "Thread/JobManager.h"
#include "Wmf/Verify.h"

SWC_BEGIN_NAMESPACE()

Sema::Sema(TaskContext& ctx, SemaInfo& semInfo) :
    ctx_(&ctx),
    semaInfo_(&semInfo),
    startSymMap_(semaInfo().moduleNamespace().symMap())
{
    visit_.start(semaInfo_->ast(), semaInfo_->ast().root());
    setVisitors();
    pushFrame({});
}

Sema::Sema(TaskContext& ctx, const Sema& parent, AstNodeRef root) :
    ctx_(&ctx),
    semaInfo_(parent.semaInfo_),
    startSymMap_(parent.curScope_->symMap())

{
    visit_.start(semaInfo_->ast(), root);
    pushFrame(parent.frame());
    setVisitors();
}

void Sema::semaInherit(AstNode& nodeDst, AstNodeRef srcRef)
{
    const AstNode& nodeSrc = node(srcRef);
    nodeDst.semaKindRaw()  = nodeSrc.semaKindRaw();
    nodeDst.setSemaRaw(nodeSrc.semaRaw());
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

void Sema::setVisitors()
{
    visit_.setEnterNodeVisitor([this](AstNode& node) { enterNode(node); });
    visit_.setPreNodeVisitor([this](AstNode& node) { return preNode(node); });
    visit_.setPostNodeVisitor([this](AstNode& node) { return postNode(node); });
    visit_.setPreChildVisitor([this](AstNode& node, AstNodeRef& childRef) { return preChild(node, childRef); });
}

Sema::~Sema() = default;

void Sema::pushFrame(const SemaFrame& frame)
{
    frame_.push_back(frame);
}

void Sema::popFrame()
{
    SWC_ASSERT(!frame_.empty());
    frame_.pop_back();
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

void Sema::enterNode(AstNode& node)
{
    const auto& info = Ast::nodeIdInfos(node.id());

    // Push scope
    if (info.scopeFlags != SemaScopeFlagsE::Zero)
        pushScope(info.scopeFlags);

    info.semaEnterNode(*this, node);
}

AstVisitStepResult Sema::preNode(AstNode& node)
{
    const auto& info = Ast::nodeIdInfos(node.id());
    return info.semaPreNode(*this, node);
}

AstVisitStepResult Sema::postNode(AstNode& node)
{
    const auto& info   = Ast::nodeIdInfos(node.id());
    const auto  result = info.semaPostNode(*this, node);

    // Pop scope once done
    if (result == AstVisitStepResult::Continue)
    {
        if (info.scopeFlags != SemaScopeFlagsE::Zero)
            popScope();
    }

    return result;
}

AstVisitStepResult Sema::preChild(AstNode& node, AstNodeRef& childRef)
{
    if (curScope_->has(SemaScopeFlagsE::TopLevel))
    {
        const AstNode& child = ast().node(childRef);
        const auto&    info  = Ast::nodeIdInfos(child.id());
        if (info.hasFlag(AstNodeIdFlagsE::SemaJob))
        {
            const auto job = heapNew<SemaJob>(ctx(), *this, childRef);
            compiler().global().jobMgr().enqueue(*job, JobPriority::Normal, compiler().jobClientId());
            return AstVisitStepResult::SkipChildren;
        }
    }

    const auto& info = Ast::nodeIdInfos(node.id());
    return info.semaPreChild(*this, node, childRef);
}

AstVisitStepResult Sema::pause(TaskStateKind kind, AstNodeRef nodeRef)
{
    auto& wait   = ctx().state();
    wait.kind    = kind;
    wait.nodeRef = nodeRef;
    return AstVisitStepResult::Pause;
}

namespace
{
    void postProcess(TaskContext& ctx, JobClientId clientId)
    {
        std::vector<Job*> jobs;
        ctx.global().jobMgr().waitingJobs(jobs, clientId);

        for (const auto job : jobs)
        {
            const auto& state = job->ctx().state();
            if (const auto semaJob = job->safeCast<SemaJob>())
            {
                if (state.kind == TaskStateKind::SemaWaitingIdentifier)
                {
                    SemaError::raise(semaJob->sema(), DiagnosticId::sema_err_unknown_identifier, state.nodeRef);
                }
            }
        }

        for (const auto& f : ctx.compiler().files())
        {
            const auto& srcView = f->ast().srcView();
            if (srcView.mustSkip())
                continue;
            f->unitTest().verifyUntouchedExpected(ctx, srcView);
        }
    }
}

void Sema::waitAll(TaskContext& ctx, JobClientId clientId)
{
    auto&       jobMgr   = ctx.global().jobMgr();
    const auto& compiler = ctx.compiler();

    uint64_t lastEpoch = 0;
    while (true)
    {
        jobMgr.waitAll(clientId);

        const uint64_t cur = compiler.semaEpoch();
        if (cur == lastEpoch)
            break;
        lastEpoch = cur;

        jobMgr.wakeAll(clientId);
    }

    postProcess(ctx, clientId);
}

JobResult Sema::exec()
{
    if (!curScope_)
    {
        scopes_.emplace_back(std::make_unique<SemaScope>(SemaScopeFlagsE::TopLevel, nullptr));
        curScope_ = scopes_.back().get();
        curScope_->setSymMap(startSymMap_);
    }

    auto jobResult = JobResult::Done;
    while (true)
    {
        const AstVisitResult result = visit_.step(ctx());
        if (result == AstVisitResult::Pause)
        {
            jobResult = JobResult::Sleep;
            break;
        }

        if (result == AstVisitResult::Stop)
        {
            jobResult = JobResult::Done;
            break;
        }
    }

    if (jobResult == JobResult::Done)
    {
        SWC_ASSERT(scopes_.size() == 1);
        SWC_ASSERT(curScope_ == scopes_.back().get());
        scopes_.clear();
    }

    return jobResult;
}

SWC_END_NAMESPACE()
