#pragma once
#include "Compiler/SourceFile.h"
#include "Main/CompilerInstance.h"
#include "Support/Core/Utf8.h"
#include "Support/Report/Assert.h"

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
        key += std::format("{:010}", symbol.tokRef().get());
        return key;
    }

    template<typename T>
    struct Entry
    {
        T*   symbol = nullptr;
        Utf8 key;
    };

    template<typename T>
    struct LocationKeyFactory
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

        std::ranges::stable_sort(entries, {}, &Entry<T>::key);

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
        values.erase(std::remove(values.begin(), values.end(), nullptr), values.end());
        if (values.size() < 2)
            return;

        const SourceFile* file     = compiler.srcView(values.front()->srcViewRef()).file();
        const bool        sameFile = std::all_of(values.begin() + 1, values.end(), [&](const T* symbol) {
            return compiler.srcView(symbol->srcViewRef()).file() == file;
        });
        if (sameFile)
        {
            // Equal path prefixes leave only the ten-digit, zero-padded uint32 token.
            // Numeric order is identical, including the invalid token's UINT32_MAX value.
            std::ranges::stable_sort(values, {}, [](const T* symbol) { return symbol->tokRef().get(); });
            values.erase(std::unique(values.begin(), values.end()), values.end());
            return;
        }

        sortAndUnique(values, LocationKeyFactory<T>{.compiler = &compiler});
    }
}

SWC_END_NAMESPACE();
