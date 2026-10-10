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
            key = Utf8(file->path());

        key += "|";
        key += std::format("{:010}", symbol.tokRef().get());
        return key;
    }

    // Location keys for many symbols. The file part of a key, the source path and its separator,
    // is the costly half: a path conversion. It is made once per source file here, not once per
    // symbol; the keys are the ones locationKey builds.
    class LocationKeyCache
    {
    public:
        explicit LocationKeyCache(const CompilerInstance& compiler) :
            compiler_(&compiler)
        {
        }

        // The file part of the symbol's key. The reference stays valid while the cache lives.
        template<typename T>
        const Utf8& prefix(const T& symbol)
        {
            const SourceFile* file = compiler_->srcView(symbol.srcViewRef()).file();
            const auto [it, inserted] = filePrefixes_.try_emplace(file);
            if (inserted)
            {
                if (file)
                    it->second = Utf8(file->path());
                innerSeparator_ = innerSeparator_ || it->second.find('|') != Utf8::npos;
                it->second += "|";
            }

            return it->second;
        }

        template<typename T>
        Utf8 key(const T& symbol)
        {
            Utf8 result = prefix(symbol);
            result += std::format("{:010}", symbol.tokRef().get());
            return result;
        }

        // True when a path holds the separator itself, so a shorter file part can be a prefix of
        // a longer one and only the whole keys order the symbols.
        bool hasInnerSeparator() const { return innerSeparator_; }

    private:
        const CompilerInstance*                     compiler_ = nullptr;
        std::unordered_map<const SourceFile*, Utf8> filePrefixes_;
        bool                                        innerSeparator_ = false;
    };

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

        // A key is the file part, which ends with the only separator it holds, then ten digits.
        // Two keys then compare as their file parts and, on a tie, as their token numbers, so the
        // keys need not be built: the same stable order comes from the parts.
        struct Located
        {
            T*          symbol = nullptr;
            const Utf8* prefix = nullptr;
            uint32_t    tokRef = 0;
        };

        LocationKeyCache     keys(compiler);
        std::vector<Located> located;
        located.reserve(values.size());
        for (T* symbol : values)
            located.push_back({.symbol = symbol, .prefix = &keys.prefix(*symbol), .tokRef = symbol->tokRef().get()});
        if (keys.hasInnerSeparator())
        {
            sortAndUnique(values, [&keys](const T& symbol) { return keys.key(symbol); });
            return;
        }

        std::ranges::stable_sort(located, [](const Located& lhs, const Located& rhs) {
            if (lhs.prefix != rhs.prefix)
            {
                const int order = lhs.prefix->compare(*rhs.prefix);
                if (order)
                    return order < 0;
            }
            return lhs.tokRef < rhs.tokRef;
        });

        values.clear();
        T* previous = nullptr;
        for (const Located& entry : located)
        {
            if (entry.symbol == previous)
                continue;
            values.push_back(entry.symbol);
            previous = entry.symbol;
        }
    }
}

SWC_END_NAMESPACE();
