#pragma once
#include "Core/SmallVector.h"
#include "Lexer/SourceView.h"
#include "Lexer/Token.h"

SWC_BEGIN_NAMESPACE()

class Symbol;
class SymbolMap;

class LookUpContext
{
public:
    SourceViewRef    srcViewRef = SourceViewRef::invalid();
    TokenRef         tokRef     = TokenRef::invalid();
    const SymbolMap* symMapHint = nullptr;

    void clear()
    {
        symbols_.clear();
        symMaps.clear();
        symMapHint = nullptr;
    }

    void addSymbol(const Symbol* symbol)
    {
        for (const auto s : symbols_)
            if (s == symbol)
                return;
        symbols_.push_back(symbol);
    }

    SmallVector<const Symbol*>&       symbols() { return symbols_; }
    const SmallVector<const Symbol*>& symbols() const { return symbols_; }
    bool                              empty() const { return symbols_.empty(); }
    size_t                            count() const { return symbols_.size(); }
    const Symbol*                     first() const { return symbols_.front(); }

    SmallVector<const SymbolMap*> symMaps;

private:
    SmallVector<const Symbol*> symbols_;
};

SWC_END_NAMESPACE()
