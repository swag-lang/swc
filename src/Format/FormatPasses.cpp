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

        std::vector<SegmentSnapshot> snapshots(segments.size());
        std::vector<FormatGap>       leadingGaps(segments.size());

        for (size_t s = 0; s < segments.size(); ++s)
        {
            const PieceRange& range = segments[s];
            SWC_ASSERT(range.first != INVALID_PIECE && range.last >= range.first);
            snapshotSegment(model, range, snapshots[s], leadingGaps[s]);
        }

        // Write the permuted segments back. Segments must be contiguous:
        // segment s+1 starts right after segment s ends.
        uint32_t writeIndex = segments.front().first;
        for (size_t s = 0; s < segments.size(); ++s)
        {
            const SegmentSnapshot& segment = snapshots[order[s]];

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
        statements(model);
        attributes(model);
        shortBlocks(model);
        braces(model);

        blanks(model);
        spacing(model);
        indent(model);
        wrap(model);
        caseBodies(model);
        caseBlanks(model);

        redundantSemicolons(model);
        comments(model);

        align(model);
    }
}

SWC_END_NAMESPACE();
