#pragma once
#include "Support/Core/RefTypes.h"
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
    JobResult   exec() override;
    Sema&       sema() { return *ownedSema_; }
    const Sema& sema() const { return *ownedSema_; }
    // The semantic and code-generation state exists only while the job runs. A finished job
    // has released it, so a diagnostic that walks the job list reads nullptr here.
    Sema*       trySema() { return ownedSema_.get(); }
    const Sema* trySema() const { return ownedSema_.get(); }

private:
    JobResult execImpl();
    void      initSemaAndCodeGen();
    void      releaseSemaAndCodeGen();

    std::unique_ptr<Sema>    ownedSema_;
    std::unique_ptr<CodeGen> codeGen_;
    SymbolFunction*          symbolFunc_     = nullptr;
    NodePayload*             nodePayloadCtx_ = nullptr;
    AstNodeRef               root_           = AstNodeRef::invalid();
};

SWC_END_NAMESPACE();
