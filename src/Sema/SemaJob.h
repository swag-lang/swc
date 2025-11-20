#pragma once
#include "Parser/AstVisit.h"
#include "Thread/Job.h"

SWC_BEGIN_NAMESPACE()

class SemaJob : public Job
{
    Ast*     ast_ = nullptr;
    AstVisit visit_;

    AstVisitStepResult preNode(AstNode& node);
    AstVisitStepResult postNode(AstNode& node);
    AstNodeRef         preChild(AstNode& node, AstNodeRef childRef);

    JobResult exec();

public:
    SemaJob(const TaskContext& ctx, Ast* ast, AstNodeRef root);

    const Ast&              ast() const { return *ast_; }
    const AstVisit&         visit() const { return visit_; }
    const CompilerInstance& compiler() const { return ctx().compiler(); }
    const ConstantManager&  constMgr() const { return compiler().constMgr(); }
    const TypeManager&      typeMgr() const { return compiler().typeMgr(); }
};

SWC_END_NAMESPACE()
