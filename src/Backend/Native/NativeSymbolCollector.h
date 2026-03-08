#pragma once

#include "Backend/Native/NativeBackendBuilder.h"

SWC_BEGIN_NAMESPACE();

class NativeSymbolCollector
{
public:
    explicit NativeSymbolCollector(NativeBackendBuilder& builder);

    bool prepare();

private:
    enum class CompilerFunctionKind : uint8_t
    {
        None,
        Test,
        Init,
        PreMain,
        Drop,
        Main,
        Excluded,
    };

    template<typename T>
    void sortAndUnique(std::vector<T*>& values) const;

    bool                 collectSymbols();
    void                 collectSymbolsRec(const SymbolMap& symbolMap);
    void                 collectFunction(SymbolFunction& symbol);
    bool                 scheduleCodeGen();
    CompilerFunctionKind classifyCompilerFunction(const SymbolFunction& symbol) const;
    static bool          isCompilerFunction(const SymbolFunction& symbol);
    Utf8                 makeSymbolSortKey(const SymbolFunction& symbol) const;
    Utf8                 makeSortKey(const SymbolFunction& symbol) const;
    Utf8                 makeSortKey(const SymbolVariable& symbol) const;

    NativeBackendBuilder& builder_;
};

template<typename T>
void NativeSymbolCollector::sortAndUnique(std::vector<T*>& values) const
{
    values.erase(std::remove(values.begin(), values.end(), nullptr), values.end());
    std::ranges::sort(values, [&](const T* lhs, const T* rhs) {
        if (lhs == rhs)
            return false;

        const Utf8 lhsKey = makeSortKey(*lhs);
        const Utf8 rhsKey = makeSortKey(*rhs);
        if (lhsKey != rhsKey)
            return lhsKey < rhsKey;
        return lhs < rhs;
    });

    values.erase(std::unique(values.begin(), values.end()), values.end());
}

SWC_END_NAMESPACE();
