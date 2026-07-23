#include "pch.h"
#include "Format/FormatPasses.h"
#include "Format/FormatPassUtil.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    using FormatPassUtil::INVALID_PIECE;
    using FormatPassUtil::PieceRange;

    struct UsingStatement
    {
        PieceRange range;
        Utf8       sortKey;
        bool       plainIdentifiers = true; // only `using A.B.C` (mergeable)
    };

    // Collects a run of consecutive single-line top-level `using` statements
    // starting at line `firstLine` (index into lineStarts).
    size_t collectRun(const FormatModel& model, const std::vector<uint32_t>& lineStarts, const size_t firstLine, std::vector<UsingStatement>& out)
    {
        out.clear();
        size_t line = firstLine;

        while (line < lineStarts.size())
        {
            const uint32_t     lineStart = lineStarts[line];
            const FormatPiece& piece     = model.piece(lineStart);

            if (!piece.hasRole(FormatRoleE::UsingStart) || piece.isNot(TokenId::KwdUsing))
                break;
            if (line != firstLine && model.gapNewlineCount(lineStart) > 1)
                break; // a blank line splits the run

            const uint32_t lineEnd = FormatPassUtil::lineEndOf(model, lineStart);

            UsingStatement stmt;
            stmt.range = {lineStart, lineEnd};

            bool editable = FormatPassUtil::canEditGap(model, lineStart);
            for (uint32_t i = lineStart; i <= lineEnd && editable; ++i)
            {
                const FormatPiece& cur = model.piece(i);
                if (cur.frozen || cur.isComment)
                    editable = false; // keep runs with comments untouched
                if (i != lineStart)
                {
                    if (cur.isNot(TokenId::Identifier) && cur.isNot(TokenId::SymDot) && cur.isNot(TokenId::SymComma))
                        stmt.plainIdentifiers = false;
                    stmt.sortKey += cur.text;
                }
            }

            if (!editable)
                break;

            out.push_back(std::move(stmt));
            line++;
        }

        return line;
    }

    void sortRun(FormatModel& model, std::vector<UsingStatement>& run)
    {
        if (run.size() < 2)
            return;

        const bool caseInsensitive = model.options().sortUsingStatements == FormatSortOrder::CaseInsensitiveAscending;

        std::vector<uint32_t> order(run.size());
        for (uint32_t i = 0; i < order.size(); ++i)
            order[i] = i;

        std::ranges::stable_sort(order, [&](const uint32_t a, const uint32_t b) {
            if (!caseInsensitive)
                return run[a].sortKey.view() < run[b].sortKey.view();
            Utf8 ka = run[a].sortKey;
            Utf8 kb = run[b].sortKey;
            ka.make_lower();
            kb.make_lower();
            return ka.view() < kb.view();
        });

        std::vector<PieceRange> segments;
        segments.reserve(run.size());
        for (const UsingStatement& stmt : run)
            segments.push_back(stmt.range);

        FormatPassUtil::reorderSegments(model, segments, order);
    }

    void mergeRun(FormatModel& model, const std::vector<UsingStatement>& run)
    {
        if (run.size() < 2)
            return;

        for (const UsingStatement& stmt : run)
        {
            if (!stmt.plainIdentifiers)
                return;
        }

        // Rewrite `using B` lines as `, B` appended to the first statement.
        // The extra `using` keywords become the separating commas.
        for (size_t s = 1; s < run.size(); ++s)
        {
            const uint32_t usingPiece = run[s].range.first;
            model.piece(usingPiece).roles.remove(FormatRoleE::UsingStart);
            model.piece(usingPiece).roles.remove(FormatRoleE::StmtStart);
            model.replaceText(usingPiece, ",");
            model.setGapSpaces(usingPiece, 0);

            const uint32_t firstIdent = model.nextPiece(usingPiece);
            if (firstIdent != INVALID_PIECE)
                model.setGapSpaces(firstIdent, 1);
        }
    }

    template<typename FN>
    void forEachRun(FormatModel& model, FN apply)
    {
        std::vector<uint32_t> lineStarts;
        model.collectLineStarts(lineStarts);

        std::vector<UsingStatement> run;
        size_t line = 0;
        while (line < lineStarts.size())
        {
            const FormatPiece& piece = model.piece(lineStarts[line]);
            if (!piece.hasRole(FormatRoleE::UsingStart) || piece.isNot(TokenId::KwdUsing) || piece.frozen)
            {
                line++;
                continue;
            }

            const size_t nextLine = collectRun(model, lineStarts, line, run);
            apply(run);
            line = std::max(nextLine, line + 1);
        }
    }

    void applyUsingPass(FormatModel& model)
    {
        const FormatOptions& options = model.options();
        const bool sortWanted  = options.sortUsingStatements != FormatSortOrder::Preserve;
        const bool mergeWanted = options.mergeUsingStatements.value_or(false);
        if (!sortWanted && !mergeWanted)
            return;

        // Sorting permutes pieces and shifts line-start indices, so the merge
        // phase rescans the model from scratch.
        if (sortWanted)
            forEachRun(model, [&](std::vector<UsingStatement>& run) { sortRun(model, run); });
        if (mergeWanted)
            forEachRun(model, [&](const std::vector<UsingStatement>& run) { mergeRun(model, run); });
    }
}

namespace FormatPass
{
    void sortUsing(FormatModel& model)
    {
        applyUsingPass(model);
    }
}

SWC_END_NAMESPACE();
