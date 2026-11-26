#global internal
#global namespace Viewers.Pptx

using Core, Pixel

private const ChartSourceLimit = 1024 * 1024_u64
private const ChartPointLimit  = 64_u64
private const ChartSeriesLimit = 8_u64
private const LineChartWidth   = 768
private const LineChartHeight  = 200
private const PieChartWidth    = 360
private const PieChartHeight   = 280
private const ChartPngLimit    = 2 * 1024 * 1024_u64

private const ChartColors: [8] string = ["4472C4", "ED7D31", "A5A5A5", "FFC000", "5B9BD5", "70AD47", "264478", "9E480E"]

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
    values: Array!{String}
    color:  String
}

private func isHexColor(value: string)->bool
{
    if value.count != 6
    {
        return false
    }

    for byte in value
    {
        if not (byte >= '0'_u8 and byte <= '9'_u8) and
           not (byte >= 'A'_u8 and byte <= 'F'_u8) and
           not (byte >= 'a'_u8 and byte <= 'f'_u8)
        {
            return false
        }
    }

    return true
}

// One bounded cached chart, keyed by its relationship on the slide.
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
        var scan                    = Package.Scanner.create(source)
        var token:      Package.Token
        var inBarChart              = false
        var sawBarChart             = false
        var inLineChart             = false
        var sawLineChart            = false
        var inAreaChart             = false
        var sawAreaChart            = false
        var inPieChart              = false
        var inSeriesProperties      = false
        var sawPieChart             = false
        var unsupportedLine         = false
        var unsupportedChartType    = false
        var hasBarDirection         = false
        var unsupportedBarDirection = false
        var verticalBars            = false
        var inSeries                = false
        var field                   = ChartField.None
        var inValue                 = false
        var pointIndex              = Swag.U64.Max
        var sequentialIndex         = 0_u64
        var value:      String
        var categories: Array!{String}
        var series:     Array!{ChartSeries}

        while scan.next(&token)
        {
            if token.kind == .Start
            {
                if token.isElement("barChart")
                {
                    inBarChart  = true
                    sawBarChart = true
                    unsupportedChartType = unsupportedChartType or sawLineChart or sawAreaChart or sawPieChart
                }
                else if token.isElement("lineChart")
                {
                    inLineChart          = true
                    sawLineChart         = true
                    unsupportedChartType = unsupportedChartType or sawBarChart or sawPieChart or sawAreaChart
                }
                else if token.isElement("areaChart")
                {
                    inAreaChart          = true
                    sawAreaChart         = true
                    unsupportedChartType = unsupportedChartType or sawBarChart or sawLineChart or sawPieChart
                }
                else if token.isElement("grouping") and inAreaChart
                {
                    let grouping = token.attribute("val") orelse "standard"
                    unsupportedLine = unsupportedLine or grouping != "standard"
                }
                else if token.isElement("pieChart")
                {
                    inPieChart  = true
                    sawPieChart = true
                    unsupportedChartType = unsupportedChartType or sawBarChart or sawLineChart or sawAreaChart
                }
                else if token.isElement("scatterChart") or
                        token.isElement("doughnutChart") or
                        token.isElement("radarChart") or
                        token.isElement("stockChart") or
                        token.isElement("surfaceChart") or
                        token.isElement("bubbleChart")
                {
                    unsupportedChartType = true
                }
                else if inLineChart and token.isElement("smooth")
                {
                    let smooth = token.attribute("val")
                    unsupportedLine = unsupportedLine or (smooth == "1" or smooth == "true")
                }
                else if inLineChart and token.isElement("grouping")
                {
                    let grouping = token.attribute("val") orelse "standard"
                    unsupportedLine = unsupportedLine or grouping != "standard"
                }
                else if inBarChart and token.isElement("barDir")
                {
                    hasBarDirection = true
                    let direction = token.attribute("val")
                    unsupportedBarDirection = unsupportedBarDirection or (direction != "bar" and direction != "col")
                    verticalBars = direction == "col"
                }
                else if token.isElement("ser") and (inBarChart or inLineChart or inAreaChart or inPieChart)
                {
                    if series.count == ChartSeriesLimit
                    {
                        return {}
                    }

                    series.add({})
                    inSeries = true
                }
                else if inSeries and token.isElement("spPr")
                {
                    inSeriesProperties = not token.empty
                }
                else if inSeriesProperties and token.isElement("srgbClr")
                {
                    let color = token.attribute("val") orelse ""
                    if isHexColor(color)
                    {
                        series.backPtr().color = color
                    }
                }
                else if inSeries and token.isElement("tx")
                {
                    field = .Title
                    sequentialIndex = 0
                }
                else if inSeries and token.isElement("cat")
                {
                    field = .Category
                    sequentialIndex = 0
                }
                else if inSeries and token.isElement("val")
                {
                    field = .Value
                    sequentialIndex = 0
                }
                else if field != .None and token.isElement("pt")
                {
                    pointIndex = catch StrConv.toU64(token.attribute("idx") orelse "") orelse Swag.U64.Max
                }
                else if field != .None and token.isElement("v")
                {
                    inValue = true
                    value.clear()
                    if pointIndex == Swag.U64.Max
                    {
                        pointIndex = sequentialIndex
                    }
                }
                else if token.empty and token.isElement("barChart")
                {
                    inBarChart = false
                }
                else if token.empty and token.isElement("lineChart")
                {
                    inLineChart = false
                }
                else if token.empty and token.isElement("areaChart")
                {
                    inAreaChart = false
                }
                else if token.empty and token.isElement("pieChart")
                {
                    inPieChart = false
                }
            }
            else if token.kind == .End
            {
                if token.isElement("v") and inValue
                {
                    if field == .Title and inSeries
                    {
                        series.backPtr().title = value
                    }
                    else if field == .Category and inSeries
                    {
                        if pointIndex >= ChartPointLimit
                        {
                            return {}
                        }

                        if pointIndex == categories.count
                        {
                            categories.add(value)
                        }
                        else if pointIndex >= categories.count or categories[pointIndex] != value
                        {
                            return {}
                        }
                    }
                    else if field == .Value and inSeries
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

                    inValue         = false
                    pointIndex      = Swag.U64.Max
                    sequentialIndex += 1
                }
                else if token.isElement("tx") or token.isElement("cat") or token.isElement("val")
                {
                    field = .None
                }
                else if token.isElement("ser")
                {
                    inSeries = false
                    inSeriesProperties = false
                    field    = .None
                }
                else if token.isElement("spPr")
                {
                    inSeriesProperties = false
                }
                else if token.isElement("barChart")
                {
                    inBarChart = false
                }
                else if token.isElement("lineChart")
                {
                    inLineChart = false
                }
                else if token.isElement("areaChart")
                {
                    inAreaChart = false
                }
                else if token.isElement("pieChart")
                {
                    inPieChart = false
                }
            }
            else if inValue
            {
                value += token.text
            }

            if scan.offset > ChartSourceLimit
            {
                fail Errors.UnsupportedFormatError{texts().err_TooLarge}
            }
        }

        if scan.damaged
        {
            fail Errors.InvalidFormatError{texts().err_Invalid}
        }

        let supportedType = (sawBarChart and not sawLineChart and not sawAreaChart and not sawPieChart) or
                            (sawLineChart and not sawBarChart and not sawAreaChart and not sawPieChart) or
                            (sawAreaChart and not sawBarChart and not sawLineChart and not sawPieChart) or
                            (sawPieChart and not sawBarChart and not sawLineChart and not sawAreaChart)
        if unsupportedChartType or
           unsupportedLine or
           not supportedType or
           (sawBarChart and (not hasBarDirection or unsupportedBarDirection)) or
           categories.isEmpty() or
           series.isEmpty()
        {
            return {}
        }

        for item in series where item.values.count != categories.count
        {
            return {}
        }

        if sawPieChart
        {
            if series.count != 1
            {
                return {}
            }

            for value in series[0].values
            {
                let number = catch StrConv.toF64(value.toString()) orelse 0.0_f64
                if number <= 0
                {
                    return {}
                }
            }

            return try SlideChart.renderPie(relationshipId, categories.toSlice(), series[0])
        }

        if sawLineChart
        {
            if categories.count < 2
            {
                return {}
            }

            return try SlideChart.renderLine(relationshipId, categories.toSlice(), series.toSlice())
        }

        if sawAreaChart
        {
            if categories.count < 2
            {
                return {}
            }

            return try SlideChart.renderArea(relationshipId, categories.toSlice(), series.toSlice())
        }

        return SlideChart.render(relationshipId, categories.toSlice(), series.toSlice(), verticalBars)
    }

    func renderLine(relationshipId: string, categories: const [..] String, series: const [..] ChartSeries)->SlideChart fail
    {
        var minimum  = 0.0_f64
        var maximum  = 0.0_f64
        var hasValue = false
        for item in series
        {
            for value in item.values
            {
                let number = try StrConv.toF64(value.toString())
                if not hasValue
                {
                    minimum  = number
                    maximum  = number
                    hasValue = true
                }
                else
                {
                    minimum = Math.min(minimum, number)
                    maximum = Math.max(maximum, number)
                }
            }
        }

        var range = maximum - minimum
        if not range
        {
            range = 1
        }

        const Left       = 28.0_f64
        const Right      = 12.0_f64
        const Top        = 12.0_f64
        const Bottom     = 12.0_f64
        const PlotWidth  = cast(f64, LineChartWidth) - Left - Right
        const PlotHeight = cast(f64, LineChartHeight) - Top - Bottom

        var source: String = Format.toString("<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"%\" height=\"%\" viewBox=\"0 0 % %\"><path d=\"", LineChartWidth, LineChartHeight, LineChartWidth, LineChartHeight)
        for gridLine in 0 until 4
        {
            let y = Top + PlotHeight * cast(f64, gridLine) / 3
            if gridLine
            {
                source += " "
            }

            source += Format.toString("M %{f2} %{f2} H %{f2}", Left, y, Left + PlotWidth)
        }

        source += "\" fill=\"none\" stroke=\"#D9D9D9\" stroke-width=\"1\"/>"
        for item, seriesIndex in series
        {
            let color = item.color.count == 6 ? item.color.toString() : ChartColors[seriesIndex]
            source += "<path d=\""
            for index in 0 until categories.count
            {
                let number = try StrConv.toF64(item.values[index].toString())
                let x      = Left + PlotWidth * cast(f64, index) / cast(f64, categories.count - 1)
                let y      = Top + PlotHeight * (maximum - number) / range
                source += Format.toString("% %{f2} %{f2}", index == 0 ? "M" : "L", x, y)
            }

            source += Format.toString("\" fill=\"none\" stroke=\"#%\" stroke-width=\"3\" stroke-linecap=\"round\" stroke-linejoin=\"round\"/>", color)
            for index in 0 until categories.count
            {
                let number = try StrConv.toF64(item.values[index].toString())
                let x      = Left + PlotWidth * cast(f64, index) / cast(f64, categories.count - 1)
                let y      = Top + PlotHeight * (maximum - number) / range
                source += Format.toString("<circle cx=\"%{f2}\" cy=\"%{f2}\" r=\"4\" fill=\"#%\"/>", x, y, color)
            }
        }

        source += "</svg>"
        let drawing = try Svg.Drawing.parse(source)
        let image   = drawing.rasterize(LineChartWidth, LineChartHeight, 2)
        if not image.isValid()
        {
            fail Errors.UnsupportedFormatError{texts().err_TooLarge}
        }

        var encoded = try image.encode("memory.png")
        encoded.makeLinear()
        let bytes = unwrap encoded.toSlice()
        if bytes.count > ChartPngLimit
        {
            fail Errors.UnsupportedFormatError{texts().err_TooLarge}
        }

        var result = SlideChart{relationshipId: relationshipId}
        result.html = Format.toString("<img width=\"%\" height=\"%\" style=\"max-width:100%%;height:auto\" alt=\"Line chart with % series and % categories\" src=\"data:image/png;base64,%\"><div role=\"table\" style=\"font-size:12px;line-height:14px\">",
                                      LineChartWidth,
                                      LineChartHeight,
                                      series.count,
                                      categories.count,
                                      Base64.encode(bytes))
        for item in series
        {
            result.html += "<div><b>"
            Package.appendHtmlEscaped(&result.html, item.title)
            result.html += "</b></div>"
            for category, index in categories
            {
                let label = item.values[index].toString()
                result.html += "<div>"
                Package.appendHtmlEscaped(&result.html, category.toString())
                result.html += ": "
                Package.appendHtmlEscaped(&result.html, label)
                result.html      += "</div>"
                result.plainText += item.title
                result.plainText += " — "
                result.plainText += category.toString()
                result.plainText += ": "
                result.plainText += label
                result.plainText += '\n'_u8
            }
        }

        result.html += "</div>"
        return result
    }

    func renderArea(relationshipId: string, categories: const [..] String, series: const [..] ChartSeries)->SlideChart fail
    {
        var minimum = 0.0_f64
        var maximum = 0.0_f64
        for item in series
        {
            for value in item.values
            {
                let number = try StrConv.toF64(value.toString())
                minimum = Math.min(minimum, number)
                maximum = Math.max(maximum, number)
            }
        }

        var range = maximum - minimum
        if not range
        {
            range = 1
        }

        const Left       = 28.0_f64
        const Right      = 12.0_f64
        const Top        = 12.0_f64
        const Bottom     = 12.0_f64
        const PlotWidth  = cast(f64, LineChartWidth) - Left - Right
        const PlotHeight = cast(f64, LineChartHeight) - Top - Bottom
        let zeroY = Top + PlotHeight * maximum / range
        var source: String = Format.toString("<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"%\" height=\"%\" viewBox=\"0 0 % %\"><path d=\"", LineChartWidth, LineChartHeight, LineChartWidth, LineChartHeight)
        for gridLine in 0 until 4
        {
            let y = Top + PlotHeight * cast(f64, gridLine) / 3
            if gridLine
            {
                source += " "
            }

            source += Format.toString("M %{f2} %{f2} H %{f2}", Left, y, Left + PlotWidth)
        }

        source += "\" fill=\"none\" stroke=\"#D9D9D9\" stroke-width=\"1\"/>"

        for item, seriesIndex in series
        {
            let color = item.color.count == 6 ? item.color.toString() : ChartColors[seriesIndex]
            let lastX = Left + PlotWidth
            source += Format.toString("<path d=\"M %{f2} %{f2}", Left, zeroY)
            for index in 0 until categories.count
            {
                let number = try StrConv.toF64(item.values[index].toString())
                let x      = Left + PlotWidth * cast(f64, index) / cast(f64, categories.count - 1)
                let y      = Top + PlotHeight * (maximum - number) / range
                source += Format.toString(" L %{f2} %{f2}", x, y)
            }

            source += Format.toString(" L %{f2} %{f2} Z\" fill=\"#%\" fill-opacity=\"0.32\"/>", lastX, zeroY, color)
        }

        source += "</svg>"

        let drawing = try Svg.Drawing.parse(source)
        let image   = drawing.rasterize(LineChartWidth, LineChartHeight, 2)
        if not image.isValid()
        {
            fail Errors.UnsupportedFormatError{texts().err_TooLarge}
        }

        var encoded = try image.encode("memory.png")
        encoded.makeLinear()
        let bytes = unwrap encoded.toSlice()
        if bytes.count > ChartPngLimit
        {
            fail Errors.UnsupportedFormatError{texts().err_TooLarge}
        }

        var result = SlideChart{relationshipId: relationshipId}
        result.html = Format.toString("<img width=\"%\" height=\"%\" style=\"max-width:100%%;height:auto\" alt=\"Area chart with % series and % categories\" src=\"data:image/png;base64,%\"><div role=\"table\" style=\"font-size:12px;line-height:14px\">",
                                      LineChartWidth,
                                      LineChartHeight,
                                      series.count,
                                      categories.count,
                                      Base64.encode(bytes))
        for item in series
        {
            result.html += "<div><b>"
            Package.appendHtmlEscaped(&result.html, item.title)
            result.html += "</b></div>"
            for category, index in categories
            {
                let label = item.values[index].toString()
                result.html += "<div>"
                Package.appendHtmlEscaped(&result.html, category.toString())
                result.html += ": "
                Package.appendHtmlEscaped(&result.html, label)
                result.html      += "</div>"
                result.plainText += item.title
                result.plainText += " — "
                result.plainText += category.toString()
                result.plainText += ": "
                result.plainText += label
                result.plainText += '\n'_u8
            }
        }

        result.html += "</div>"
        return result
    }

    func renderPie(relationshipId: string, categories: const [..] String, series: const *ChartSeries)->SlideChart fail
    {
        var total = 0.0_f64
        for value in series.values
        {
            total += try StrConv.toF64(value.toString())
        }

        if not Math.isFinite(total) or total <= 0
        {
            return {}
        }

        const CenterX    = 180.0_f64
        const CenterY    = 140.0_f64
        const Radius     = 128.0_f64
        const StartAngle = -Math.ConstF64.Pi / 2
        var source: String = Format.toString("<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"%\" height=\"%\" viewBox=\"0 0 % %\">", PieChartWidth, PieChartHeight, PieChartWidth, PieChartHeight)
        let colors         = Color.generateDistinctColors(cast(u32, categories.count))
        var angle          = StartAngle
        if categories.count == 1
        {
            let color = colors[0]
            source += Format.toString("<circle cx=\"%{f2}\" cy=\"%{f2}\" r=\"%{f2}\" fill=\"#%{X02}%{X02}%{X02}\"/>", CenterX, CenterY, Radius, color.r, color.g, color.b)
        }
        else
        {
            for value, index in series.values
            {
                let number   = try StrConv.toF64(value.toString())
                let sweep    = number / total * Math.ConstF64.TwoPi
                let endAngle = angle + sweep
                let startX   = CenterX + Math.cos(angle) * Radius
                let startY   = CenterY + Math.sin(angle) * Radius
                let endX     = CenterX + Math.cos(endAngle) * Radius
                let endY     = CenterY + Math.sin(endAngle) * Radius
                let largeArc = sweep > Math.ConstF64.Pi ? 1 : 0
                let color    = colors[index]
                source += Format.toString("<path d=\"M %{f2} %{f2} L %{f2} %{f2} A %{f2} %{f2} 0 % 1 %{f2} %{f2} Z\" fill=\"#%\" stroke=\"#FFFFFF\" stroke-width=\"2\"/>",
                                          CenterX,
                                          CenterY,
                                          startX,
                                          startY,
                                          Radius,
                                          Radius,
                                          largeArc,
                                          endX,
                                          endY,
                                          Format.toString("%{X02}%{X02}%{X02}", color.r, color.g, color.b))
                angle = endAngle
            }
        }

        source += "</svg>"
        let drawing = try Svg.Drawing.parse(source)
        let image   = drawing.rasterize(PieChartWidth, PieChartHeight, 2)
        if not image.isValid()
        {
            fail Errors.UnsupportedFormatError{texts().err_TooLarge}
        }

        var encoded = try image.encode("memory.png")
        encoded.makeLinear()
        let bytes = unwrap encoded.toSlice()
        if bytes.count > ChartPngLimit
        {
            fail Errors.UnsupportedFormatError{texts().err_TooLarge}
        }

        var result = SlideChart{relationshipId: relationshipId}
        result.html = "<div style=\"display:flex;align-items:center;gap:12px\">"
        result.html += Format.toString("<img width=\"%\" height=\"%\" style=\"max-width:45%%;height:auto\" alt=\"Pie chart with % categories\" src=\"data:image/png;base64,%\"><div role=\"table\" style=\"max-height:240px;overflow-y:auto;font-size:12px;line-height:14px\"><b>",
                                       PieChartWidth,
                                       PieChartHeight,
                                       categories.count,
                                       Base64.encode(bytes))
        Package.appendHtmlEscaped(&result.html, series.title.toString())
        result.html += "</b>"
        for category, index in categories
        {
            let label   = series.values[index].toString()
            let number  = try StrConv.toF64(label)
            let percent = number / total * 100
            let color   = colors[index]
            result.html += Format.toString("<div><span style=\"display:inline-block;width:10px;height:10px;background-color:#%{X02}%{X02}%{X02}\"></span> ", color.r, color.g, color.b)
            Package.appendHtmlEscaped(&result.html, category.toString())
            result.html += ": "
            Package.appendHtmlEscaped(&result.html, label)
            result.html      += Format.toString(" (%{f1}%%)</div>", percent)
            result.plainText += series.title
            result.plainText += " — "
            result.plainText += category.toString()
            result.plainText += ": "
            result.plainText += label
            result.plainText += '\n'_u8
        }

        result.html += "</div></div>"
        return result
    }

    func render(relationshipId: string, categories: const [..] String, series: const [..] ChartSeries, verticalBars: bool)->SlideChart
    {
        var result  = SlideChart{relationshipId: relationshipId}
        var minimum = 0.0_f64
        var maximum = 0.0_f64
        for item in series
        {
            for value in item.values
            {
                let number = catch StrConv.toF64(value.toString()) orelse 0.0_f64
                minimum = Math.min(minimum, number)
                maximum = Math.max(maximum, number)
            }
        }

        var range = maximum - minimum
        if not range
        {
            range = 1
        }

        let zeroPercent = Math.clamp(-minimum / range * 100, 0, 100)
        let zeroTopEm   = Math.clamp(maximum / range * 6, 0, 6)

        result.html = verticalBars ? "<div style=\"height:100%;display:flex;flex-direction:column\">" : "<div>"
        for item, seriesIndex in series
        {
            let color = item.color.count == 6 ? item.color.toString() : ChartColors[seriesIndex]
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
                let label          = item.values[index].toString()
                let number         = catch StrConv.toF64(label) orelse 0.0_f64
                let percent        = Math.clamp(Math.abs(number) / range * 100, 0, 100)
                let barHeightEm    = percent / 100 * 6
                let barLeftPercent = number >= 0 ? zeroPercent : zeroPercent - percent
                let barTopEm       = number >= 0 ? zeroTopEm - barHeightEm : zeroTopEm
                if verticalBars
                {
                    result.html += "<div role=\"listitem\" style=\"flex:1;min-width:0;display:flex;flex-direction:column;align-items:center;justify-content:flex-end;gap:2px\"><span>"
                    Package.appendHtmlEscaped(&result.html, label)
                    result.html += "</span><span style=\"position:relative;display:block;width:100%;height:6em\"><span style=\"position:absolute;left:0;top:"
                    result.html += Format.toString("%{f2}em;width:100%%;height:1px;background-color:#808080\"></span><span style=\"position:absolute;left:20%%;top:%{f2}em;display:block;width:60%%;height:%{f2}em;background-color:#%\"></span></span><span>", zeroTopEm, barTopEm, barHeightEm, color)
                    Package.appendHtmlEscaped(&result.html, category.toString())
                    result.html += "</span></div>"
                }
                else
                {
                    result.html += "<div role=\"listitem\" style=\"display:flex;align-items:center;gap:8px\"><span>"
                    Package.appendHtmlEscaped(&result.html, category.toString())
                    result.html += "</span><span style=\"position:relative;display:block;flex:1;height:12px;background-color:#E8E8E8\"><span style=\"position:absolute;left:"
                    result.html += Format.toString("%{f2}%%;top:0;width:1px;height:12px;background-color:#808080\"></span><span style=\"position:absolute;left:%{f2}%%;top:0;display:block;height:12px;width:%{f2}%%;background-color:#%\"></span></span><span>", zeroPercent, barLeftPercent, percent, color)
                    Package.appendHtmlEscaped(&result.html, label)
                    result.html += "</span></div>"
                }

                result.plainText += category.toString()
                result.plainText += ": "
                result.plainText += label
                result.plainText += '\n'_u8
            }

            result.html += "</div>"
        }

        result.html += "</div>"
        return result
    }
}

