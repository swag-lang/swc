#pragma once
#include "Support/Thread/Job.h"

SWC_BEGIN_NAMESPACE();

class CodeGen;
class NodePayload;
class Sema;

class CodeGenJob : public Job
{
public:
    static constexpr auto K = JobKind::CodeGen;

    CodeGenJob(const TaskContext& ctx, Sema& sema, SymbolFunction& symbolFunc, AstNodeRef root);
    JobResult   exec();
    Sema&       sema() { return *ownedSema_; }
    const Sema& sema() const { return *ownedSema_; }

private:
    void initSemaAndCodeGen();

    std::unique_ptr<Sema>    ownedSema_;
    std::unique_ptr<CodeGen> codeGen_;
    SymbolFunction*          symbolFunc_      = nullptr;
    NodePayload*             nodePayloadCtx_  = nullptr;
    AstNodeRef               root_            = AstNodeRef::invalid();
};

SWC_END_NAMESPACE();
