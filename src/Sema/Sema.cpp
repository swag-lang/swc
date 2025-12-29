#include "pch.h"
#include "Sema/Sema.h"
#include "Helpers/SemaError.h"
#include "Main/CompilerInstance.h"
#include "Main/Global.h"
#include "Memory/Heap.h"
#include "Report/DiagnosticDef.h"
#include "Sema/Constant/ConstantManager.h"
#include "Sema/Helpers/SemaInfo.h"
#include "Sema/Helpers/SemaJob.h"
#include "Sema/Helpers/SemaScope.h"
#include "Symbol/Symbols.h"
#include "Thread/JobManager.h"
#include "Wmf/Verify.h"

SWC_BEGIN_NAMESPACE()

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
    startSymMap_(parent.curScope_->symMap())

{
    visit_.start(semaInfo_->ast(), root);
    pushFrame(parent.frame());
    setVisitors();
}

Sema::~Sema() = default;

void Sema::semaInherit(AstNode& nodeDst, AstNodeRef srcRef)
{
    const AstNode& nodeSrc = node(srcRef);
    nodeDst.semaBits()     = nodeSrc.semaBits();
    nodeDst.setSemaRef(nodeSrc.semaRef());
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
    if (declPass_)
    {
        visit_.setPreNodeVisitor([this](AstNode& node) { return preDecl(node); });
        visit_.setPreChildVisitor([this](AstNode& node, AstNodeRef& childRef) { return preDeclChild(node, childRef); });
        visit_.setPostNodeVisitor([this](AstNode& node) { return postDecl(node); });
    }
    else
    {
        visit_.setEnterNodeVisitor([this](AstNode& node) { enterNode(node); });
        visit_.setPreNodeVisitor([this](AstNode& node) { return preNode(node); });
        visit_.setPreChildVisitor([this](AstNode& node, AstNodeRef& childRef) { return preNodeChild(node, childRef); });
        visit_.setPostNodeVisitor([this](AstNode& node) { return postNode(node); });
    }
}

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
    const AstNodeIdInfo& info = Ast::nodeIdInfos(node.id());
    info.semaEnterNode(*this, node);
}

AstVisitStepResult Sema::preDecl(AstNode& node)
{
    const AstNodeIdInfo&     info   = Ast::nodeIdInfos(node.id());
    const AstVisitStepResult result = info.semaPreDecl(*this, node);
    return result;
}

AstVisitStepResult Sema::preDeclChild(AstNode& node, AstNodeRef& childRef)
{
    const AstNodeIdInfo& info = Ast::nodeIdInfos(node.id());
    return info.semaPreDeclChild(*this, node, childRef);
}

AstVisitStepResult Sema::postDecl(AstNode& node)
{
    const AstNodeIdInfo&     info   = Ast::nodeIdInfos(node.id());
    const AstVisitStepResult result = info.semaPostDecl(*this, node);
    return result;
}

AstVisitStepResult Sema::preNode(AstNode& node)
{
    const AstNodeIdInfo&     info   = Ast::nodeIdInfos(node.id());
    const AstVisitStepResult result = info.semaPreNode(*this, node);
    return result;
}

AstVisitStepResult Sema::preNodeChild(AstNode& node, AstNodeRef& childRef)
{
    if (curScope_->hasFlag(SemaScopeFlagsE::TopLevel))
    {
        const AstNode&       child = ast().node(childRef);
        const AstNodeIdInfo& info  = Ast::nodeIdInfos(child.id());
        if (info.hasFlag(AstNodeIdFlagsE::SemaJob))
        {
            const auto job = heapNew<SemaJob>(ctx(), *this, childRef);
            compiler().global().jobMgr().enqueue(*job, JobPriority::Normal, compiler().jobClientId());
            return AstVisitStepResult::SkipChildren;
        }
    }

    const AstNodeIdInfo& info = Ast::nodeIdInfos(node.id());
    return info.semaPreNodeChild(*this, node, childRef);
}

AstVisitStepResult Sema::postNode(AstNode& node)
{
    const AstNodeIdInfo&     info   = Ast::nodeIdInfos(node.id());
    const AstVisitStepResult result = info.semaPostNode(*this, node);
    return result;
}

