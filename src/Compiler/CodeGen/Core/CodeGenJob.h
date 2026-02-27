#pragma once
#include "Compiler/CodeGen/Core/CodeGen.h"
#include "Support/Thread/Job.h"

SWC_BEGIN_NAMESPACE();

class Sema;

class CodeGenJob : public Job
{
public:
    static constexpr JobKind K = JobKind::CodeGen;

    CodeGenJob(const TaskContext& ctx, Sema& sema, SymbolFunction& symbolFunc, AstNodeRef root);
    JobResult   exec();
    Sema&       sema() { return codeGen_->sema(); }
    const Sema& sema() const { return codeGen_->sema(); }

private:
    std::unique_ptr<Sema>    ownedSema_;
    std::unique_ptr<CodeGen> codeGen_;
    SymbolFunction*          symbolFunc_ = nullptr;
    AstNodeRef               root_       = AstNodeRef::invalid();
};

SWC_END_NAMESPACE();
