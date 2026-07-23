#include "pch.h"
#include "Format/FormatPasses.h"
#include "Format/FormatPassUtil.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    using FormatPassUtil::INVALID_PIECE;

    // Ensures the gap before `pieceIndex` holds at least `newlines` line
    // breaks (or exactly, when `exact` is true), keeping the line indent.
    void forceGapNewlines(FormatModel& model, const uint32_t pieceIndex, const uint32_t newlines, const bool exact)
    {
        if (!FormatPassUtil::canEditGap(model, pieceIndex))
            return;

        const uint32_t current = model.gapNewlineCount(pieceIndex);
        if (current == 0)
            return; // same-line neighbors: not a line-structure gap
        if (exact ? current == newlines : current >= newlines)
            return;

        const Utf8 indent(model.lineIndentOf(pieceIndex));
        model.setGapBreak(pieceIndex, newlines, indent.view());
    }

    void applyBlankLineAfterUsingBlock(FormatModel& model)
    {
        const FormatOptions& options = model.options();
        if (!options.blankLineAfterUsingBlock)
            return;

        // Locate the initial run of top-level `using` statements.
        uint32_t lastUsingLineEnd = INVALID_PIECE;
        bool     sawUsing         = false;

        std::vector<uint32_t> lineStarts;
        model.collectLineStarts(lineStarts);

        for (const uint32_t lineStart : lineStarts)
        {
            const FormatPiece& piece = model.piece(lineStart);
            if (piece.isComment)
            {
                if (sawUsing)
                    break;
                continue; // header comments before the using block
            }

            if (piece.hasRole(FormatRoleE::UsingStart) && piece.depth == 0)
            {
                sawUsing         = true;
                lastUsingLineEnd = FormatPassUtil::lineEndOf(model, lineStart);
                continue;
            }

            if (!sawUsing)
                return; // first code is not a using: nothing to do

            // First non-using code line after the block.
            const uint32_t wanted = *options.blankLineAfterUsingBlock ? 2u : 1u;
            forceGapNewlines(model, lineStart, wanted, !*options.blankLineAfterUsingBlock);
            return;
        }
    }

    void applyBlankLinesBetweenFunctions(FormatModel& model)
    {
        const FormatOptions& options = model.options();
        if (options.minBlankLinesBetweenFunctions == 0)
            return;

        std::vector<uint32_t> lineStarts;
        model.collectLineStarts(lineStarts);

        for (const uint32_t lineStart : lineStarts)
        {
            const FormatPiece& piece = model.piece(lineStart);
            if (piece.removed || !piece.hasRole(FormatRoleE::FuncDeclStart))
                continue;

            // Walk up over the attribute lines attached to the declaration.
            uint32_t target = lineStart;
            for (;;)
            {
                const uint32_t prev = model.prevPiece(target);
                if (prev == INVALID_PIECE)
                    break;
                const uint32_t prevLineStart = model.lineStartOf(prev);
                const FormatPiece& prevPiece = model.piece(prevLineStart);
                if (!prevPiece.hasRole(FormatRoleE::AttrOpen))
                    break;
                target = prevLineStart;
            }

            const uint32_t prev = model.prevPiece(target);
            if (prev == INVALID_PIECE)
                continue;
            // No forced blank line right after an opening brace or before the
            // very first statement of a block.
            if (model.piece(prev).is(TokenId::SymLeftCurly))
                continue;

            forceGapNewlines(model, target, options.minBlankLinesBetweenFunctions + 1, false);
        }
    }
}

namespace FormatPass
{
    void blanks(FormatModel& model)
    {
        applyBlankLineAfterUsingBlock(model);
        applyBlankLinesBetweenFunctions(model);
    }
}

SWC_END_NAMESPACE();
