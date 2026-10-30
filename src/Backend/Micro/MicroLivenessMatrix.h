#pragma once
#include "Support/Report/Assert.h"

SWC_BEGIN_NAMESPACE();

// Cyclic dataflow updates dense rows in place. Acyclic dataflow publishes each row once,
// allowing zero prefixes and suffixes to be omitted without changing register numbering.
class MicroLivenessMatrix
{
public:
    struct Row
    {
        std::span<const uint64_t> words;
        uint32_t                  firstWord = 0;

        uint32_t endWord() const { return firstWord + static_cast<uint32_t>(words.size()); }

        uint64_t operator[](size_t wordIndex) const
        {
            const size_t local = wordIndex - firstWord;
            return local < words.size() ? words[local] : 0;
        }

        bool contains(uint32_t bitIndex) const { return ((*this)[bitIndex >> 6u] & (1ull << (bitIndex & 63u))) != 0; }

        void copyTo(std::span<uint64_t> destination) const
        {
            SWC_ASSERT(firstWord + words.size() <= destination.size());
            std::ranges::fill(destination.first(firstWord), 0);
            std::ranges::copy(words, destination.begin() + firstWord);
            std::ranges::fill(destination.subspan(firstWord + words.size()), 0);
        }

        void mergeInto(std::span<uint64_t> destination) const
        {
            SWC_ASSERT(firstWord + words.size() <= destination.size());
            for (size_t word = 0; word < words.size(); ++word)
                destination[firstWord + word] |= words[word];
        }
    };

    void reset(uint32_t rows, uint32_t words, bool compact, bool clear)
    {
        rowCount_  = rows;
        wordCount_ = words;
        compact_   = compact;
        usedWords_ = 0;
        if (compact_)
        {
            rows_.resize(rows);
            return;
        }

        rows_.clear();
        const size_t count = static_cast<size_t>(rows) * words;
        if (clear || count > bits_.capacity())
            bits_.assign(count, 0);
        else
            bits_.resize(count);
    }

    bool compact() const { return compact_; }

    Row row(uint32_t index) const
    {
        SWC_ASSERT(index < rowCount_);
        if (!compact_)
            return {wordCount_ ? std::span<const uint64_t>{bits_.data() + static_cast<size_t>(index) * wordCount_, wordCount_} : std::span<const uint64_t>{}, 0};

        const RowRange& range = rows_[index];
        return {range.count ? std::span<const uint64_t>{bits_.data() + range.offset, range.count} : std::span<const uint64_t>{}, range.first};
    }

    uint64_t word(uint32_t index, uint32_t wordIndex) const
    {
        SWC_ASSERT(index < rowCount_ && wordIndex < wordCount_);
        if (!compact_)
            return bits_[static_cast<size_t>(index) * wordCount_ + wordIndex];
        return row(index)[wordIndex];
    }

    bool contains(uint32_t index, uint32_t bitIndex) const { return (word(index, bitIndex >> 6u) & (1ull << (bitIndex & 63u))) != 0; }

    std::span<uint64_t> denseRow(uint32_t index)
    {
        SWC_ASSERT(!compact_ && index < rowCount_);
        return wordCount_ ? std::span<uint64_t>{bits_.data() + static_cast<size_t>(index) * wordCount_, wordCount_} : std::span<uint64_t>{};
    }

    // Source words must not alias this matrix. Their global word indices start at firstWord.
    void assignRow(uint32_t index, uint32_t firstWord, std::span<const uint64_t> source)
    {
        SWC_ASSERT(compact_ && index < rowCount_ && firstWord + source.size() <= wordCount_);
        while (!source.empty() && !source.back())
            source = source.first(source.size() - 1);
        while (!source.empty() && !source.front())
        {
            source = source.subspan(1);
            ++firstWord;
        }
        if (source.empty())
            firstWord = 0;

        const size_t end = usedWords_ + source.size();
        if (end > bits_.size())
            bits_.resize(end);
        if (!source.empty())
            std::ranges::copy(source, bits_.begin() + usedWords_);
        rows_[index] = {usedWords_, firstWord, static_cast<uint32_t>(source.size())};
        usedWords_   = end;
    }

    void finishRows()
    {
        if (compact_)
            bits_.resize(usedWords_);
    }

private:
    struct RowRange
    {
        size_t   offset = 0;
        uint32_t first  = 0;
        uint32_t count  = 0;
    };

    std::vector<uint64_t> bits_;
    std::vector<RowRange> rows_;
    size_t                usedWords_ = 0;
    uint32_t              wordCount_ = 0;
    uint32_t              rowCount_  = 0;
    bool                  compact_   = false;
};

SWC_END_NAMESPACE();
