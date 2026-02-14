#include "pch.h"
#include "Compiler/CodeGen/Core/CodeGenJob.h"
#include "Compiler/CodeGen/Core/CodeGen.h"
#include "Compiler/Sema/Core/Sema.h"
#include "Compiler/Sema/Symbol/Symbol.Function.h"

SWC_BEGIN_NAMESPACE();

CodeGenJob::CodeGenJob(const TaskContext& ctx, Sema& sema, SymbolFunction& symbolFunc, AstNodeRef root) :
    Job(ctx, JobKind::CodeGen),
    sema_(&sema),
    symbolFunc_(&symbolFunc),
    root_(root)
{
    func = [this] {
        return exec();
    };
}

JobResult CodeGenJob::exec()
{
    SWC_ASSERT(sema_);
    SWC_ASSERT(symbolFunc_);

    CodeGen      codeGen(*sema_);
    const Result result = codeGen.exec(*symbolFunc_, root_);
    if (result == Result::Continue)
    {
        symbolFunc_->setCompleted(ctx());
        return JobResult::Done;
    }

    if (result == Result::Pause)
        return JobResult::Sleep;

    return JobResult::Done;
}

SWC_END_NAMESPACE();
