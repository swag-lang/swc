#include "pch.h"
#include "Format/FormatPasses.h"
#include "Format/FormatPassUtil.h"
#include "Support/Report/Assert.h"

SWC_BEGIN_NAMESPACE();

namespace FormatPassUtil
{
    void reorderSegments(FormatModel& model, const std::vector<PieceRange>& segments, const std::vector<uint32_t>& order)
    {
        SWC_ASSERT(segments.size() == order.size());
        if (segments.empty())
            return;

        bool identity = true;
        for (uint32_t i = 0; i < order.size(); ++i)
        {
            if (order[i] != i)
            {
                identity = false;
                break;
            }
        }
        if (identity)
            return;

        // Snapshot the pieces and inner gaps of each segment, plus the leading
        // gap of each segment *position*.
        struct Segment
        {
            std::vector<FormatPiece> pieces;
            std::vector<FormatGap>   innerGaps; // gaps before pieces[1..]
        };

        std::vector<Segment>   snapshots(segments.size());
        std::vector<FormatGap> leadingGaps(segments.size());

        for (size_t s = 0; s < segments.size(); ++s)
        {
            const PieceRange& range = segments[s];
            SWC_ASSERT(range.first != INVALID_PIECE && range.last >= range.first);
            leadingGaps[s] = model.gapBefore(range.first);
            for (uint32_t i = range.first; i <= range.last; ++i)
            {
                snapshots[s].pieces.push_back(model.piece(i));
                if (i != range.first)
                    snapshots[s].innerGaps.push_back(model.gapBefore(i));
            }
        }

        // Write the permuted segments back. Segments must be contiguous:
        // segment s+1 starts right after segment s ends.
        uint32_t writeIndex = segments.front().first;
        for (size_t s = 0; s < segments.size(); ++s)
        {
            const Segment& segment = snapshots[order[s]];

            model.gapBefore(writeIndex) = leadingGaps[s];
            for (size_t p = 0; p < segment.pieces.size(); ++p)
            {
                model.piece(writeIndex) = segment.pieces[p];
                if (p != 0)
                    model.gapBefore(writeIndex) = segment.innerGaps[p - 1];
                writeIndex++;
            }
        }

        model.computeBrackets();
    }
}

namespace FormatPass
{
    void runAll(FormatModel& model)
    {
        sortUsing(model);
        attributes(model);
        shortBlocks(model);
        braces(model);
        blanks(model);
        spacing(model);
        indent(model);
        wrap(model);
        comments(model);
        align(model);
    }
}

SWC_END_NAMESPACE();
