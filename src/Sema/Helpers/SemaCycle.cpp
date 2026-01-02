#include "pch.h"
#include "Sema/Helpers/SemaCycle.h"
#include "Main/CompilerInstance.h"
#include "Main/Global.h"
#include "Report/DiagnosticDef.h"
#include "Sema/Core/Sema.h"
#include "Sema/Helpers/SemaError.h"
#include "Sema/Helpers/SemaJob.h"
#include "Thread/JobManager.h"

SWC_BEGIN_NAMESPACE()

void SemaCycle::addNodeIfNeeded(const Symbol* sym)
{
    if (!graph_.names.contains(sym))
        graph_.names[sym] = sym->name(*ctx_);
    if (!graph_.adj.contains(sym))
        graph_.adj[sym] = {};
}

void SemaCycle::addEdge(const Symbol* from, const Symbol* to, SemaJob* job, const TaskState& state)
{
    addNodeIfNeeded(from);
    addNodeIfNeeded(to);

    graph_.adj[from].push_back(to);

    auto& loc = graph_.locs[from];
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

    const auto firstSym = cycle.front();
    const auto itLoc    = graph_.locs.find(firstSym);
    if (itLoc == graph_.locs.end())
        return;

    auto diag = SemaError::report(itLoc->second.job->sema(), DiagnosticId::sema_err_cyclic_dependency, itLoc->second.nodeRef);
    diag.addArgument(Diagnostic::ARG_VALUE, graph_.names.at(firstSym));

    for (const auto sym : cycle)
    {
        const auto itAdj = graph_.adj.find(sym);
        if (itAdj == graph_.adj.end())
            continue;

        for (const auto nextSym : itAdj->second)
        {
            bool inCycle = false;
            for (const auto s : cycle)
            {
                if (s == nextSym)
                {
                    inCycle = true;
                    break;
                }
            }

            if (inCycle)
            {
                const auto itLocNext = graph_.locs.find(sym);
                if (itLocNext != graph_.locs.end())
                {
                    diag.addNote(DiagnosticId::sema_note_cyclic_dependency_link);
                    diag.addArgument(Diagnostic::ARG_VALUE, graph_.names.at(nextSym));

                    const auto& node    = itLocNext->second.job->sema().node(itLocNext->second.nodeRef);
                    const auto& srcView = itLocNext->second.job->sema().compiler().srcView(node.srcViewRef());
                    const auto  loc     = Diagnostic::tokenErrorLocation(*ctx_, srcView, node.tokRef());
                    diag.last().addSpan(loc);
                }
                break;
            }
        }
    }

    diag.report(*ctx_);
}

void SemaCycle::findCycles(const Symbol* v, std::vector<const Symbol*>& stack, std::unordered_set<const Symbol*>& visited, std::unordered_set<const Symbol*>& onStack)
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
    std::unordered_set<const Symbol*> visited;
    std::unordered_set<const Symbol*> onStack;
    std::vector<const Symbol*>        stack;

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

            case TaskStateKind::SemaWaitSymDeclared:
            case TaskStateKind::SemaWaitSymTyped:
            case TaskStateKind::SemaWaitSymCompleted:
            {
                SWC_ASSERT(state.symbol);
                auto diag = SemaError::report(semaJob->sema(), DiagnosticId::sema_err_wait_sym_completed, state.srcViewRef, state.tokRef);
                diag.addArgument(Diagnostic::ARG_SYM, state.symbol->name(ctx));
                diag.report(ctx);
                break;
            }

            case TaskStateKind::SemaWaitTypeCompleted:
            {
                SWC_ASSERT(state.symbol);
                auto diag = SemaError::report(semaJob->sema(), DiagnosticId::sema_err_wait_sym_completed, state.nodeRef);
                diag.addArgument(Diagnostic::ARG_SYM, state.symbol->name(ctx));
                diag.report(ctx);
                break;
            }

            default:
                SWC_UNREACHABLE();
        }
    }
}

SWC_END_NAMESPACE()
