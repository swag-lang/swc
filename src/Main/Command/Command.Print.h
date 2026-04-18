#pragma once

#include "Support/Core/Utf8Helper.h"
#include "Support/Report/Logger.h"

SWC_BEGIN_NAMESPACE();

namespace CommandPrint
{
    inline constexpr LogColor helpArgumentLabelColor()
    {
        return LogColor::BrightBlue;
    }

    inline Logger::FieldGroupStyle infoGroupStyle(const bool blankLineBefore, const size_t maxLabelWidth = 24)
    {
        Logger::FieldGroupStyle style;
        style.blankLineBefore = blankLineBefore;
        style.maxLabelWidth   = maxLabelWidth;
        return style;
    }

    inline Logger::FieldGroupStyle nextInfoGroupStyle(bool& hasPrintedGroup, const size_t maxLabelWidth = 24)
    {
        const Logger::FieldGroupStyle style = infoGroupStyle(hasPrintedGroup, maxLabelWidth);
        hasPrintedGroup                     = true;
        return style;
    }

    inline Logger::FieldGroupStyle helpGroupStyle(const bool blankLineBefore, const size_t maxLabelWidth = 34)
    {
        Logger::FieldGroupStyle style = infoGroupStyle(blankLineBefore, maxLabelWidth);
        if (style.maxLabelWidth < style.minLabelWidth)
            style.maxLabelWidth = style.minLabelWidth;
        return style;
    }

    inline Logger::FieldGroupStyle nextHelpGroupStyle(bool& hasPrintedGroup, const size_t maxLabelWidth = 34)
    {
        const Logger::FieldGroupStyle style = helpGroupStyle(hasPrintedGroup, maxLabelWidth);
        hasPrintedGroup                     = true;
        return style;
    }

    inline void addInfoEntry(std::vector<Logger::FieldEntry>& entries, const std::string_view label, Utf8 value, LogColor valueColor = LogColor::White, const uint32_t indentLevel = 0, const LogColor labelColor = LogColor::Gray)
    {
        if (value.empty())
        {
            value = "<empty>";
            if (valueColor == LogColor::White)
                valueColor = LogColor::Gray;
        }

        Logger::FieldEntry entry;
        entry.label       = Utf8(label);
        entry.value       = std::move(value);
        entry.labelColor  = labelColor;
        entry.valueColor  = valueColor;
        entry.indentLevel = indentLevel;
        entries.push_back(std::move(entry));
    }

    inline void addInfoEntry(std::vector<Logger::FieldEntry>& entries, const std::string_view label, const char* value, const LogColor valueColor = LogColor::White, const uint32_t indentLevel = 0, const LogColor labelColor = LogColor::Gray)
    {
        addInfoEntry(entries, label, Utf8(value), valueColor, indentLevel, labelColor);
    }

    inline void addInfoEntry(std::vector<Logger::FieldEntry>& entries, const std::string_view label, const std::string& value, const LogColor valueColor = LogColor::White, const uint32_t indentLevel = 0, const LogColor labelColor = LogColor::Gray)
    {
        addInfoEntry(entries, label, Utf8(value), valueColor, indentLevel, labelColor);
    }

    inline void addInfoEntry(std::vector<Logger::FieldEntry>& entries, const std::string_view label, const std::string_view value, const LogColor valueColor = LogColor::White, const uint32_t indentLevel = 0, const LogColor labelColor = LogColor::Gray)
    {
        addInfoEntry(entries, label, Utf8(value), valueColor, indentLevel, labelColor);
    }

    inline void addInfoEntry(std::vector<Logger::FieldEntry>& entries, const std::string_view label, const fs::path& value, const LogColor valueColor = LogColor::White, const uint32_t indentLevel = 0, const LogColor labelColor = LogColor::Gray)
    {
        addInfoEntry(entries, label, Utf8(value), valueColor, indentLevel, labelColor);
    }

    inline void addInfoEntryParts(std::vector<Logger::FieldEntry>& entries, const std::string_view label, std::vector<Logger::FieldValuePart> valueParts, const uint32_t indentLevel = 0, const LogColor labelColor = LogColor::Gray)
    {
        if (valueParts.empty())
        {
            addInfoEntry(entries, label, "<empty>", LogColor::Gray, indentLevel, labelColor);
            return;
        }

        Logger::FieldEntry entry;
        entry.label       = Utf8(label);
        entry.labelColor  = labelColor;
        entry.indentLevel = indentLevel;
        entry.valueParts  = std::move(valueParts);
        entries.push_back(std::move(entry));
    }

    inline void addBoolEntry(std::vector<Logger::FieldEntry>& entries, const std::string_view label, const bool enabled)
    {
        addInfoEntry(entries, label, enabled ? "on" : "off", enabled ? LogColor::BrightGreen : LogColor::Gray);
    }

    inline void addUtf8Set(std::vector<Logger::FieldEntry>& entries, const std::string_view label, const std::set<Utf8>& values)
    {
        if (values.empty())
        {
            addInfoEntry(entries, label, "<empty>", LogColor::Gray);
            return;
        }

        addInfoEntry(entries, label, Utf8Helper::countWithLabel(values.size(), "entry"));
        uint32_t index = 0;
        for (const Utf8& value : values)
            addInfoEntry(entries, std::format("[{}]", index++), value, LogColor::White, 1);
    }

    inline void addPathSet(std::vector<Logger::FieldEntry>& entries, const std::string_view label, const std::set<fs::path>& values)
    {
        if (values.empty())
        {
            addInfoEntry(entries, label, "<empty>", LogColor::Gray);
            return;
        }

        addInfoEntry(entries, label, Utf8Helper::countWithLabel(values.size(), "entry"));
        uint32_t index = 0;
        for (const fs::path& value : values)
            addInfoEntry(entries, std::format("[{}]", index++), value, LogColor::White, 1);
    }
}

SWC_END_NAMESPACE();
