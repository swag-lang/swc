#global internal
#global namespace Viewers.Pptx

using Core

private const ChartSourceLimit = 1024 * 1024'u64
private const ChartPointLimit  = 64'u64
private const ChartSeriesLimit = 8'u64

private enum ChartField
{
    None
    Title
    Category
    Value
}

private struct ChartSeries
{
    title:  String
    values: Array'String
}

// One bounded cached bar chart, keyed by its relationship on the slide.
struct SlideChart
{
    relationshipId: String
    html:           String
    plainText:      String
}

private impl SlideChart
{
    func parse(source, relationshipId: string)->SlideChart fail
    {
        var result: #returntype
        result.relationshipId = relationshipId
        var scan = Package.Scanner.create(source)
        var token: Package.Token
        var inBarChart = false
        var sawBarChart = false
        var unsupportedChartType = false
        var hasBarDirection = false
        var unsupportedBarDirection = false
        var verticalBars = false
        var inSeries = false
        var field = ChartField.None
        var inValue = false
        var pointIndex = Swag.U64.Max
        var sequentialIndex = 0'u64
        var value: String
        var categories: Array'String
        var series: Array'ChartSeries

        while scan.next(&token)
        {
            if token.kind == .Start
            {
                if token.isElement("barChart")
                {
                    inBarChart = true
                    sawBarChart = true
                }
                elif token.isElement("lineChart") or token.isElement("pieChart") or token.isElement("areaChart") or
                     token.isElement("scatterChart") or token.isElement("doughnutChart") or token.isElement("radarChart") or
                     token.isElement("stockChart") or token.isElement("surfaceChart") or token.isElement("bubbleChart")
                {
                    unsupportedChartType = true
                }
                elif inBarChart and token.isElement("barDir")
                {
                    hasBarDirection = true
                    let direction = token.attribute("val")
                    unsupportedBarDirection = unsupportedBarDirection or (direction != "bar" and direction != "col")
                    verticalBars = direction == "col"
                }
                elif token.isElement("ser") and inBarChart
                {
                    if series.count == ChartSeriesLimit
                    {
                        return {}
                    }
                    series.add({})
                    inSeries = true
                }
                elif inSeries and token.isElement("tx")
                {
                    field = .Title
                    sequentialIndex = 0
                }
                elif inSeries and token.isElement("cat")
                {
                    field = .Category
                    sequentialIndex = 0
                }
                elif inSeries and token.isElement("val")
                {
                    field = .Value
                    sequentialIndex = 0
                }
                elif field != .None and token.isElement("pt")
                {
                    pointIndex = catch StrConv.toU64(token.attribute("idx") orelse "") orelse Swag.U64.Max
                }
                elif field != .None and token.isElement("v")
                {
                    inValue = true
                    value.clear()
                    if pointIndex == Swag.U64.Max do
                        pointIndex = sequentialIndex
                }
                elif token.empty and token.isElement("barChart") do
                    inBarChart = false
            }
            elif token.kind == .End
            {
                if token.isElement("v") and inValue
                {
                    if field == .Title and inSeries
                    {
                        series.backPtr().title = value
                    }
                    elif field == .Category and inSeries
                    {
                        if pointIndex >= ChartPointLimit
                        {
                            return {}
                        }
                        if pointIndex == categories.count
                        {
                            categories.add(value)
                        }
                        elif pointIndex >= categories.count or categories[pointIndex] != value
                        {
                            return {}
                        }
                    }
                    elif field == .Value and inSeries
                    {
                        if pointIndex >= ChartPointLimit
                        {
                            return {}
                        }
                        if pointIndex != series.back().values.count
                        {
                            return {}
                        }
                        let number = catch StrConv.toF64(value) { return {}; }
                        if not Math.isFinite(number) or number < -1e100 or number > 1e100
                        {
                            return {}
                        }
                        series.backPtr().values.add(value)
                    }

                    inValue = false
                    pointIndex = Swag.U64.Max
                    sequentialIndex += 1
                }
                elif token.isElement("tx") or token.isElement("cat") or token.isElement("val")
                {
                    field = .None
                }
                elif token.isElement("ser")
                {
                    inSeries = false
                    field = .None
                }
                elif token.isElement("barChart")
                {
                    inBarChart = false
                }
            }
            elif inValue
            {
                value += token.text
            }

            if scan.offset > ChartSourceLimit do
                fail Errors.UnsupportedFormatError{texts().err_TooLarge}
        }

        if scan.damaged do
            fail Errors.InvalidFormatError{texts().err_Invalid}
        if not sawBarChart or unsupportedChartType or not hasBarDirection or unsupportedBarDirection or categories.isEmpty() or series.isEmpty()
        {
            return {}
        }
        for item in series where item.values.count != categories.count
        {
            return {}
        }

        return SlideChart.render(relationshipId, categories.toSlice(), series.toSlice(), verticalBars)
    }

