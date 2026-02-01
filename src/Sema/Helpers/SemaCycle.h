#pragma once
#include "Main/TaskContext.h"
#include "Support/Thread/JobManager.h"

SWC_BEGIN_NAMESPACE();

class SemaJob;
struct TaskState;
class Symbol;

class SemaCycle
{
public:
    void check(TaskContext& ctx, JobClientId clientId);

private:
    using SymbolSet = std::unordered_set<const Symbol*>;

    struct WaitGraph
    {
        struct NodeLoc
        {
            SemaJob*   job     = nullptr;
            AstNodeRef nodeRef = AstNodeRef::invalid();
        };

        std::unordered_map<const Symbol*, std::vector<const Symbol*>> adj;
        std::map<std::pair<const Symbol*, const Symbol*>, NodeLoc>    edges;
    };

    void addNodeIfNeeded(const Symbol* sym);
    void addEdge(const Symbol* from, const Symbol* to, SemaJob* job, const TaskState& state);
    void reportCycle(const std::vector<const Symbol*>& cycle);
    void findCycles(const Symbol* v, std::vector<const Symbol*>& stack, SymbolSet& visited, SymbolSet& onStack);
    void detectAndReportCycles();

    TaskContext* ctx_ = nullptr;
    WaitGraph    graph_;
};

SWC_END_NAMESPACE();
