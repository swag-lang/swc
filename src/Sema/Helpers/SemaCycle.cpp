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

namespace
{
    struct WaitGraph
    {
        std::unordered_map<const Symbol*, std::vector<const Symbol*>> adj;
        std::unordered_map<const Symbol*, Utf8>                       names;

        // For pointing diagnostics, keep a representative job + state for each node
        struct NodeLoc
        {
            SemaJob*      job     = nullptr;
            AstNodeRef    node    = AstNodeRef::invalid();
            SourceViewRef srcView = SourceViewRef::invalid();
            TokenRef      tok     = TokenRef::invalid();
        };

        std::unordered_map<const Symbol*, NodeLoc> locs;
    };

    void addNodeIfNeeded(WaitGraph& g, const Symbol* sym, const TaskContext& ctx)
    {
        if (!g.names.contains(sym))
            g.names[sym] = sym->name(ctx);
        if (!g.adj.contains(sym))
            g.adj[sym] = {};
    }

    void addEdge(WaitGraph& g, const Symbol* from, const Symbol* to, const TaskContext& ctx, SemaJob* job, const TaskState& state)
    {
        addNodeIfNeeded(g, from, ctx);
        addNodeIfNeeded(g, to, ctx);

        g.adj[from].push_back(to);

        // record a representative location for "from" if we don't have one yet
        auto& loc = g.locs[from];
        if (!loc.job)
        {
            loc.job     = job;
            loc.node    = state.nodeRef;
            loc.srcView = state.srcViewRef;
            loc.tok     = state.tokRef;
        }
    }

    void detectAndReportCycles(TaskContext& ctx, JobClientId clientId, WaitGraph& g)
    {
        using IndexMap   = std::unordered_map<const Symbol*, int>;
        using OnStackSet = std::unordered_set<const Symbol*>;

        IndexMap                   index;
        IndexMap                   lowlink;
        OnStackSet                 onStack;
        std::vector<const Symbol*> st;
        int                        currentIndex = 0;

        std::vector<std::vector<const Symbol*>> cycles;

        std::function<void(const Symbol*)> strongConnect = [&](const Symbol* v) {
            index[v]   = currentIndex;
            lowlink[v] = currentIndex;
            ++currentIndex;

            st.push_back(v);
            onStack.insert(v);

            auto itAdj = g.adj.find(v);
            if (itAdj != g.adj.end())
            {
                for (const auto w : itAdj->second)
                {
                    if (!index.contains(w))
                    {
                        strongConnect(w);
                        lowlink[v] = std::min(lowlink[v], lowlink[w]);
                    }
                    else if (onStack.contains(w))
                    {
                        lowlink[v] = std::min(lowlink[v], index[w]);
                    }
                }
            }

            if (lowlink[v] == index[v])
            {
                std::vector<const Symbol*> component;
                while (true)
                {
                    const Symbol* w = st.back();
                    st.pop_back();
                    onStack.erase(w);
                    component.push_back(w);
                    if (w == v)
                        break;
                }

                bool hasCycle = component.size() > 1;
                if (!hasCycle)
                {
                    auto itAdjV = g.adj.find(v);
                    if (itAdjV != g.adj.end())
                    {
                        for (const auto to : itAdjV->second)
                        {
                            if (to == v)
                            {
                                hasCycle = true;
                                break;
                            }
                        }
                    }
                }

                if (hasCycle)
                    cycles.push_back(std::move(component));
            }
        };

        for (const auto& key : g.adj | std::views::keys)
        {
            const Symbol* v = key;
            if (!index.contains(v))
                strongConnect(v);
        }

        // Emit one diagnostic per strongly connected component that is actually a cycle.
        for (const auto& cyc : cycles)
        {
            if (cyc.empty())
                continue;

            // Build "A -> B -> C -> A"
            Utf8 msg;
            for (size_t i = 0; i < cyc.size(); ++i)
            {
                if (i)
                    msg += " -> ";
                msg += g.names.at(cyc[i]);
            }
            msg += " -> ";
            msg += g.names.at(cyc.front());

            // Pick a representative node for a location.
            const Symbol* rep   = cyc.front();
            auto          itLoc = g.locs.find(rep);
            SemaJob*      job   = nullptr;
            AstNodeRef    node  = AstNodeRef::invalid();

            if (itLoc != g.locs.end())
            {
                job  = itLoc->second.job;
                node = itLoc->second.node;
            }

            if (!job)
            {
                // Worst case: no specific location, just emit a global diagnostic.
                auto diag = Diagnostic::get(DiagnosticId::sema_err_cyclic_dependency);
                diag.addArgument(Diagnostic::ARG_VALUE, msg);
                diag.report(ctx);
                continue;
            }

            auto diag = SemaError::report(job->sema(), DiagnosticId::sema_err_cyclic_dependency, node);
            diag.addArgument(Diagnostic::ARG_VALUE, msg);
            diag.report(ctx);
        }
    }
}

void SemaCycle::check(TaskContext& ctx, JobClientId clientId)
{
    std::vector<Job*> jobs;
    ctx.global().jobMgr().waitingJobs(jobs, clientId);

    WaitGraph graph;

    for (const auto job : jobs)
    {
        const TaskState& state   = job->ctx().state();
        auto*            semaJob = job->safeCast<SemaJob>();
        if (!semaJob)
            continue;
        if (state.waiterSymbol && state.symbol)
            addEdge(graph, state.waiterSymbol, state.symbol, ctx, semaJob, state);
    }

    detectAndReportCycles(ctx, clientId, graph);

    for (const auto job : jobs)
    {
        const TaskState& state = job->ctx().state();
        if (const auto semaJob = job->safeCast<SemaJob>())
        {
            switch (state.kind)
            {
                case TaskStateKind::SemaWaitIdentifier:
                {
                    auto diag = SemaError::report(semaJob->sema(), DiagnosticId::sema_err_unknown_symbol, state.srcViewRef, state.tokRef);
                    diag.addArgument(Diagnostic::ARG_SYM, state.idRef);
                    if (state.waiterSymbol)
                        diag.addArgument(Diagnostic::ARG_SYM_2, state.waiterSymbol->name(ctx));
                    diag.report(ctx);
                    break;
                }

                case TaskStateKind::SemaWaitSymDeclared:
                case TaskStateKind::SemaWaitSymTyped:
                case TaskStateKind::SemaWaitSymCompleted:
                case TaskStateKind::SemaWaitTypeCompleted:
                {
                    auto diag = SemaError::report(semaJob->sema(), DiagnosticId::sema_err_wait_sym_completed, state.srcViewRef, state.tokRef);
                    if (state.symbol)
                        diag.addArgument(Diagnostic::ARG_SYM, state.symbol->name(ctx));
                    if (state.waiterSymbol)
                        diag.addArgument(Diagnostic::ARG_SYM_2, state.waiterSymbol->name(ctx));
                    diag.report(ctx);
                    break;
                }

                default:
                    SWC_UNREACHABLE();
            }
        }
    }
}

SWC_END_NAMESPACE()
