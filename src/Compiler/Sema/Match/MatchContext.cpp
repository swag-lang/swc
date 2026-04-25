#include "pch.h"
#include "Compiler/Sema/Match/MatchContext.h"
#include "Compiler/Sema/Symbol/Symbols.h"

SWC_BEGIN_NAMESPACE();

int MatchContext::Priority::compare(const Priority& a, const Priority& b)
{
    if (a.scopeDepth != b.scopeDepth)
        return (a.scopeDepth < b.scopeDepth) ? -1 : 1;
    if (a.visibility != b.visibility)
        return (static_cast<uint8_t>(a.visibility) < static_cast<uint8_t>(b.visibility)) ? -1 : 1;
    return 0;
}

void MatchContext::clear()
{
    resetCandidates();
    symMaps.clear();
    symMapPriorities.clear();
    localSymbols.clear();
    symMapHint          = nullptr;
    hasCurrentPriority_ = false;
    codeRef             = SourceCodeRef::invalid();
}

void MatchContext::resetCandidates()
{
    symbols_.clear();
    allSymbols_.clear();
    hasBestPriority_        = false;
    bestPriority_           = Priority{};
    hasIgnoredBestPriority_ = false;
    ignoredBestPriority_    = Priority{};
}

void MatchContext::beginSymMapLookup(const Priority& priority)
{
    currentPriority_    = priority;
    hasCurrentPriority_ = true;
}

void MatchContext::addSymbol(const Symbol* symbol, const Priority& priority)
{
    if (hasIgnoredBestPriority_)
    {
        const int cmpIgnored = Priority::compare(priority, ignoredBestPriority_);
        if (cmpIgnored > 0)
        {
            // An ignored declaration from a better-priority scope shadows this symbol.
            return;
        }
    }

    bool found = false;
    for (const CandidateSymbol& s : allSymbols_)
    {
        if (s.symbol == symbol)
        {
            found = true;
            break;
        }
    }

    if (!found)
        allSymbols_.push_back({.symbol = symbol, .priority = priority});

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
    for (const Symbol* s : symbols_)
        if (s == symbol)
            return;

    symbols_.push_back(symbol);
}

void MatchContext::collectCallFallbackSymbols(SmallVector<const Symbol*>& outSymbols) const
{
    outSymbols.clear();

    if (symbols_.empty())
        return;

    for (const Symbol* symbol : symbols_)
    {
        if (!symbol || !symbol->acceptOverloads())
            return;
    }

    for (const CandidateSymbol& candidate : allSymbols_)
    {
        const Symbol* symbol = candidate.symbol;
        if (!symbol || !symbol->acceptOverloads())
            continue;

        bool duplicate = false;
        for (const Symbol* existing : outSymbols)
        {
            if (existing == symbol)
            {
                duplicate = true;
                break;
            }
        }

        if (!duplicate)
            outSymbols.push_back(symbol);
    }
}

void MatchContext::addIgnoredSymbol(const Priority& priority)
{
    if (!hasIgnoredBestPriority_ || Priority::compare(priority, ignoredBestPriority_) < 0)
    {
        hasIgnoredBestPriority_ = true;
        ignoredBestPriority_    = priority;
    }
}

SWC_END_NAMESPACE();
