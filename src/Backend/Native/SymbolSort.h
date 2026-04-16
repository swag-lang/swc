#pragma once
#include "Compiler/SourceFile.h"
#include "Main/CompilerInstance.h"

SWC_BEGIN_NAMESPACE();

namespace SymbolSort
{
    template<typename T>
    Utf8 locationKey(const CompilerInstance& compiler, const T& symbol)
    {
        Utf8 key;
        if (const SourceFile* file = compiler.srcView(symbol.srcViewRef()).file())
            key += Utf8(file->path());

        key += "|";
        key += std::to_string(symbol.tokRef().get());
        return key;
    }

    template<typename T>
    struct Entry
    {
        T*   symbol = nullptr;
        Utf8 key;
    };

    template<typename T>
    struct EntryKeyLess
    {
        bool operator()(const Entry<T>& lhs, const Entry<T>& rhs) const
        {
            return lhs.key < rhs.key;
        }
    };

    template<typename T>
    struct LocationKeyMaker
    {
        const CompilerInstance* compiler = nullptr;

        Utf8 operator()(const T& symbol) const
        {
            SWC_ASSERT(compiler != nullptr);
            return locationKey(*compiler, symbol);
        }
    };

    template<typename T, typename MAKE_KEY>
    void sortAndUnique(std::vector<T*>& values, const MAKE_KEY& makeKey)
    {
        values.erase(std::remove(values.begin(), values.end(), nullptr), values.end());
        if (values.size() < 2)
            return;

        std::vector<Entry<T>> entries;
        entries.reserve(values.size());
        for (T* symbol : values)
        {
            SWC_ASSERT(symbol != nullptr);
            entries.push_back({.symbol = symbol, .key = makeKey(*symbol)});
        }

        std::ranges::stable_sort(entries, EntryKeyLess<T>{});

        values.clear();
        values.reserve(entries.size());
        T* previous = nullptr;
        for (const auto& entry : entries)
        {
            if (entry.symbol == previous)
                continue;

            values.push_back(entry.symbol);
            previous = entry.symbol;
        }
    }

    template<typename T>
    void sortAndUniqueByLocation(std::vector<T*>& values, const CompilerInstance& compiler)
    {
        sortAndUnique(values, LocationKeyMaker<T>{.compiler = &compiler});
    }
}

SWC_END_NAMESPACE();
