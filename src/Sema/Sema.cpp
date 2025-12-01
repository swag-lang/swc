#include "pch.h"
#include "Sema/Sema.h"
#include "Main/Global.h"
#include "Sema/SemaInfo.h"
#include "Sema/SemaJob.h"
#include "Symbol/Decls.h"
#include "Symbol/Scope.h"
#include "Thread/JobManager.h"

SWC_BEGIN_NAMESPACE()

Sema::Sema(TaskContext& ctx, SemaInfo& semCtx) :
    ctx_(&ctx),
    semaInfo_(&semCtx)
{
    visit_.start(semaInfo_->ast(), semaInfo_->ast().root());
    setVisitors();
}

Sema::Sema(TaskContext& ctx, const Sema& parent, AstNodeRef root) :
    ctx_(&ctx),
    semaInfo_(parent.semaInfo_),
    currentScope_(parent.currentScope_)
{
    visit_.start(semaInfo_->ast(), root);
    setVisitors();
}

Ast& Sema::ast()
{
    return semaInfo_->ast();
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

Scope* Sema::pushScope(ScopeFlags flags)
{
    Scope* parent = currentScope_;
    scopes_.emplace_back(std::make_unique<Scope>(flags, parent));
    Scope* scope = scopes_.back().get();

    if (!rootScope_)
    {
        rootScope_ = scope;
        rootScope_->setDeclContext(ctx_->compiler().moduleDecl());
    }
    else
    {
        scope->setDeclContext(parent->declContext());
    }

    currentScope_ = scope;
    return scope;
}

void Sema::popScope()
{
    SWC_ASSERT(currentScope_);
    currentScope_ = currentScope_->parent();
    scopes_.pop_back();
}

void Sema::enterNode(AstNode& node)
{
    const auto& info = Ast::nodeIdInfos(node.id());

    // Push scope
    if (info.scopeFlags != ScopeFlagsE::Zero)
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
        if (info.scopeFlags != ScopeFlagsE::Zero)
            popScope();
    }

    return result;
}

AstVisitStepResult Sema::preChild(AstNode& node, AstNodeRef& childRef)
{
    if (currentScope_->has(ScopeFlagsE::TopLevel))
    {
        const AstNode& child = ast().node(childRef);
        const auto&    info  = Ast::nodeIdInfos(child.id());
        if (info.hasFlag(AstNodeIdFlagsE::SemaJob))
        {
            const auto job = std::make_shared<SemaJob>(ctx(), *this, childRef);
            compiler().global().jobMgr().enqueue(job, JobPriority::Normal, compiler().jobClientId());
            return AstVisitStepResult::SkipChildren;
        }
    }

    const auto& info = Ast::nodeIdInfos(node.id());
    return info.semaPreChild(*this, node, childRef);
}

JobResult Sema::exec()
{
    while (true)
    {
        const auto result = visit_.step();
        if (result == AstVisitResult::Pause)
            return JobResult::Sleep;
        if (result == AstVisitResult::Stop)
            return JobResult::Done;
    }
}

SWC_END_NAMESPACE()
