#pragma once
#include "Support/Core/RefTypes.h"
#include "Support/Core/SmallVector.h"
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
    JobResult exec() override;

#if SWC_DEV_MODE
    Utf8 statsLabel() const override;
#endif

    Sema&       sema() { return *ownedSema_; }
    const Sema& sema() const { return *ownedSema_; }

    // Finished jobs release their state. Diagnostics walking the retained job
    // list therefore need this nullable accessor.
    Sema*       trySema() { return ownedSema_.get(); }
    const Sema* trySema() const { return ownedSema_.get(); }

private:
    JobResult execImpl();
    void      initSemaAndCodeGen();
    void      releaseSemaAndCodeGen();

    JobResult waitLeafCalleesLowered(std::span<SymbolFunction* const> callees);

    std::unique_ptr<Sema>    ownedSema_;
    std::unique_ptr<CodeGen> codeGen_;

    SymbolFunction* symbolFunc_          = nullptr;
    NodePayload*    nodePayloadCtx_      = nullptr;
    AstNodeRef      root_                = AstNodeRef::invalid();
    bool            readsCalleeClobbers_ = false;
    bool            loweringStarted_     = false;
    bool            bodyEmitted_         = false;

    // The functions the lowered body calls directly, read while the job still owned it. An
    // optimized body is emitted once the leaf candidates among them are lowered (see
    // SymbolFunction::resolveCallClobbers).
    SmallVector<SymbolFunction*> directCallees_;
};

SWC_END_NAMESPACE();