func chartsForSlide(source: string, parts: const *Package.PartReader, path: string)->Array!{SlideChart} fail
{
    let relationships = try parts.relationships(path)
    var result:   #returntype
    var scan = Package.Scanner.create(source)
    var token:    Package.Token
    var chartIds: Array!{String}
    while scan.next(&token)
    {
        if token.kind != .Start or not token.isElement("chart")
        {
            continue
        }

        let id = token.attribute("r:id") orelse ""
        if not id.count
        {
            continue
        }

        var seen = false
        for existing in chartIds where existing.toString() == id
        {
            seen = true
        }

        if not seen
        {
            chartIds.add(id)
        }

        if chartIds.count > ChartSeriesLimit
        {
            fail Errors.UnsupportedFormatError{texts().err_TooLarge}
        }
    }

    if scan.damaged
    {
        fail Errors.InvalidFormatError{texts().err_Invalid}
    }

    var sourceBytes = 0_u64
    for id in chartIds
    {
        for relation in relationships where relation.id.toString() == id.toString() and Utf8.endsWith(relation.kind.toString(), "/chart")
        {
            let source = try parts.text(relation.path, required: false, limit: ChartSourceLimit)
            sourceBytes += source.count
            if sourceBytes > 4 * ChartSourceLimit
            {
                fail Errors.UnsupportedFormatError{texts().err_TooLarge}
            }

            let chart = try SlideChart.parse(source, id.toString())
            if not chart.html.isEmpty()
            {
                result.add(chart)
            }

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
            for chart in charts where chart.relationshipId.toString() == id
            {
                return chart
            }
        }
    }

    return null
}