    func render(relationshipId: string, categories: const [..] String, series: const [..] ChartSeries, verticalBars: bool)->SlideChart
    {
        var result = SlideChart{relationshipId: relationshipId}
        var minimum = 0.0'f64
        var maximum = 0.0'f64
        for item in series
        {
            for value in item.values
            {
                let number = catch StrConv.toF64(value.toString()) orelse 0.0'f64
                minimum = Math.min(minimum, number)
                maximum = Math.max(maximum, number)
            }
        }
        var range = maximum - minimum
        if not range do
            range = 1
        let zeroPercent = Math.clamp(-minimum / range * 100, 0, 100)
        let zeroTopEm = Math.clamp(maximum / range * 6, 0, 6)

        result.html = verticalBars ? "<div style=\"height:100%;display:flex;flex-direction:column\">" : "<div>"
        for item in series
        {
            result.html += "<p><b>"
            Package.appendHtmlEscaped(&result.html, item.title)
            result.html += "</b></p>"
            if verticalBars
            {
                result.html += "<div role=\"list\" style=\"display:flex;flex:1;min-height:0;align-items:stretch;gap:4px\">"
            }
            else
            {
                result.html += "<div role=\"list\">"
            }
            for category, index in categories
            {
                let label = item.values[index].toString()
                let number = catch StrConv.toF64(label) orelse 0.0'f64
                let percent = Math.clamp(Math.abs(number) / range * 100, 0, 100)
                let barHeightEm = percent / 100 * 6
                let barLeftPercent = number >= 0 ? zeroPercent : zeroPercent - percent
                let barTopEm = number >= 0 ? zeroTopEm - barHeightEm : zeroTopEm
                if verticalBars
                {
                    result.html += "<div role=\"listitem\" style=\"flex:1;min-width:0;display:flex;flex-direction:column;align-items:center;justify-content:flex-end;gap:2px\"><span>"
                    Package.appendHtmlEscaped(&result.html, label)
                    result.html += "</span><span style=\"position:relative;display:block;width:100%;height:6em\"><span style=\"position:absolute;left:0;top:"
                    result.html += Format.toString("%{f2}em;width:100%%;height:1px;background-color:#808080\"></span><span style=\"position:absolute;left:20%%;top:%{f2}em;display:block;width:60%%;height:%{f2}em;background-color:#4472C4\"></span></span><span>", zeroTopEm, barTopEm, barHeightEm)
                    Package.appendHtmlEscaped(&result.html, category.toString())
                    result.html += "</span></div>"
                }
                else
                {
                    result.html += "<div role=\"listitem\" style=\"display:flex;align-items:center;gap:8px\"><span>"
                    Package.appendHtmlEscaped(&result.html, category.toString())
                    result.html += "</span><span style=\"position:relative;display:block;flex:1;height:12px;background-color:#E8E8E8\"><span style=\"position:absolute;left:"
                    result.html += Format.toString("%{f2}%%;top:0;width:1px;height:12px;background-color:#808080\"></span><span style=\"position:absolute;left:%{f2}%%;top:0;display:block;height:12px;width:%{f2}%%;background-color:#4472C4\"></span></span><span>", zeroPercent, barLeftPercent, percent)
                    Package.appendHtmlEscaped(&result.html, label)
                    result.html += "</span></div>"
                }
                result.plainText += category.toString()
                result.plainText += ": "
                result.plainText += label
                result.plainText += '\n'u8
            }

            result.html += "</div>"
        }
        result.html += "</div>"
        return result
    }
}

func chartsForSlide(source: string, parts: const *Package.PartReader, path: string)->Array'SlideChart fail
{
    let relationships = try parts.relationships(path)
    var result: #returntype
    var scan = Package.Scanner.create(source)
    var token: Package.Token
    var chartIds: Array'String
    while scan.next(&token)
    {
        if token.kind != .Start or not token.isElement("chart") do
            continue
        let id = token.attribute("r:id") orelse ""
        if not id.count do
            continue
        var seen = false
        for existing in chartIds where existing.toString() == id do
            seen = true
        if not seen do
            chartIds.add(id)
        if chartIds.count > ChartSeriesLimit do
            fail Errors.UnsupportedFormatError{texts().err_TooLarge}
    }

    if scan.damaged do
        fail Errors.InvalidFormatError{texts().err_Invalid}

    var sourceBytes = 0'u64
    for id in chartIds
    {
        for relation in relationships where relation.id.toString() == id.toString() and Utf8.endsWith(relation.kind.toString(), "/chart")
        {
            let source = try parts.text(relation.path, required: false, limit: ChartSourceLimit)
            sourceBytes += source.count
            if sourceBytes > 4 * ChartSourceLimit do
                fail Errors.UnsupportedFormatError{texts().err_TooLarge}
            let chart = try SlideChart.parse(source, id.toString())
            if not chart.html.isEmpty() do
                result.add(chart)
            break
        }
    }

    return result
}

func findSlideChart(charts: const [..] SlideChart, source: string)->const *SlideChart?
{
    var scan = Package.Scanner.create(source)
    var token: Package.Token
    while scan.next(&token)
    {
        if token.kind == .Start and token.isElement("chart")
        {
            let id = token.attribute("r:id") orelse ""
            for chart in charts where chart.relationshipId.toString() == id do
                return chart
        }
    }

    return null
}
