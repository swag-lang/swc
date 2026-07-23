#include "pch.h"
#include "Format/FormatPasses.h"
#include "Format/FormatPassUtil.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    using FormatPassUtil::INVALID_PIECE;
    using FormatPassUtil::PieceRange;

    // Sorts the attributes inside a single `#[A, B, C]` list alphabetically.
    void sortAttributeArgumentsIn(FormatModel& model, const uint32_t openPiece)
    {
        const uint32_t closePiece = model.piece(openPiece).match;
        const uint32_t innerDepth = model.piece(openPiece).depth + 1;

        // Segment boundaries: the commas at the list's own depth.
        std::vector<PieceRange> segments;
        std::vector<Utf8>       keys;
        uint32_t                segmentStart = INVALID_PIECE;
        Utf8                    key;

        for (uint32_t i = openPiece + 1; i < closePiece; ++i)
        {
            const FormatPiece& piece = model.piece(i);
            if (piece.removed)
                continue;
            if (piece.frozen || piece.isComment || piece.is(TokenId::SymLeftCurly))
                return; // keep unusual lists untouched
            if (model.gapHasNewline(i))
                return; // multi-line lists are left as written

            if (piece.is(TokenId::SymComma) && piece.depth == innerDepth)
            {
                if (segmentStart == INVALID_PIECE)
                    return;
                segments.push_back({segmentStart, model.prevPiece(i)});
                keys.push_back(std::move(key));
                key.clear();
                segmentStart = INVALID_PIECE;
                continue;
            }

            if (segmentStart == INVALID_PIECE)
                segmentStart = i;
            key += piece.text;
        }

        if (segmentStart == INVALID_PIECE)
            return;
        segments.push_back({segmentStart, model.prevPiece(closePiece)});
        keys.push_back(std::move(key));

        if (segments.size() < 2)
            return;

        // The reorder helper needs contiguous segments: the separating commas
        // stay in place because each segment ends right before a comma and the
        // next segment starts right after it... which is NOT contiguous.
        // Instead, extend each segment (but the last) to include its comma and
        // sort on the attribute text only.
        std::vector<uint32_t> order(segments.size());
        for (uint32_t i = 0; i < order.size(); ++i)
            order[i] = i;
        std::ranges::stable_sort(order, [&](const uint32_t a, const uint32_t b) { return keys[a].view() < keys[b].view(); });

        bool identity = true;
        for (uint32_t i = 0; i < order.size(); ++i)
        {
            if (order[i] != i)
                identity = false;
        }
        if (identity)
            return;

        // Snapshot each attribute's text, then rewrite the segments in sorted
        // order. Pieces counts differ between attributes, so rebuild through
        // the generic segment reorder on comma-extended ranges is unsound;
        // instead, replace the text of a synthetic single piece per segment.
        // Simplest robust rewrite: replace the whole list content by text.
        Utf8 rebuilt;
        for (size_t s = 0; s < order.size(); ++s)
        {
            if (s != 0)
                rebuilt += ", ";
            const PieceRange& range = segments[order[s]];
            for (uint32_t i = range.first; i <= range.last; ++i)
            {
                if (model.piece(i).removed)
                    continue;
                if (i != range.first && model.gapColumns(i) > 0)
                    rebuilt.append(model.gapColumns(i), ' ');
                rebuilt += model.piece(i).text;
            }
        }

        // Collapse the content into the first piece and drop the others.
        const uint32_t first = segments.front().first;
        model.replaceText(first, std::move(rebuilt));
        for (uint32_t i = model.nextPiece(first); i != INVALID_PIECE && i < closePiece; i = model.nextPiece(i))
            model.removePiece(i);
        model.setGapSpaces(closePiece, 0);
        model.computeBrackets();
    }

    void applyPlacement(FormatModel& model)
    {
        const FormatOptions& options = model.options();

        const bool breakAfter = options.breakAfterAttribute.value_or(false) ||
                                options.attributePlacement == FormatAttributePlacement::OwnLine ||
                                options.attributePlacement == FormatAttributePlacement::Grouped;
        const bool joinAfter = !options.breakAfterAttribute.value_or(true) ||
                               options.attributePlacement == FormatAttributePlacement::Inline;

        if (!breakAfter && !joinAfter)
            return;

        for (uint32_t i = 0; i < model.numPieces(); ++i)
        {
            const FormatPiece& piece = model.piece(i);
            if (piece.removed || !piece.hasRole(FormatRoleE::AttrClose))
                continue;

            const uint32_t next = model.nextPiece(i);
            if (next == INVALID_PIECE || !FormatPassUtil::canEditGap(model, next))
                continue;
            if (model.piece(next).isComment)
                continue;
            // Only between the attribute and the declaration it annotates: the
            // next piece must start a statement or another attribute list.
            if (!model.piece(next).roles.hasAny({FormatRoleE::AttrOpen, FormatRoleE::StmtStart, FormatRoleE::FuncDeclStart, FormatRoleE::VarDeclStart, FormatRoleE::ConstDeclStart, FormatRoleE::FieldDeclStart, FormatRoleE::EnumValueStart}))
                continue;

            const bool hasBreak = model.gapHasNewline(next);
            if (breakAfter && !hasBreak)
            {
                const uint32_t attrOpen = piece.match;
                model.setGapBreak(next, 1, model.lineIndentOf(attrOpen != INVALID_PIECE ? attrOpen : i));
            }
            else if (joinAfter && hasBreak)
            {
                model.setGapSpaces(next, 1);
            }
        }
    }

    void applyGrouping(FormatModel& model)
    {
        if (model.options().attributePlacement != FormatAttributePlacement::Grouped)
            return;

        for (uint32_t i = 0; i < model.numPieces(); ++i)
        {
            FormatPiece& closePiece = model.piece(i);
            if (closePiece.removed || !closePiece.hasRole(FormatRoleE::AttrClose) || closePiece.frozen)
                continue;

            const uint32_t next = model.nextPiece(i);
            if (next == INVALID_PIECE)
                continue;

            FormatPiece& nextOpen = model.piece(next);
            if (!nextOpen.hasRole(FormatRoleE::AttrOpen) || nextOpen.frozen)
                continue;
            if (!FormatPassUtil::canEditGap(model, next))
                continue;

            const uint32_t contentStart = model.nextPiece(next);
            if (contentStart == INVALID_PIECE)
                continue;

            // `... ] #[ ...` becomes `... , ...` inside a single list.
            closePiece.roles.remove(FormatRoleE::AttrClose);
            closePiece.roles.add(FormatRoleE::AttrComma);
            model.replaceText(i, ",");
            model.setGapSpaces(i, 0);

            nextOpen.roles.remove(FormatRoleE::AttrOpen);
            model.removePiece(next);
            model.setGapSpaces(contentStart, 1);
        }

        model.computeBrackets();
    }
}

namespace FormatPass
{
    void attributes(FormatModel& model)
    {
        const FormatOptions& options = model.options();

        if (options.sortAttributeArguments.value_or(false))
        {
            for (uint32_t i = 0; i < model.numPieces(); ++i)
            {
                const FormatPiece& piece = model.piece(i);
                if (!piece.removed && !piece.frozen && piece.hasRole(FormatRoleE::AttrOpen) && piece.match != INVALID_PIECE)
                    sortAttributeArgumentsIn(model, i);
            }
        }

        applyGrouping(model);
        applyPlacement(model);
    }
}

SWC_END_NAMESPACE();