AstVisitStepResult Sema::waitIdentifier(IdentifierRef idRef)
{
    TaskState& wait = ctx().state();
    wait.kind       = TaskStateKind::SemaWaitingIdentifier;
    wait.nodeRef    = curNodeRef();
    wait.idRef      = idRef;
    return AstVisitStepResult::Pause;
}

AstVisitStepResult Sema::waitCompilerDefined(IdentifierRef idRef)
{
    TaskState& wait = ctx().state();
    wait.kind       = TaskStateKind::SemaWaitingCompilerDefined;
    wait.nodeRef    = curNodeRef();
    wait.idRef      = idRef;
    return AstVisitStepResult::Pause;
}

AstVisitStepResult Sema::waitComplete(const Symbol* symbol)
{
    TaskState& wait = ctx().state();
    wait.kind       = TaskStateKind::SemaWaitingComplete;
    wait.nodeRef    = curNodeRef();
    wait.symbol     = symbol;
    return AstVisitStepResult::Pause;
}

AstVisitStepResult Sema::waitDeclared()
{
    TaskState& wait = ctx().state();
    wait.kind       = TaskStateKind::SemaWaitingDeclared;
    wait.nodeRef    = curNodeRef();
    return AstVisitStepResult::Pause;
}

namespace
{
    void postPass(TaskContext& ctx, JobClientId clientId)
    {
        std::vector<Job*> jobs;
        ctx.global().jobMgr().waitingJobs(jobs, clientId);

        for (const auto job : jobs)
        {
            const TaskState& state = job->ctx().state();
            if (const auto semaJob = job->safeCast<SemaJob>())
            {
                switch (state.kind)
                {
                    case TaskStateKind::SemaWaitingIdentifier:
                    {
                        SemaError::raise(semaJob->sema(), DiagnosticId::sema_err_unknown_identifier, state.nodeRef);
                        break;
                    }
                    case TaskStateKind::SemaWaitingCompilerDefined:
                    {
                        // No error for compiler defined
                        break;
                    }
                    case TaskStateKind::SemaWaitingComplete:
                    {
                        if (state.symbol)
                        {
                            auto diag = SemaError::report(semaJob->sema(), DiagnosticId::sema_err_unsolved_symbol, state.nodeRef);
                            diag.addArgument(Diagnostic::ARG_SYM, state.symbol->name(ctx));
                            diag.report(ctx);
                        }
                        else
                        {
                            SemaError::raise(semaJob->sema(), DiagnosticId::sema_err_unsolved_identifier, state.nodeRef);
                        }
                        break;
                    }
                    case TaskStateKind::SemaWaitingDeclared:
                        SemaError::raise(semaJob->sema(), DiagnosticId::sema_err_unsolved_identifier, state.nodeRef);
                        break;
                    default:
                        break;
                }
            }
        }

        for (const auto& f : ctx.compiler().files())
        {
            const SourceView& srcView = f->ast().srcView();
            if (srcView.mustSkip())
                continue;
            f->unitTest().verifyUntouchedExpected(ctx, srcView);
        }
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

        std::vector<Job*> jobs;
        jobMgr.waitingJobs(jobs, clientId);

        // If we are waiting for a symbol inside a #defined, then we must not trigger
        // an error and just force the evaluation to false.
        bool doneSomething = false;
        for (const auto job : jobs)
        {
            auto& state = job->ctx().state();
            if (state.kind == TaskStateKind::SemaWaitingCompilerDefined)
            {
                if (const auto semaJob = job->safeCast<SemaJob>())
                {
                    // @CompilerNotDefined
                    semaJob->sema().setConstant(state.nodeRef, semaJob->sema().cstMgr().cstFalse());
                    state.reset();
                    doneSomething = true;
                }
            }
        }

        if (doneSomething)
        {
            jobMgr.wakeAll(clientId);
            continue;
        }

        break;
    }

    postPass(ctx, clientId);
}

JobResult Sema::exec()
{
    if (!curScope_)
    {
        scopes_.emplace_back(std::make_unique<SemaScope>(SemaScopeFlagsE::TopLevel, nullptr));
        curScope_ = scopes_.back().get();
        curScope_->setSymMap(startSymMap_);
    }

    JobResult jobResult;
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
        scopes_.clear();
    return jobResult;
}

SWC_END_NAMESPACE()
