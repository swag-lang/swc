#include "pch.h"
#include "Sema/Sema.h"
#include "Main/Global.h"
#include "Sema/SemaJob.h"
#include "Symbol/Scope.h"
#include "Thread/JobManager.h"

SWC_BEGIN_NAMESPACE()

Sema::Sema(TaskContext& ctx, Ast* ast) :
    ctx_(&ctx),
    ast_(ast)
{
    visit_.start(*ast, ast->root());
    visit_.setPreNodeVisitor([this](AstNode& node) { return preNode(node); });
    visit_.setPostNodeVisitor([this](AstNode& node) { return postNode(node); });
    visit_.setPreChildVisitor([this](AstNode& node, AstNodeRef& childRef) { return preChild(node, childRef); });
}

Sema::Sema(TaskContext& ctx, const Sema& parent, AstNodeRef root) :
    ctx_(&ctx),
    ast_(parent.ast_),
    currentScope_(parent.currentScope_)
{
    visit_.start(*ast_, root);
    visit_.setPreNodeVisitor([this](AstNode& node) { return preNode(node); });
    visit_.setPostNodeVisitor([this](AstNode& node) { return postNode(node); });
    visit_.setPreChildVisitor([this](AstNode& node, AstNodeRef& childRef) { return preChild(node, childRef); });
}

Sema::~Sema() = default;

Scope* Sema::pushScope(ScopeKind kind)
{
    Scope* parent = currentScope_;
    scopes_.emplace_back(std::make_unique<Scope>(kind, parent));
    Scope* scope = scopes_.back().get();

    if (!rootScope_)
        rootScope_ = scope;
    currentScope_ = scope;

    return scope;
}

void Sema::popScope()
{
    SWC_ASSERT(currentScope_);
    currentScope_ = currentScope_->parent();
}

AstVisitStepResult Sema::preNode(AstNode& node)
{
    const auto& info = Ast::nodeIdInfos(node.id());
    if (!info.semaPreNode)
        return AstVisitStepResult::Continue;
    return info.semaPreNode(*this, node);
}

AstVisitStepResult Sema::postNode(AstNode& node)
{
    const auto& info = Ast::nodeIdInfos(node.id());
    if (!info.semaPostNode)
        return AstVisitStepResult::Continue;
    return info.semaPostNode(*this, node);
}

AstVisitStepResult Sema::preChild(AstNode& node, AstNodeRef& childRef)
{
    const auto& info = Ast::nodeIdInfos(node.id());

    const AstNode& childPtr = ast().node(childRef);
    switch (childPtr.id())
    {
        case AstNodeId::CompilerDiagnostic:
        case AstNodeId::CompilerIf:
        {
            if (visit().root() == ast().root())
            {
                const auto job = std::make_shared<SemaJob>(ctx(), *this, childRef);
                compiler().global().jobMgr().enqueue(job, JobPriority::Normal, compiler().jobClientId());
                return AstVisitStepResult::SkipChildren;
            }

            break;
        }

        default:
            break;
    }

    if (!info.semaPreChild)
        return AstVisitStepResult::Continue;
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
