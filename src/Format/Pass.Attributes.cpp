#include "pch.h"
#include "Format/FormatPassUtil.h"
#include "Format/FormatPasses.h"
#include "Support/Report/Assert.h"

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
        std::vector<uint32_t>   separators;
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
                separators.push_back(i);
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

        // Keep separators at their positional boundaries while moving complete
        // token sequences. Attribute names can contain different piece counts,
        // so the destination comma indices can move after sorting.
        struct SegmentSnapshot
        {
            std::vector<FormatPiece> pieces;
            std::vector<FormatGap>   innerGaps;
        };

        std::vector<SegmentSnapshot> snapshots(segments.size());
        std::vector<FormatGap>       leadingGaps(segments.size());
        for (size_t s = 0; s < segments.size(); ++s)
        {
            const PieceRange& range = segments[s];
            leadingGaps[s]          = model.gapBefore(range.first);
            for (uint32_t i = range.first; i <= range.last; ++i)
            {
                snapshots[s].pieces.push_back(model.piece(i));
                if (i != range.first)
                    snapshots[s].innerGaps.push_back(model.gapBefore(i));
            }
        }

        std::vector<FormatPiece> separatorPieces;
        std::vector<FormatGap>   separatorGaps;
        separatorPieces.reserve(separators.size());
        separatorGaps.reserve(separators.size());
        for (const uint32_t separator : separators)
        {
            separatorPieces.push_back(model.piece(separator));
            separatorGaps.push_back(model.gapBefore(separator));
        }

        uint32_t writeIndex = segments.front().first;
        for (size_t position = 0; position < order.size(); ++position)
        {
            const SegmentSnapshot& snapshot = snapshots[order[position]];
            for (size_t pieceIndex = 0; pieceIndex < snapshot.pieces.size(); ++pieceIndex)
            {
                model.piece(writeIndex) = snapshot.pieces[pieceIndex];
                model.gapBefore(writeIndex) =
                    pieceIndex == 0 ? leadingGaps[position] : snapshot.innerGaps[pieceIndex - 1];
                writeIndex++;
            }

            if (position < separatorPieces.size())
            {
                model.piece(writeIndex)     = separatorPieces[position];
                model.gapBefore(writeIndex) = separatorGaps[position];
                writeIndex++;
            }
        }

        SWC_ASSERT(writeIndex == closePiece);
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
