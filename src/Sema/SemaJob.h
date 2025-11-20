#pragma once
#include "Parser/Ast.h"
#include "Parser/AstVisit.h"
#include "Thread/Job.h"

SWC_BEGIN_NAMESPACE()

class SemaJob : public Job
{
    Ast*     ast_ = nullptr;
    AstVisit visit_;

    AstVisitStepResult preNode(AstNode& node);
    AstVisitStepResult postNode(AstNode& node);
    AstVisitStepResult preChild(AstNode& node, AstNodeRef& childRef);

    JobResult exec();

public:
    SemaJob(const TaskContext& ctx, Ast* ast, AstNodeRef root);

    Ast&                    ast() { return *ast_; }
    const Ast&              ast() const { return *ast_; }
    AstVisit&               visit() { return visit_; }
    const AstVisit&         visit() const { return visit_; }
    CompilerInstance&       compiler() { return ctx().compiler(); }
    const CompilerInstance& compiler() const { return ctx().compiler(); }
    ConstantManager&        constMgr() { return compiler().constMgr(); }
    const ConstantManager&  constMgr() const { return compiler().constMgr(); }
    TypeManager&            typeMgr() { return compiler().typeMgr(); }
    const TypeManager&      typeMgr() const { return compiler().typeMgr(); }
    AstNode*                node(AstNodeRef nodeRef) { return ast().node(nodeRef); }
    const AstNode*          node(AstNodeRef nodeRef) const { return ast().node(nodeRef); }
    const Token&            token(TokenRef tokenRef) const { return visit_.currentLex().token(tokenRef); }
};

SWC_END_NAMESPACE()
