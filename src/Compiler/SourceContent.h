#pragma once

SWC_BEGIN_NAMESPACE();

// A captured source generation is immutable. Importers share its padded bytes,
// while their tokens, syntax trees and semantic state remain instance-owned.
class SourceContent
{
public:
    static constexpr size_t TRAILING_0 = 4;

    explicit SourceContent(std::vector<char8_t> bytes) :
        bytes_(std::move(bytes))
    {
        bytes_.insert(bytes_.end(), TRAILING_0, 0);
    }

    explicit SourceContent(std::string_view text)
    {
        bytes_.reserve(text.size() + TRAILING_0);
        bytes_.insert(bytes_.end(), text.begin(), text.end());
        bytes_.insert(bytes_.end(), TRAILING_0, 0);
    }

    const std::vector<char8_t>& bytes() const { return bytes_; }
    std::string_view            view() const { return {reinterpret_cast<const char*>(bytes_.data()), bytes_.size() - TRAILING_0}; }

private:
    std::vector<char8_t> bytes_;
};

SWC_END_NAMESPACE();
