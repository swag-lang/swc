#pragma once
#include "Parser/Ast.h"
#include "Parser/AstVisit.h"
#include "Report/DiagnosticDef.h"
#include "Sema/Sema.h"
#include "Thread/Job.h"

SWC_BEGIN_NAMESPACE()

class SemaJob : public Job
{
    Sema sema_;

    JobResult exec();

public:
    SemaJob(TaskContext& ctx, Ast* ast, AstNodeRef root);

    Sema&       sema() { return sema_; }
    const Sema& sema() const { return sema_; }
};

SWC_END_NAMESPACE()
