#pragma once
#include "Support/Thread/Job.h"

SWC_BEGIN_NAMESPACE();

class Sema;
class SymbolFunction;

class CodeGenJob : public Job
{
public:
    static constexpr JobKind K = JobKind::CodeGen;

    CodeGenJob(const TaskContext& ctx, Sema& sema, SymbolFunction& symbolFunc, AstNodeRef root);
    JobResult   exec();
    Sema&       sema() { return *SWC_CHECK_NOT_NULL(sema_); }
    const Sema& sema() const { return *SWC_CHECK_NOT_NULL(sema_); }

private:
    Sema*           sema_       = nullptr;
    SymbolFunction* symbolFunc_ = nullptr;
    AstNodeRef      root_       = AstNodeRef::invalid();
};

SWC_END_NAMESPACE();
