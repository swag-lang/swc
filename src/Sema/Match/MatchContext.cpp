#include "pch.h"
#include "Sema/Match/MatchContext.h"

SWC_BEGIN_NAMESPACE();

int MatchContext::Priority::compare(const Priority& a, const Priority& b)
{
    if (a.scopeDepth != b.scopeDepth)
        return (a.scopeDepth < b.scopeDepth) ? -1 : 1;
    if (a.visibility != b.visibility)
        return (static_cast<uint8_t>(a.visibility) < static_cast<uint8_t>(b.visibility)) ? -1 : 1;
    if (a.searchOrder != b.searchOrder)
        return (a.searchOrder < b.searchOrder) ? -1 : 1;
    return 0;
}

void MatchContext::clear()
{
    resetCandidates();
    symMaps.clear();
    symMapPriorities.clear();
    symMapHint          = nullptr;
    hasCurrentPriority_ = false;
}

void MatchContext::resetCandidates()
{
    symbols_.clear();
    hasBestPriority_ = false;
    bestPriority_    = Priority{};
}

void MatchContext::beginSymMapLookup(const Priority& priority)
{
    currentPriority_    = priority;
    hasCurrentPriority_ = true;
}

void MatchContext::addSymbol(const Symbol* symbol, const Priority& priority)
{
    if (!hasBestPriority_)
    {
        hasBestPriority_ = true;
        bestPriority_    = priority;
        symbols_.clear();
        symbols_.push_back(symbol);
        return;
    }

    const int cmp = Priority::compare(priority, bestPriority_);

    if (cmp > 0)
    {
        // Worse than best: ignore.
        return;
    }

    if (cmp < 0)
    {
        // Better: replace the current best set.
        bestPriority_ = priority;
        symbols_.clear();
        symbols_.push_back(symbol);
        return;
    }

    // Same priority: keep all candidates at this level (for ambiguity checks),
    // but avoid duplicates.
    for (const auto* s : symbols_)
        if (s == symbol)
            return;

    symbols_.push_back(symbol);
}

SWC_END_NAMESPACE();
