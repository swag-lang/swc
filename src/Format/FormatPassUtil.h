#pragma once
#include "Format/FormatModel.h"

SWC_BEGIN_NAMESPACE();

// Shared helpers for the formatting passes.
namespace FormatPassUtil
{
    constexpr uint32_t INVALID_PIECE = FormatPiece::INVALID_INDEX;

    inline bool canEditGap(const FormatModel& model, const uint32_t pieceIndex)
    {
        if (model.gapBefore(pieceIndex).frozen)
            return false;
        if (model.piece(pieceIndex).frozen || model.piece(pieceIndex).removed)
            return false;
        return true;
    }

    inline bool canEditPiece(const FormatModel& model, const uint32_t pieceIndex)
    {
        const FormatPiece& piece = model.piece(pieceIndex);
        return !piece.frozen && !piece.removed;
    }

    // One indentation level, following the configured indent style.
    inline Utf8 indentUnit(const FormatModel& model)
    {
        const FormatOptions& options = model.options();
        if (options.indentStyle == FormatIndentStyle::Tabs)
            return "\t";
        return Utf8(std::max(options.indentWidth, 1u), ' ');
    }

    inline Utf8 indentPlusOne(const FormatModel& model, const std::string_view baseIndent)
    {
        Utf8 result(baseIndent);
        if (model.options().indentStyle == FormatIndentStyle::Preserve && baseIndent.find('\t') != std::string_view::npos)
            result += '\t';
        else
            result += indentUnit(model).view();
        return result;
    }

    // Indentation text for a given column count, following the indent style.
    inline Utf8 indentForColumns(const FormatModel& model, const uint32_t columns)
    {
        const FormatOptions& options = model.options();
        const uint32_t       width   = std::max(options.indentWidth, 1u);
        if (options.indentStyle == FormatIndentStyle::Tabs)
        {
            Utf8 result(columns / width, '\t');
            result.append(columns % width, ' ');
            return result;
        }
        return Utf8(columns, ' ');
    }

    // Last piece of the line starting at `lineStart` (skips removed pieces).
    inline uint32_t lineEndOf(const FormatModel& model, const uint32_t lineStart)
    {
        uint32_t last = lineStart;
        for (;;)
        {
            const uint32_t next = model.nextPiece(last);
            if (next == INVALID_PIECE || model.gapHasNewline(next))
                return last;
            last = next;
        }
    }

    struct PieceColumn
    {
        uint32_t piece  = INVALID_PIECE;
        uint32_t column = 0; // start column of the piece
    };

    // Computes the start column of every piece of the line beginning at
    // `lineStart`, and the column right after its last piece.
    inline uint32_t computeLineColumns(const FormatModel& model, const uint32_t lineStart, std::vector<PieceColumn>* out)
    {
        const uint32_t tabWidth = std::max(model.options().tabWidth, 1u);
        if (out)
            out->clear();

        uint32_t column = FormatModel::textColumns(model.lineIndentOf(lineStart), tabWidth);
        uint32_t piece  = lineStart;
        for (;;)
        {
            if (out)
                out->push_back({piece, column});
            column += FormatModel::textColumns(model.piece(piece).text, tabWidth, column);

            const uint32_t next = model.nextPiece(piece);
            if (next == INVALID_PIECE || model.gapHasNewline(next))
                return column;
            column += model.gapColumns(next);
            piece = next;
        }
    }

    // Rendered width of the line containing `lineStart`.
    inline uint32_t lineWidth(const FormatModel& model, const uint32_t lineStart)
    {
        return computeLineColumns(model, lineStart, nullptr);
    }

    // A contiguous range of pieces [first, last].
    struct PieceRange
    {
        uint32_t first = INVALID_PIECE;
        uint32_t last  = INVALID_PIECE;
    };

    // Reorders contiguous segments in place. The leading gap of each segment
    // position is kept at that position (so line breaks / indentation stay
    // put), while the inner gaps travel with their segment.
    void reorderSegments(FormatModel& model, const std::vector<PieceRange>& segments, const std::vector<uint32_t>& order);
}

SWC_END_NAMESPACE();
