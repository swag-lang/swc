#include "pch.h"
#include "Format/FormatPasses.h"
#include "Format/FormatPassUtil.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    using FormatPassUtil::INVALID_PIECE;
    using FormatPassUtil::PieceColumn;

    enum class AlignCategory : uint8_t
    {
        Assignments,
        Declarations,
        Constants,
        StructFields,
        EnumValues,
        Attributes,
        FatArrows,
    };

    class AlignPass
    {
    public:
        explicit AlignPass(FormatModel& model) :
            model_(&model),
            options_(&model.options())
        {
            model.collectLineStarts(lineStarts_);
        }

        void run()
        {
            runCategory(AlignCategory::Declarations, options_->alignConsecutiveDeclarations);
            runCategory(AlignCategory::StructFields, options_->alignStructFields);
            runCategory(AlignCategory::Assignments, options_->alignConsecutiveAssignments);
            runCategory(AlignCategory::Constants, options_->alignConsecutiveConstants);
            runCategory(AlignCategory::EnumValues, options_->alignEnumValues);
            runCategory(AlignCategory::Attributes, options_->alignAttributes);
            runCategory(AlignCategory::FatArrows, options_->alignFatArrows);
            runArrayColumns();
            runTrailingComments();
        }

    private:
        // The piece whose start column gets aligned for this line, or
        // INVALID_PIECE when the line does not belong to the category.
        uint32_t anchorOf(const AlignCategory category, const uint32_t lineStart) const
        {
            const FormatPiece& first   = model_->piece(lineStart);
            const uint32_t     lineEnd = FormatPassUtil::lineEndOf(*model_, lineStart);

            const auto findRole = [&](const FormatRoleE role, const bool afterPiece) -> uint32_t {
                for (uint32_t i = lineStart; i != INVALID_PIECE && i <= lineEnd; i = model_->nextPiece(i))
                {
                    const FormatPiece& piece = model_->piece(i);
                    if (piece.hasRole(role) && piece.depth == first.depth)
                    {
                        if (!afterPiece)
                            return i;
                        const uint32_t next = model_->nextPiece(i);
                        return next != INVALID_PIECE && next <= lineEnd ? next : INVALID_PIECE;
                    }
                }
                return INVALID_PIECE;
            };

            switch (category)
            {
                case AlignCategory::Assignments:
                    if (!first.hasRole(FormatRoleE::AssignStart))
                        return INVALID_PIECE;
                    return findRole(FormatRoleE::AssignOp, false);

                case AlignCategory::Declarations:
                    if (!first.hasRole(FormatRoleE::VarDeclStart))
                        return INVALID_PIECE;
                    return findRole(FormatRoleE::DeclColon, true);

                case AlignCategory::Constants:
                    if (!first.hasRole(FormatRoleE::ConstDeclStart))
                        return INVALID_PIECE;
                    return findRole(FormatRoleE::InitAssign, false);

                case AlignCategory::StructFields:
                    if (!first.hasRole(FormatRoleE::FieldDeclStart))
                        return INVALID_PIECE;
                    return findRole(FormatRoleE::DeclColon, true);

                case AlignCategory::EnumValues:
                    if (!first.hasRole(FormatRoleE::EnumValueStart))
                        return INVALID_PIECE;
                    return findRole(FormatRoleE::EnumAssign, false);

                case AlignCategory::FatArrows:
                    if (!first.hasRole(FormatRoleE::FuncDeclStart))
                        return INVALID_PIECE;
                    return findRole(FormatRoleE::FatArrow, false);

                case AlignCategory::Attributes:
                {
                    if (first.hasRole(FormatRoleE::AttrOpen))
                        return INVALID_PIECE; // attribute starts the line: nothing to align
                    for (uint32_t i = model_->nextPiece(lineStart); i != INVALID_PIECE && i <= lineEnd; i = model_->nextPiece(i))
                    {
                        if (model_->piece(i).hasRole(FormatRoleE::AttrOpen))
                            return i;
                    }
                    return INVALID_PIECE;
                }
            }

            return INVALID_PIECE;
        }

        bool lineIsBlankSeparated(const uint32_t lineStart) const
        {
            return model_->gapNewlineCount(lineStart) > 1;
        }

        bool lineIsCommentOnly(const uint32_t lineStart) const
        {
            return model_->piece(lineStart).isComment && FormatPassUtil::lineEndOf(*model_, lineStart) == lineStart;
        }

        void runCategory(const AlignCategory category, const FormatAlignMode mode)
        {
            if (mode == FormatAlignMode::Preserve)
                return;

            std::vector<std::pair<uint32_t, uint32_t>> group; // (lineStart, anchor)
            uint32_t                                   groupDepth = 0;

            auto flush = [&]() {
                if (mode == FormatAlignMode::None)
                    unalignGroup(group);
                else if (group.size() >= 2)
                    alignGroup(group);
                else
                    unalignGroup(group); // lone line: stale manual padding shrinks to one space
                group.clear();
            };

            for (const uint32_t lineStart : lineStarts_)
            {
                if (model_->piece(lineStart).removed)
                    continue;

                const uint32_t anchor = anchorOf(category, lineStart);
                const bool     blank  = lineIsBlankSeparated(lineStart);

                if (!group.empty())
                {
                    bool breaks = false;
                    if (blank)
                    {
                        if (mode == FormatAlignMode::Consecutive)
                            breaks = true;
                        else if (mode == FormatAlignMode::AcrossBlanks && model_->gapNewlineCount(lineStart) > 2)
                            breaks = true;
                    }

                    if (anchor == INVALID_PIECE)
                    {
                        if (mode != FormatAlignMode::All)
                            breaks = true;
                        else if (model_->piece(lineStart).depth < groupDepth || model_->piece(lineStart).is(TokenId::SymRightCurly))
                            breaks = true;
                    }

                    if (breaks)
                        flush();
                }

                if (anchor == INVALID_PIECE)
                    continue;
                if (!FormatPassUtil::canEditGap(*model_, anchor) || model_->gapHasNewline(anchor))
                    continue;

                if (group.empty())
                    groupDepth = model_->piece(lineStart).depth;
                group.emplace_back(lineStart, anchor);
            }

            flush();
        }

        void alignGroup(const std::vector<std::pair<uint32_t, uint32_t>>& group) const
        {
            std::vector<PieceColumn> columns;

            // Compute the natural (unpadded) anchor column of each line: the
            // column the anchor would occupy with a single space before it.
            std::vector<uint32_t> naturalCols(group.size());
            std::vector<uint32_t> currentCols(group.size());
            uint32_t              target = 0;

            for (size_t i = 0; i < group.size(); ++i)
            {
                const auto [lineStart, anchor] = group[i];
                FormatPassUtil::computeLineColumns(*model_, lineStart, &columns);

                uint32_t anchorCol = 0;
                uint32_t prevEnd   = 0;
                for (const PieceColumn& pc : columns)
                {
                    if (pc.piece == anchor)
                    {
                        anchorCol = pc.column;
                        break;
                    }
                    prevEnd = pc.column + FormatModel::textColumns(model_->piece(pc.piece).text, std::max(options_->tabWidth, 1u), pc.column);
                }

                naturalCols[i] = prevEnd + 1;
                currentCols[i] = anchorCol;
                target         = std::max(target, naturalCols[i]);
            }

            for (size_t i = 0; i < group.size(); ++i)
            {
                const auto [lineStart, anchor] = group[i];
                SWC_UNUSED(lineStart);

                // Pad the gap so the anchor lands on the target column.
                const uint32_t prevEndCol = currentCols[i] - model_->gapColumns(anchor);
                if (target > prevEndCol && currentCols[i] != target)
                    model_->setGapSpaces(anchor, target - prevEndCol);
            }
        }

        void unalignGroup(const std::vector<std::pair<uint32_t, uint32_t>>& group) const
        {
            for (const auto& [lineStart, anchor] : group)
            {
                SWC_UNUSED(lineStart);
                if (model_->gapColumns(anchor) != 1)
                    model_->setGapSpaces(anchor, 1);
            }
        }

        // Aligns the columns of a multi-line array literal whose rows are
        // single-line `{ ... }` literals: element k starts at the same column
        // on every row. Rows with comments, ragged element counts, or scalar
        // entries leave the literal untouched.
        void runArrayColumns()
        {
            if (!options_->alignArrayColumns.value_or(false))
                return;

            for (uint32_t i = 0; i < model_->numPieces(); ++i)
            {
                const FormatPiece& open = model_->piece(i);
                if (open.removed || open.frozen || open.isNot(TokenId::SymLeftBracket) || open.match == INVALID_PIECE)
                    continue;

                bool multiLine = false;
                for (uint32_t p = i + 1; p <= open.match && !multiLine; ++p)
                {
                    if (!model_->piece(p).removed && model_->gapHasNewline(p))
                        multiLine = true;
                }
                if (!multiLine)
                    continue;

                const std::vector<std::vector<uint32_t>> rows = collectArrayRows(i, open.match, open.depth + 1);
                if (rows.size() < 2)
                    continue;

                // Pad column by column; later columns shift, so recompute per column.
                const size_t elemCount = rows.front().size();
                for (size_t k = 1; k < elemCount; ++k)
                {
                    uint32_t              target = 0;
                    std::vector<uint32_t> currentCols(rows.size());
                    std::vector<uint32_t> naturalCols(rows.size());
                    for (size_t r = 0; r < rows.size(); ++r)
                    {
                        std::vector<PieceColumn> columns;
                        FormatPassUtil::computeLineColumns(*model_, model_->lineStartOf(rows[r][k]), &columns);
                        uint32_t prevEnd = 0;
                        for (const PieceColumn& pc : columns)
                        {
                            if (pc.piece == rows[r][k])
                            {
                                currentCols[r] = pc.column;
                                break;
                            }
                            prevEnd = pc.column + FormatModel::textColumns(model_->piece(pc.piece).text, std::max(options_->tabWidth, 1u), pc.column);
                        }
                        naturalCols[r] = prevEnd + 1;
                        target         = std::max(target, naturalCols[r]);
                    }

                    for (size_t r = 0; r < rows.size(); ++r)
                    {
                        const uint32_t prevEndCol = currentCols[r] - model_->gapColumns(rows[r][k]);
                        if (target > prevEndCol && currentCols[r] != target)
                            model_->setGapSpaces(rows[r][k], target - prevEndCol);
                    }
                }
            }
        }

        // The element-start pieces of each `{ ... }` row, or empty when the
        // literal does not qualify (scalar rows, comments, ragged counts, ...).
        std::vector<std::vector<uint32_t>> collectArrayRows(const uint32_t openPiece, const uint32_t closePiece, const uint32_t rowDepth) const
        {
            std::vector<std::vector<uint32_t>> rows;
            size_t elemCount = SIZE_MAX;

            for (uint32_t p = openPiece + 1; p < closePiece; ++p)
            {
                const FormatPiece& piece = model_->piece(p);
                if (piece.removed)
                    continue;
                if (piece.depth != rowDepth)
                    return {}; // stray content outside a row
                if (piece.is(TokenId::SymComma))
                    continue;
                if (piece.isComment || piece.isNot(TokenId::SymLeftCurly) || piece.match == INVALID_PIECE || piece.match >= closePiece)
                    return {};
                if (model_->lineStartOf(p) != p)
                    return {}; // each row starts its own line

                std::vector<uint32_t> elems;
                uint32_t              last = p;
                for (uint32_t q = p + 1; q < piece.match; ++q)
                {
                    const FormatPiece& inner = model_->piece(q);
                    if (inner.removed)
                        continue;
                    if (model_->gapHasNewline(q))
                        return {}; // rows must be single-line
                    if (inner.isComment)
                        return {};
                    if (last == p)
                        elems.push_back(q);
                    else if (inner.is(TokenId::SymComma) && inner.depth == rowDepth + 1)
                    {
                        const uint32_t next = model_->nextPiece(q);
                        if (next != INVALID_PIECE && next < piece.match)
                        {
                            if (!FormatPassUtil::canEditGap(*model_, next))
                                return {};
                            elems.push_back(next);
                        }
                    }
                    last = q;
                }
                if (model_->gapHasNewline(piece.match))
                    return {};

                if (elemCount == SIZE_MAX)
                    elemCount = elems.size();
                else if (elems.size() != elemCount)
                    return {}; // ragged rows
                rows.push_back(std::move(elems));
                p = piece.match;
            }

            if (elemCount == SIZE_MAX || elemCount < 2)
                return {};
            return rows;
        }

        void runTrailingComments()
        {
            const FormatOptions& options = *options_;
            if (!options.alignTrailingComments)
                return;

            const bool     doAlign   = *options.alignTrailingComments;
            const uint32_t minSpaces = std::max(options.trailingCommentMinSpaces, 1u);

            std::vector<std::pair<uint32_t, uint32_t>> group; // (comment piece, code end column)

            auto flush = [&]() {
                if (group.empty())
                    return;

                uint32_t maxEnd = 0;
                for (const auto& [comment, endCol] : group)
                    maxEnd = std::max(maxEnd, endCol);

                uint32_t target = maxEnd + minSpaces;
                if (doAlign && options.trailingCommentMaxColumn > 0)
                    target = std::min(target, std::max(options.trailingCommentMaxColumn, maxEnd + 1));

                for (const auto& [comment, endCol] : group)
                {
                    const uint32_t wanted = doAlign ? target - endCol : minSpaces;
                    if (model_->gapColumns(comment) != wanted)
                        model_->setGapSpaces(comment, wanted);
                }
                group.clear();
            };

            std::vector<PieceColumn> columns;
            for (const uint32_t lineStart : lineStarts_)
            {
                if (model_->piece(lineStart).removed)
                    continue;
                if (lineIsBlankSeparated(lineStart) || lineIsCommentOnly(lineStart))
                {
                    flush();
                    if (lineIsCommentOnly(lineStart))
                        continue;
                }

                const uint32_t lineEnd = FormatPassUtil::lineEndOf(*model_, lineStart);
                if (!model_->piece(lineEnd).isComment || lineEnd == lineStart)
                {
                    flush();
                    continue;
                }
                if (!FormatPassUtil::canEditGap(*model_, lineEnd) || model_->gapHasNewline(lineEnd))
                {
                    flush();
                    continue;
                }

                FormatPassUtil::computeLineColumns(*model_, lineStart, &columns);
                uint32_t endCol = 0;
                for (const PieceColumn& pc : columns)
                {
                    if (pc.piece == lineEnd)
                        break;
                    endCol = pc.column + FormatModel::textColumns(model_->piece(pc.piece).text, std::max(options_->tabWidth, 1u), pc.column);
                }

                group.emplace_back(lineEnd, endCol);
            }

            flush();
        }

        FormatModel*          model_;
        const FormatOptions*  options_;
        std::vector<uint32_t> lineStarts_;
    };
}

namespace FormatPass
{
    void align(FormatModel& model)
    {
        AlignPass(model).run();
    }
}

SWC_END_NAMESPACE();
