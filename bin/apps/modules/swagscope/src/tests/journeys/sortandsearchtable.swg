#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Gui, Pixel, Viewers

// Sort a CSV by its numeric column, find a row, reverse the sort and copy the chosen line.
#[Swag.TestTag("integration.application.journey")]
#test
{
    var journey: ScopeJourney
    journey.setup()
    let file = Path.combine(journey.root, "sizes.csv")
    expect File.writeAllText(file, "name,size\nfile10,1200\nfile9,\nfile2,35\nFile1,-4.5\n")
    let window = journey.window

    window.openFile(file)
    journey.waitForFile(file)
    Swag.require(window.choices[window.activeChoiceIndex].key == "table")
    let table = assume cast(*Table.Panel, window.currentView)
    Swag.require(table.document.rows.count == 4 and table.numeric[1])

    table.sortBy(1)
    journey.waitFor("ascending sizes", func|table|()->bool => table.sortColumn == 1 and
                                                           not table.descending and table.order[0] == 3)
    window.sendCommandEvent(ViewerCommands.Find)
    window.searchBox.setText("file2")
    journey.waitFor("found table row", func|window, table|()->bool => window.searchComplete and
                                                                   window.searchMatches.count == 1 and
                                                                   table.searchRow == 2)

    table.sortBy(1)
    journey.waitFor("descending sizes", func|table|()->bool => table.descending and table.order[0] == 0)
    table.list.unselectAll()
    table.list.selectLine(0)
    Swag.require(table.selectionText() == "file10\t1200\n")
}
