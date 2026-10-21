#pragma once
#include "Support/Core/Utf8.h"

#include "Main/Version.h"
#include "Support/Core/Utf8Helper.h"
#include "Support/Os/Os.h"
#include "Support/Report/LogSymbol.h"
#include "Support/Report/Logger.h"

SWC_BEGIN_NAMESPACE();

namespace CommandPrint
{
    inline void printCompilerHeader(const TaskContext& ctx)
    {
        Logger::print(ctx, std::format("{}{}{} Swag compiler {}.{}.{}\n", LogColorHelper::toAnsi(ctx, LogColor::BrandVoltage), LogSymbolHelper::toString(ctx, LogSymbol::CommandMark), LogColorHelper::toAnsi(ctx, LogColor::Reset), SWC_VERSION, SWC_REVISION, SWC_BUILD_NUM));
    }

    constexpr LogColor helpArgumentLabelColor()
    {
        return LogColor::BrandArc;
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
        style.titleColor              = LogColor::BrandVoltage;
        style.defaultValueColor       = LogColor::Reset;
        style.wrapValues              = true;
        const size_t columns          = Os::stdoutColumnCount();
        style.maxLineWidth            = columns ? std::min<size_t>(columns, 100) : 100;
        style.minLabelWidth           = std::min(style.minLabelWidth, style.maxLineWidth / 3);
        style.maxLabelWidth           = std::min(style.maxLabelWidth, style.maxLineWidth / 3);
        style.maxLabelWidth           = std::max(style.maxLabelWidth, style.minLabelWidth);
        style.minLabelWidth           = style.maxLabelWidth;
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

    inline void addNativeToolchainEntries(std::vector<Logger::FieldEntry>& entries, const Os::WindowsToolchainDiscoveryResult toolchainResult, const Os::WindowsToolchainPaths& toolchain)
    {
        switch (toolchainResult)
        {
            case Os::WindowsToolchainDiscoveryResult::Ok:
                addInfoEntry(entries, "Status", "ready", LogColor::BrightGreen);
                addInfoEntry(entries, "Linker", "integrated (swc)");
                addInfoEntry(entries, "MSVC library path", toolchain.vcLibPath);
                addInfoEntry(entries, "Windows SDK UM libs", toolchain.sdkUmLibPath);
                addInfoEntry(entries, "Windows SDK UCRT libs", toolchain.sdkUcrtLibPath);
                break;

            case Os::WindowsToolchainDiscoveryResult::MissingMsvcToolchain:
                addInfoEntry(entries, "Status", "missing MSVC toolchain", LogColor::BrightRed);
                break;

            case Os::WindowsToolchainDiscoveryResult::MissingWindowsSdk:
                addInfoEntry(entries, "Status", "missing Windows SDK", LogColor::BrightRed);
                break;
        }
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

    template<typename T>
    inline void addSetEntries(std::vector<Logger::FieldEntry>& entries, const std::string_view label, const std::set<T>& values)
    {
        if (values.empty())
        {
            addInfoEntry(entries, label, "<empty>", LogColor::Gray);
            return;
        }

        addInfoEntry(entries, label, Utf8Helper::countWithLabel(values.size(), "entry"));
        uint32_t index = 0;
        for (const T& value : values)
            addInfoEntry(entries, std::format("[{}]", index++), value, LogColor::White, 1);
    }

}

SWC_END_NAMESPACE();
