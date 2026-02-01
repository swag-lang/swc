#include "pch.h"
#include "Compiler/Sema/Helpers/SemaCycle.h"
#include "Compiler/Sema/Core/Sema.h"
#include "Compiler/Sema/Core/SemaJob.h"
#include "Compiler/Sema/Helpers/SemaError.h"
#include "Main/Global.h"
#include "Support/Report/DiagnosticDef.h"
#include "Support/Thread/JobManager.h"

SWC_BEGIN_NAMESPACE();

void SemaCycle::addNodeIfNeeded(const Symbol* sym)
{
    if (!graph_.adj.contains(sym))
        graph_.adj[sym] = {};
}

void SemaCycle::addEdge(const Symbol* from, const Symbol* to, SemaJob* job, const TaskState& state)
{
    addNodeIfNeeded(from);
    addNodeIfNeeded(to);

    graph_.adj[from].push_back(to);

    auto& loc = graph_.edges[{from, to}];
    if (!loc.job)
    {
        loc.job     = job;
        loc.nodeRef = state.nodeRef;
    }
}

void SemaCycle::reportCycle(const std::vector<const Symbol*>& cycle)
{
    for (const auto sym : cycle)
        const_cast<Symbol*>(sym)->addFlag(SymbolFlagsE::Ignored);

    const auto firstSym = cycle[0];
    const auto nextSym  = cycle.size() > 1 ? cycle[1] : cycle[0];
    const auto itLoc    = graph_.edges.find({firstSym, nextSym});
    if (itLoc == graph_.edges.end())
        return;

    auto diag = SemaError::report(itLoc->second.job->sema(), DiagnosticId::sema_err_cyclic_dependency, firstSym->srcViewRef(), firstSym->tokRef());
    diag.addArgument(Diagnostic::ARG_SYM, firstSym->name(*ctx_));

    for (size_t i = 0; i < cycle.size(); i++)
    {
        const auto sym    = cycle[i];
        const auto next   = cycle[(i + 1) % cycle.size()];
        const auto itEdge = graph_.edges.find({sym, next});
        if (itEdge == graph_.edges.end())
            continue;
        Sema& sema = itEdge->second.job->sema();

        diag.addNote(DiagnosticId::sema_note_cyclic_dependency_link);
        const SourceCodeLocation loc = sema.node(itEdge->second.nodeRef).locationWithChildren(sema.ctx(), sema.ast());
        diag.last().addSpan(loc, next->name(*ctx_), DiagnosticSeverity::Note);
    }

    diag.report(*ctx_);
}

void SemaCycle::findCycles(const Symbol* v, std::vector<const Symbol*>& stack, SymbolSet& visited, SymbolSet& onStack)
{
    visited.insert(v);
    onStack.insert(v);
    stack.push_back(v);

    const auto it = graph_.adj.find(v);
    if (it != graph_.adj.end())
    {
        for (const auto w : it->second)
        {
            if (onStack.contains(w))
            {
                std::vector<const Symbol*> cycle;
                const auto                 itCyc = std::ranges::find(stack, w);
                cycle.insert(cycle.end(), itCyc, stack.end());
                reportCycle(cycle);
            }
            else if (!visited.contains(w))
            {
                findCycles(w, stack, visited, onStack);
            }
        }
    }

    stack.pop_back();
    onStack.erase(v);
}

void SemaCycle::detectAndReportCycles()
{
    SymbolSet                  visited;
    SymbolSet                  onStack;
    std::vector<const Symbol*> stack;

    for (const auto& key : graph_.adj | std::views::keys)
    {
        if (!visited.contains(key))
            findCycles(key, stack, visited, onStack);
    }
}

void SemaCycle::check(TaskContext& ctx, JobClientId clientId)
{
    std::vector<Job*> jobs;
    ctx.global().jobMgr().waitingJobs(jobs, clientId);

    ctx_ = &ctx;

    for (const auto job : jobs)
    {
        const auto semaJob = job->safeCast<SemaJob>();
        if (!semaJob)
            continue;

        const auto& state = job->ctx().state();
        if (state.waiterSymbol && state.symbol)
            addEdge(state.waiterSymbol, state.symbol, semaJob, state);
    }

    detectAndReportCycles();

    for (const auto job : jobs)
    {
        const auto& state = job->ctx().state();
        if (state.symbol && state.symbol->isIgnored())
            continue;

        const auto semaJob = job->safeCast<SemaJob>();
        if (!semaJob)
            continue;

        switch (state.kind)
        {
            case TaskStateKind::SemaWaitIdentifier:
            {
                auto diag = SemaError::report(semaJob->sema(), DiagnosticId::sema_err_unknown_symbol, state.srcViewRef, state.tokRef);
                diag.addArgument(Diagnostic::ARG_SYM, state.idRef);
                diag.report(ctx);
                break;
            }

            case TaskStateKind::SemaWaitImplRegistrations:
            {
                // This is a global barrier wait (no symbol dependency). If it reaches cycle detection,
                // something prevents impl registrations from completing.
                auto diag = SemaError::report(semaJob->sema(), DiagnosticId::sema_err_wait_impl_registration, state.srcViewRef, state.tokRef);
                diag.report(ctx);
                break;
            }

            case TaskStateKind::SemaWaitSymDeclared:
            {
                SWC_ASSERT(state.symbol);
                auto diag = SemaError::report(semaJob->sema(), DiagnosticId::sema_err_wait_sym_declared, state.srcViewRef, state.tokRef);
                diag.addArgument(Diagnostic::ARG_SYM, state.symbol->name(ctx));
                diag.report(ctx);
                break;
            }

            case TaskStateKind::SemaWaitSymTyped:
            {
                SWC_ASSERT(state.symbol);
                auto diag = SemaError::report(semaJob->sema(), DiagnosticId::sema_err_wait_sym_typed, state.srcViewRef, state.tokRef);
                diag.addArgument(Diagnostic::ARG_SYM, state.symbol->name(ctx));
                diag.report(ctx);
                break;
            }

            case TaskStateKind::SemaWaitSymCompleted:
            case TaskStateKind::SemaWaitTypeCompleted:
            {
                SWC_ASSERT(state.symbol);
                auto diag = SemaError::report(semaJob->sema(), DiagnosticId::sema_err_wait_sym_completed, state.srcViewRef, state.tokRef);
                diag.addArgument(Diagnostic::ARG_SYM, state.symbol->name(ctx));
                diag.report(ctx);
                break;
            }

            default:
                SWC_UNREACHABLE();
        }
    }
}

SWC_END_NAMESPACE();
