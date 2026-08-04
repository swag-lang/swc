#include "pch.h"
#include "Format/FormatPassUtil.h"
#include "Format/FormatPasses.h"
#include "Support/Report/Assert.h"

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
        Aliases,
        StructFields,
        EnumValues,
        Attributes,
        FatArrows,
        CaseBodies,
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
            runDeclarationFamily(AlignCategory::Declarations, options_->alignConsecutiveDeclarations, options_->alignDeclarationInitializers.value_or(false));
            runDeclarationFamily(AlignCategory::StructFields, options_->alignStructFields, options_->alignStructFieldInitializers.value_or(false));
            runDeclarationFamily(AlignCategory::Constants, options_->alignConsecutiveConstants, options_->alignConstantTypes.value_or(false));
            runCategory(AlignCategory::Aliases, options_->alignConsecutiveAliases);
            runCategory(AlignCategory::Assignments, options_->alignConsecutiveAssignments);
            runCategory(AlignCategory::EnumValues, options_->alignEnumValues);
            runCategory(AlignCategory::Attributes, options_->alignAttributes);
            runCategory(AlignCategory::FatArrows, options_->alignFatArrows);
            runCategory(AlignCategory::CaseBodies, options_->alignCaseBodies);
            runArrayColumns();
            repairHangingLines();
            runTrailingComments();
        }

    private:
        // The first piece on the line carrying `role` at the line's own depth.
        // With afterPiece, returns the piece that follows it instead (used to
        // anchor the type after `:` or the body after `case ... :`).
        uint32_t findRoleOnLine(const uint32_t lineStart, const FormatRoleE role, const bool afterPiece) const
        {
            const uint32_t declDepth = model_->piece(lineStart).depth;
            const uint32_t lineEnd   = FormatPassUtil::lineEndOf(*model_, lineStart);
            for (uint32_t i = lineStart; i != INVALID_PIECE && i <= lineEnd; i = model_->nextPiece(i))
            {
                const FormatPiece& piece = model_->piece(i);
                if (piece.hasRole(role) && piece.depth == declDepth)
                {
                    if (!afterPiece)
                        return i;
                    const uint32_t next = model_->nextPiece(i);
                    return next != INVALID_PIECE && next <= lineEnd ? next : INVALID_PIECE;
                }
            }
            return INVALID_PIECE;
        }

        // The piece whose start column gets aligned for this line, or
        // INVALID_PIECE when the line does not belong to the category.
        uint32_t anchorOf(const AlignCategory category, const uint32_t lineStart) const
        {
            const FormatPiece& first = model_->piece(lineStart);

            switch (category)
            {
                case AlignCategory::Assignments:
                    if (!first.hasRole(FormatRoleE::AssignStart))
                        return INVALID_PIECE;
                    return findRoleOnLine(lineStart, FormatRoleE::AssignOp, false);

                case AlignCategory::Declarations:
                    if (!first.hasRole(FormatRoleE::VarDeclStart))
                        return INVALID_PIECE;
                    return findRoleOnLine(lineStart, FormatRoleE::DeclColon, true);

                case AlignCategory::Constants:
                    if (!first.hasRole(FormatRoleE::ConstDeclStart))
                        return INVALID_PIECE;
                    return findRoleOnLine(lineStart, FormatRoleE::InitAssign, false);

                case AlignCategory::Aliases:
                    if (findRoleOnLine(lineStart, FormatRoleE::AliasDeclStart, false) == INVALID_PIECE)
                        return INVALID_PIECE;
                    return findRoleOnLine(lineStart, FormatRoleE::InitAssign, false);

                case AlignCategory::StructFields:
                    if (!first.hasRole(FormatRoleE::FieldDeclStart))
                        return INVALID_PIECE;
                    return findRoleOnLine(lineStart, FormatRoleE::DeclColon, true);

                case AlignCategory::EnumValues:
                    if (!first.hasRole(FormatRoleE::EnumValueStart))
                        return INVALID_PIECE;
                    return findRoleOnLine(lineStart, FormatRoleE::EnumAssign, false);

                case AlignCategory::FatArrows:
                    if (!first.hasRole(FormatRoleE::FuncDeclStart))
                        return INVALID_PIECE;
                    return findRoleOnLine(lineStart, FormatRoleE::FatArrow, false);

                case AlignCategory::CaseBodies:
                    if (!first.hasRole(FormatRoleE::CaseLabel))
                        return INVALID_PIECE;
                    return findRoleOnLine(lineStart, FormatRoleE::CaseColon, true);

                case AlignCategory::Attributes:
                {
                    if (first.hasRole(FormatRoleE::AttrOpen))
                        return INVALID_PIECE; // attribute starts the line: nothing to align
                    const uint32_t lineEnd = FormatPassUtil::lineEndOf(*model_, lineStart);
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

        bool lineIsTransparentFor(const AlignCategory category, const uint32_t lineStart) const
        {
            return category == AlignCategory::Aliases && model_->piece(lineStart).hasRole(FormatRoleE::AttrOpen);
        }

        uint32_t lineIndentColumn(const uint32_t lineStart) const
        {
            return FormatModel::textColumns(model_->lineIndentOf(lineStart), std::max(options_->tabWidth, 1u));
        }

        void runCategory(const AlignCategory category, const FormatAlignMode mode) const
        {
            if (mode == FormatAlignMode::Preserve)
                return;

            std::vector<std::pair<uint32_t, uint32_t>> group; // (lineStart, anchor)
            uint32_t                                   groupDepth  = 0;
            uint32_t                                   groupIndent = 0;

            auto flush = [&] {
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
                const uint32_t indent = lineIndentColumn(lineStart);

                if (anchor == INVALID_PIECE && lineIsTransparentFor(category, lineStart))
                {
                    if (!group.empty() && blank && mode == FormatAlignMode::Consecutive)
                        flush();
                    continue;
                }

                if (!group.empty())
                {
                    bool breaks = anchor != INVALID_PIECE && indent != groupIndent;
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
                {
                    groupDepth  = model_->piece(lineStart).depth;
                    groupIndent = indent;
                }
                group.emplace_back(lineStart, anchor);
            }

            flush();
        }

        void runDeclarationFamily(const AlignCategory category, const FormatAlignMode mode, const bool grid) const
        {
            if (grid)
                runDeclarationGrid(category, mode);
            else
                runCategory(category, mode);
        }

        static FormatRoleE declStartRole(const AlignCategory category)
        {
            switch (category)
            {
                case AlignCategory::Declarations:
                    return FormatRoleE::VarDeclStart;
                case AlignCategory::StructFields:
                    return FormatRoleE::FieldDeclStart;
                case AlignCategory::Constants:
                    return FormatRoleE::ConstDeclStart;
                case AlignCategory::Aliases:
                    SWC_ASSERT(false);
                    return FormatRoleE::AliasDeclStart;
                default:
                    SWC_ASSERT(false);
                    return FormatRoleE::VarDeclStart;
            }
        }

        // The type column (the piece after `:`), or INVALID_PIECE when the
        // declaration on this line is untyped.
        uint32_t typeAnchorOf(const uint32_t lineStart) const
        {
            return findRoleOnLine(lineStart, FormatRoleE::DeclColon, true);
        }

        // The initializer column (the `=` piece), or INVALID_PIECE when the
        // declaration on this line has no initializer.
        uint32_t initAnchorOf(const uint32_t lineStart) const
        {
            return findRoleOnLine(lineStart, FormatRoleE::InitAssign, false);
        }

        // A line joins a grid group when it is a declaration of the right kind
        // that owns at least one alignable column. Unlike the single-anchor
        // path, an untyped-but-initialized field still joins (via its `=`
        // column), so it no longer fragments the surrounding group.
        bool declLineHasColumn(const FormatRoleE startRole, const uint32_t lineStart) const
        {
            if (!model_->piece(lineStart).hasRole(startRole))
                return false;
            return typeAnchorOf(lineStart) != INVALID_PIECE || initAnchorOf(lineStart) != INVALID_PIECE;
        }

        // Two-column ("grid") alignment: within a run of declarations or struct
        // fields, align the type column (after `:`) and the initializer column
        // (`=`) independently, so lines that mix `name: Type`, `name = value`,
        // and `name: Type = value` line up in two stable columns.
        void runDeclarationGrid(const AlignCategory category, const FormatAlignMode mode) const
        {
            if (mode == FormatAlignMode::Preserve)
                return;

            const FormatRoleE     startRole = declStartRole(category);
            std::vector<uint32_t> group;
            uint32_t              groupDepth  = 0;
            uint32_t              groupIndent = 0;

            auto flush = [&] {
                alignGridGroup(group, mode == FormatAlignMode::None);
                group.clear();
            };

            for (const uint32_t lineStart : lineStarts_)
            {
                if (model_->piece(lineStart).removed)
                    continue;

                const bool     member = declLineHasColumn(startRole, lineStart);
                const bool     blank  = lineIsBlankSeparated(lineStart);
                const uint32_t indent = lineIndentColumn(lineStart);

                if (!group.empty())
                {
                    bool breaks = member && indent != groupIndent;
                    if (blank)
                    {
                        if (mode == FormatAlignMode::Consecutive)
                            breaks = true;
                        else if (mode == FormatAlignMode::AcrossBlanks && model_->gapNewlineCount(lineStart) > 2)
                            breaks = true;
                    }

                    if (!member)
                    {
                        if (mode != FormatAlignMode::All)
                            breaks = true;
                        else if (model_->piece(lineStart).depth < groupDepth || model_->piece(lineStart).is(TokenId::SymRightCurly))
                            breaks = true;
                    }

                    if (breaks)
                        flush();
                }

                if (!member)
                    continue;

                if (group.empty())
                {
                    groupDepth  = model_->piece(lineStart).depth;
                    groupIndent = indent;
                }
                group.push_back(lineStart);
            }

            flush();
        }

        // Aligns the type and initializer columns of one grid group. The type
        // column is padded first because widening it shifts every initializer;
        // alignGroup recomputes columns from the live model, so the second pass
        // sees the already-aligned types.
        void alignGridGroup(const std::vector<uint32_t>& group, const bool tightenOnly) const
        {
            std::vector<std::pair<uint32_t, uint32_t>> types; // (lineStart, type anchor)
            std::vector<std::pair<uint32_t, uint32_t>> inits; // (lineStart, `=` anchor)

            const auto collect = [&](std::vector<std::pair<uint32_t, uint32_t>>& out, const uint32_t lineStart, const uint32_t anchor) {
                if (anchor != INVALID_PIECE && FormatPassUtil::canEditGap(*model_, anchor) && !model_->gapHasNewline(anchor))
                    out.emplace_back(lineStart, anchor);
            };

            for (const uint32_t lineStart : group)
            {
                collect(types, lineStart, typeAnchorOf(lineStart));
                collect(inits, lineStart, initAnchorOf(lineStart));
            }

            // A single-line group is treated like any singleton: the columns
            // collapse to one space rather than keeping stale manual padding.
            if (tightenOnly)
            {
                unalignGroup(types);
                unalignGroup(inits);
                return;
            }

            alignGroup(types);
            alignGroup(inits);
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
        void runArrayColumns() const
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
            size_t                             elemCount = SIZE_MAX;

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

        // Padding an anchor pushes everything after it on that line to the
        // right, including any bracket a later line hangs inside. The indent
        // pass ran before this one, so those continuation lines still sit at
        // the pre-alignment column: move each one back under its bracket.
        // Records come in source order, so a bracket that itself lives on a
        // repaired line is already at its final column when it is read.
        void repairHangingLines() const
        {
            std::vector<PieceColumn> columns;

            for (const FormatHangingLine& hanging : model_->hangingLines())
            {
                if (!FormatPassUtil::canEditGap(*model_, hanging.lineStart) || model_->piece(hanging.openPiece).removed)
                    continue;

                const uint32_t newlines = model_->gapNewlineCount(hanging.lineStart);
                if (newlines == 0)
                    continue;

                FormatPassUtil::computeLineColumns(*model_, model_->lineStartOf(hanging.openPiece), &columns);
                uint32_t openColumn = UINT32_MAX;
                for (const PieceColumn& pc : columns)
                {
                    if (pc.piece == hanging.openPiece)
                    {
                        openColumn = pc.column;
                        break;
                    }
                }
                if (openColumn == UINT32_MAX)
                    continue;

                const uint32_t wanted = openColumn + hanging.offset;
                if (wanted == lineIndentColumn(hanging.lineStart))
                    continue;
                model_->setGapBreak(hanging.lineStart, newlines, FormatPassUtil::indentForColumns(*model_, wanted).view());
            }
        }

        void runTrailingComments() const
        {
            const FormatOptions& options = *options_;
            if (!options.alignTrailingComments)
                return;

            const bool     doAlign   = *options.alignTrailingComments;
            const uint32_t minSpaces = std::max(options.trailingCommentMinSpaces, 1u);

            std::vector<std::pair<uint32_t, uint32_t>> group; // (comment piece, code end column)
            uint32_t                                   groupIndent = 0;

            auto flush = [&] {
                if (group.empty())
                    return;

                uint32_t maxEnd = 0;
                for (const auto& endCol : group | std::views::values)
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

                const uint32_t indent = lineIndentColumn(lineStart);
                if (!group.empty() && indent != groupIndent)
                    flush();
                if (group.empty())
                    groupIndent = indent;
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
