#pragma once
#include "Compiler/Lexer/SourceCodeRange.h"
#include "Support/Core/SmallVector.h"

SWC_BEGIN_NAMESPACE();

class Symbol;
class SymbolMap;

class MatchContext
{
public:
    // How a symbol became visible at a given point.
    enum class VisibilityTier : uint8_t
    {
        LocalScope      = 0, // directly declared in the scope
        UsingDirective  = 1, // brought in via "using" / import
        FileNamespace   = 2, // file-level namespace
        ModuleNamespace = 3, // module-level namespace
    };

    // Priority key for a symbol / symMap. Lower is better in each dimension.
    struct Priority
    {
        uint16_t       scopeDepth = 0; // 0 = innermost, increases as we go outward
        VisibilityTier visibility = VisibilityTier::LocalScope;
        static int     compare(const Priority& a, const Priority& b);
    };

    SourceCodeRef codeRef = SourceCodeRef::invalid();

    // Optional hint: if set, we only look in this symMap (high precision lookup).
    const SymbolMap* symMapHint = nullptr;

    // When true, `Match::match` will not return `Pause` on empty results.
    // This is useful for speculative/probing lookups where the caller will try other strategies.
    bool noWaitOnEmpty = false;

    void clear();
    void resetCandidates();
    void beginSymMapLookup(const Priority& priority);
    void addSymbol(const Symbol* symbol, const Priority& priority);

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

    SmallVector<const Symbol*>&       symbols() { return symbols_; }
    const SmallVector<const Symbol*>& symbols() const { return symbols_; }

    bool          empty() const { return symbols_.empty(); }
    size_t        count() const { return symbols_.size(); }
    const Symbol* first() const { return symbols_.front(); }

    SmallVector<const SymbolMap*> symMaps;
    SmallVector<Priority>         symMapPriorities;

private:
    SmallVector<const Symbol*> symbols_;

    bool     hasBestPriority_ = false;
    Priority bestPriority_    = {};

    bool     hasCurrentPriority_ = false;
    Priority currentPriority_    = {};
};

SWC_END_NAMESPACE();
