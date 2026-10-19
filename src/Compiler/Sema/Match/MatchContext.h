#pragma once
#include "Compiler/Lexer/SourceCodeRange.h"
#include "Support/Core/SmallVector.h"
#include "Support/Report/Assert.h"

SWC_BEGIN_NAMESPACE();

class Symbol;
class SymbolMap;

class MatchContext
{
public:
    // At equal depth, namespace declarations shadow names brought in by using directives.
    // A module's own Error therefore precedes Swag.Error imported through using Swag.
    enum class VisibilityTier : uint8_t
    {
        LocalScope      = 0, // directly declared in the scope
        FileNamespace   = 1, // file-level namespace
        ModuleNamespace = 2, // module-level namespace
        UsingDirective  = 3, // brought in via "using" / import
    };

    // Priority key for a symbol / symMap. Lower is better in each dimension.
    struct Priority
    {
        uint16_t       scopeDepth = 0; // 0 = innermost, increases as we go outward
        VisibilityTier visibility = VisibilityTier::LocalScope;

        static int compare(const Priority& a, const Priority& b);
    };

    SourceCodeRef codeRef = SourceCodeRef::invalid();

    // Optional hint: if set, we only look in this symMap (high precision lookup).
    const SymbolMap* symMapHint = nullptr;

    // When true, `Match::match` will not return `Pause` on empty results.
    // This is useful for speculative/probing lookups where the caller will try other strategies.
    bool noWaitOnEmpty = false;

    // Probe symbols that are not declared or typed yet without waiting, so speculative
    // lookup does not create a hard dependency.
    bool noWaitOnPendingSymbols = false;

    // Skip members brought in by a struct's using fields. Walking those fields is safe
    // only after completion, when other jobs can no longer add fields.
    bool skipUsingFieldMembers = false;

    void clear();
    void resetCandidates();

    void beginSymMapLookup(const Priority& priority);
    void addSymbol(const Symbol* symbol, const Priority& priority);

    // Discards the resolved candidates in favor of 'symbol'. Used to arbitrate a lookup on a rule
    // the scope priorities cannot express, such as preferring a namespace of the current module.
    void replaceWithSingleSymbol(const Symbol* symbol);
    void addIgnoredSymbol(const Priority& priority);

    void collectCallFallbackSymbols(SmallVector<const Symbol*>& outSymbols) const;
    void collectCallableSymbols(SmallVector<const Symbol*>& outSymbols) const;
    void appendCallFallbackSymbols(SmallVector<const Symbol*>& outSymbols) const;
    void appendCallableSymbols(SmallVector<const Symbol*>& outSymbols) const;

    struct LocalSymbol
    {
        const Symbol* symbol;
        Priority      priority;
    };

    SmallVector<LocalSymbol> localSymbols;

    void addSymbol(const Symbol* symbol)
    {
        SWC_ASSERT(hasCurrentPriority_);
        addSymbol(symbol, currentPriority_);
    }

    void addIgnoredSymbol()
    {
        SWC_ASSERT(hasCurrentPriority_);
        addIgnoredSymbol(currentPriority_);
    }

    SmallVector<const Symbol*>&       symbols() { return symbols_; }
    const SmallVector<const Symbol*>& symbols() const { return symbols_; }

    bool          empty() const { return symbols_.empty(); }
    size_t        count() const { return symbols_.size(); }
    const Symbol* first() const { return symbols_.front(); }

    // A failed declaration also poisons an incomplete overload set at its own priority.
    // Matching only the survivors can turn the original error into a false argument mismatch.
    bool blockedByIgnored() const { return hasIgnoredBestPriority_ && (!hasBestPriority_ || Priority::compare(ignoredBestPriority_, bestPriority_) <= 0); }

    SmallVector<const SymbolMap*> symMaps;
    SmallVector<Priority>         symMapPriorities;

private:
    SmallVector<const Symbol*> symbols_;

    // Unique symbols in first-discovery order, including candidates below the best priority.
    SmallVector<const Symbol*> allSymbols_;

    Priority bestPriority_        = {};
    Priority ignoredBestPriority_ = {};
    Priority currentPriority_     = {};

    bool hasBestPriority_        = false;
    bool hasIgnoredBestPriority_ = false;
    bool hasCurrentPriority_     = false;
};

SWC_END_NAMESPACE();
