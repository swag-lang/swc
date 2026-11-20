#global internal

using Core, Gui, Pixel, Video

// The viewer-owned information session used by both a selected file and an open document.
// It creates the corresponding viewer without playback, reuses its information callback, and
// enriches its identity asynchronously through the same privacy-aware artwork service.
struct ViewerInformation
{
    using wnd:           Wnd
    late window:         *ViewerWindow
    viewer:              *EmbeddedViewer?
    entry:               ExplorerEntry
    hasSubject:          bool
    location:            String
    subjectLocation:     String
    archivePath:         String
    extracted:           String
    retiredExtractions:  Array'String
    onlinePending:       bool
    extractionAttempted: bool
    extractionFailure:   String
    locationName:        String
    status:              String
    kind:                String
    isArchive:           bool
    archive:             Viewers.Archive.Zip
    album:               bool
    preview:             ExplorerPreview
    settings:            String
    loadedSettings:      String
    loadedPath:          String
    picture:             Texture
    refreshing:          bool
    includeAction:       bool
    includeTechnical:    bool = true
    includeFile:         bool = true
    refreshPosted:       bool
    needsRetirement:     bool
}

impl ViewerInformation
{
    func create(parent: *Wnd, window: *ViewerWindow)->*ViewerInformation
    {
        let result = Wnd.create'ViewerInformation(parent, "scope.information.source")
        result.window    = window
        result.dockStyle = .None
        result.hide()
        result.hookOnChildEvent = func|source = result|(_, evt)
        {
            if evt is TaskEvent do
                source.postRefresh()
            return false
        }

        return result
    }

    mtd selectExplorer(explorer: *Explorer)
    {
        if explorer.listing.isArchive and .archivePath != explorer.listing.path do
            .hasSubject = false
        if explorer.selected < explorer.entries.count
        {
            let entry = &explorer.entries[explorer.selected]
            .select(entry, localFile: not explorer.listing.isArchive)
        }
        else
        {
            .hasSubject = false
            .entry      = {}
            .stop()
        }

        .location = explorer.listing.isArchive ? explorer.folder : explorer.listing.path
        Path.normalize(&.location)
        .subjectLocation = explorer.locationText()
        .archivePath     = explorer.listing.path
        .locationName    = explorer.locationName()
        .status          = explorer.status.text()
        .isArchive       = explorer.listing.isArchive
        .archive         = explorer.listing.archive
        .album           = explorer.grid.board == .Album
    }

    mtd selectFile(path: string)
    {
        var entry: ExplorerEntry
        entry.path = path
        entry.name = Path.fileName(path) orelse path
        .select(&entry)
        .location = Path.directoryName(path) orelse ""
        Path.normalize(&.location)
        .locationName = ViewerHome.folderText(path)
        .isArchive    = false
        .album        = false
    }

    private mtd select(selection: const *ExplorerEntry, localFile = true)
    {
        var subject = selection[]
        if localFile and not selection.directory and not selection.path.isEmpty()
        {
            catch
            {
                let info     = try File.info(selection.path)
                let modified = Hash.hash64(info.lastWriteTime)
                let created  = Hash.hash64(info.creationTime)
                let known    = selection.modifiedStamp != 0 or selection.creationStamp != 0
                let changed  = known and
                               (selection.size != info.size or
                                (selection.modifiedStamp != 0 and selection.modifiedStamp != modified) or
                                (selection.creationStamp != 0 and selection.creationStamp != created))
                if changed do
                    subject = {name: selection.name, path: selection.path}
                subject.size          = info.size
                subject.creationStamp = created
                subject.modifiedStamp = modified
                subject.modified      = info.lastWriteTime.toString(.DateTimeIsoHm)
            }
        }

        let entry = &subject
        if not .hasSubject or
           .entry.path != entry.path or
           .entry.name != entry.name or
           .entry.size != entry.size or
           .entry.modifiedStamp != entry.modifiedStamp
        {
            .preview.task.cancel()
            .onlinePending       = false
            .extractionAttempted = false
            .extractionFailure.clear()
            if not .extracted.isEmpty()
            {
                .retiredExtractions.add(.extracted)
                .extracted.clear()
            }

            .needsRetirement = .viewer != null
            .loadedPath.clear()
            .loadedSettings.clear()
            .app().renderer.removeTexture(&.picture)
            .entry      = entry[]
            .hasSubject = true
            .kind.clear()
            let choices = .window.index.choices(entry.path.isEmpty() ? entry.name.toString() : entry.path.toString())
            if not choices.isEmpty() do
                .kind = choices[0].key
        }
        elif not .picture.isValid() and
             (entry.path.isEmpty() or
              not entry.movie.title.isEmpty() or
              not entry.music.title.isEmpty() or
              not entry.music.track.isEmpty())
        {
            // Reuse already published artwork, without taking its texture ownership.
            .entry = entry[]
        }
    }

    mtd request()
    {
        if .refreshing do
            return
        .refreshing = true
        defer .refreshing = false
        if .needsRetirement and .viewer
        {
            let viewer: Viewer.Embedded = .viewer
            if not viewer.retire() do
                return
            .needsRetirement = false
        }

        for file in .retiredExtractions do
            discard catch File.delete(file[])
        .retiredExtractions.clear()
        if not .window.infoSheet.isLocallyVisible() or not .hasSubject or .entry.directory do
            return
        if .isArchive and .extracted.isEmpty() and not .matchesCurrentFile()
        {
            if not .preview.started and
               not .extractionAttempted and
               .entry.archiveIndex < .archive.entries.count
            {
                .extractionAttempted  = true
                .preview.path         = .entry.path
                .preview.archivePath  = .archivePath
                .preview.entry        = .archive.entries[.entry.archiveIndex]
                .preview.opening      = true
                .preview.online       = false
                .preview.durationHint = 0
                .preview.privacy      = .window.privacy.policy(.archivePath)
                .preview.start(me)
            }

            return
        }

        let file    = .isArchive ? .extracted.toString() : .entry.path.toString()
        let showing = .matchesCurrentFile() and .window.activeChoiceIndex < .window.instances.count
        if not showing and not File.exists(file) do
            return
        if not showing and not .viewer
        {
            .viewer = EmbeddedViewer.create(me, .window)
            .viewer.informationOnly = true
            .viewer.hide()
        }

        if not showing and .viewer and .viewer.fileName != file
        {
            let viewer: Viewer.Embedded = .viewer
            if not viewer.retire() do
                return
            catch viewer.open(file, .entry.name)
        }

        if not showing and .viewer
        {
            for choice, index in .viewer.choices where choice.key == .kind and index != .viewer.activeIndex
            {
                discard .viewer.activate(cast(u32, index))
                break
            }
        }

        if .isArchive or not .hasMediaSelection() do
            return
        let settings = ThumbnailSettings.capture(.window, &.entry)
        if not .settings.isEmpty() and settings != .settings
        {
            .onlinePending = false
            let previous = catch ThumbnailSettings.decode(.settings) orelse {}
            let current  = catch ThumbnailSettings.decode(settings) orelse {}
            if previous.onlineMovies and not current.onlineMovies do
                .entry.movie = {}
            if previous.onlineMusic and not current.onlineMusic do
                .entry.music = {}
        }

        .settings = settings
        if .preview.started
        {
            if .preview.path != .entry.path or .preview.settings != .settings do
                .preview.task.cancel()
            return
        }

        if .loadedPath == .entry.path and .loadedSettings == .settings do
            return
        .preview.path = .entry.path
        .preview.archivePath.clear()
        .preview.opening      = false
        .preview.settings     = .settings
        .preview.online       = .onlinePending
        .preview.durationHint = .entry.duration
        .preview.privacy      = .window.privacy.policy(.entry.path)
        .preview.start(me)
    }

    mtd stop()
    {
        .preview.task.cancel()
        .needsRetirement = .viewer != null
        .request()
    }

    // Refresh only after the viewer has finished handling its event, so retirement cannot
    // destroy a viewer while one of its own callbacks is still on the stack.
    mtd postRefresh()
    {
        if .refreshPosted do
            return
        .refreshPosted = true
        .postCommandEvent("scope.information.ready")
    }

    // Dispatches the entire sheet to the corresponding viewer, including its shared file identity.
    mtd describe(sheet: *InfoSheet, includeAction = false, includeTechnical = true, includeFile = true)
    {
        .includeAction    = includeAction
        .includeTechnical = includeTechnical
        .includeFile      = includeFile
        if .matchesCurrentFile() and .window.activeChoiceIndex < .window.choices.count do
            .kind = .window.choices[.window.activeChoiceIndex].key
        .request()
        let instance = .session()
        if instance and instance.describeInformation do
            instance.describeInformation(sheet)
        else do
            .present(sheet)
    }

    // Completes a viewer's information callback with its media identity, artwork and file readings.
    mtd present(sheet: *InfoSheet)
    {
        let page = sheet.pageIndex
        sheet.clear()
        let media = .hasMediaSelection()
        if media do
            sheet.beginPage(MediaInfoRow{field: .Media}.label())
        .describeContent(sheet, .includeAction, includeTechnical: .includeTechnical and not media, includeFile: .includeFile and not media)
        if media and .includeTechnical
        {
            sheet.beginPage(MediaInfoRow{field: .Technical}.label())
            .describeSelectedTechnical(sheet, includeFile: .includeFile, labelled: false)
        }

        sheet.selectPage(page)
    }

    private mtd matchesCurrentFile()->bool
    {
        if .window.currentFile.isEmpty() do
            return false
        if Path.equals(.window.currentFile, .entry.path) do
            return true
        if .isArchive and .window.explorer
        {
            let logical = Format.toString("%/%", .window.explorer.logicalPath(.archivePath), .entry.path)
            return Path.equals(.window.explorer.logicalPath(.window.currentFile), logical)
        }

        return false
    }

    private mtd session()->*ViewerSession?
    {
        if .matchesCurrentFile() and .window.activeChoiceIndex < .window.instances.count do
            return &.window.instances[.window.activeChoiceIndex]
        if .viewer and
           (.viewer.fileName == .entry.path or (.isArchive and .viewer.fileName == .extracted)) and
           .viewer.activeIndex < .viewer.instances.count do
            return &.viewer.instances[.viewer.activeIndex]
        return null
    }

    private mtd openActionName()->String
    {
        let point = .entry.directory ? null : .window.resumePoint(.entry.path)
        return point ? point.positionText() : String.from(appStrings().cmd_OpenChosen)
    }

    // Describes the chosen item in `sheet`: its picture, its title, the figures and the readings
    // known of it, then the file itself; with nothing chosen, the location and how much it holds.
    private mtd describeContent(sheet: *InfoSheet, includeAction = true, includeTechnical = true, includeFile = true)
    {
        let strings = appStrings()
        if not .hasSubject
        {
            sheet.setSubjectFile(.archivePath, directory: not .isArchive)
            sheet.setTitle(.locationName)
            sheet.setIdentity(.subjectLocation)
            sheet.addText(.status)
            return
        }

        let entry = &.entry
        sheet.setSubjectFile(entry.name, directory: entry.directory)
        if .hasMediaSelection() and entry.texture.isValid() and entry.texture.width > 1
        {
            sheet.setPicture(entry.texture)
            sheet.setPictureBeside(true)
        }

        sheet.setTitle(safeMediaText(.selectionTitle(entry)))
        sheet.setIdentity(.selectionIdentity(entry))

        // A film is headed by its poster, its title, its year and length, and its rating, the
        // figure a reader of a film comes for, with its source as its unit; then the action, what
        // it tells, who made it and played in it, and at its foot who said so.
        if not entry.movie.title.isEmpty()
        {
            sheet.setPictureBeside(true)
            if not entry.movie.imdbRating.isEmpty()
            {
                var rating = safeMediaText(entry.movie.imdbRating)
                let slash  = Utf8.indexOf(rating, "/")
                if slash != Swag.U64.Max do
                    rating = String.from(rating.toString()[0 until slash])
                sheet.addFact(rating, entry.movie.ratingSource == "TMDB" ? "TMDB" : "IMDb")
            }

            if includeAction do
                sheet.setAction(.openActionName(), ViewerCommands.OpenChosen)
            if entry.movie.overview.length do
                sheet.addText(safeMediaText(entry.movie.overview))
            addSheetReading(sheet, strings.explore_MovieGenre, entry.movie.genre)
            addSheetReading(sheet, strings.explore_Director, entry.movie.director)
            addSheetReading(sheet, strings.explore_Cast, entry.movie.actors)
            if includeTechnical do
                .describeSelectedTechnical(sheet, includeFile: includeFile)
            if not entry.movie.sources.isEmpty() do
                sheet.addFootnote(Format.toString("% %", strings.explore_Sources, safeMediaText(entry.movie.sources)))
            return
        }

        // A recording, or an album, is headed by its cover and its length; then what it is part
        // of, and at its foot where these readings came from.
        if not entry.music.track.isEmpty() or not entry.music.title.isEmpty()
        {
            if entry.texture.isValid() and entry.texture.width > 1 do
                sheet.setPictureBeside(true)
            if entry.duration do
                sheet.addFact(formatDuration(entry.duration))

            // The album page already offers Play in Voltage: its sheet keeps the quiet form.
            if includeAction do
                sheet.setAction(.openActionName(), ViewerCommands.OpenChosen, quiet: .album)
            if not entry.directory and not entry.music.track.isEmpty() do
                addSheetReading(sheet, strings.explore_Album, entry.music.title)
            addSheetReading(sheet, strings.explore_Artist, entry.music.artist)
            if entry.music.albumArtist != entry.music.artist do
                addSheetReading(sheet, strings.explore_AlbumArtist, entry.music.albumArtist)
            addSheetReading(sheet, strings.explore_FirstRelease, entry.music.date, mono: true)
            if includeTechnical do
                .describeSelectedTechnical(sheet, includeFile: includeFile)
            if entry.music.source == "tags" do
                sheet.addFootnote(Format.toString("% %", strings.explore_Source, strings.explore_FileTags))
            elif not entry.music.source.isEmpty() do
                sheet.addFootnote(Format.toString("% %", strings.explore_Source, "MusicBrainz"))
            return
        }

        // A rating is the figure a reader of a film comes for, with its source as its unit.
        if not entry.movie.imdbRating.isEmpty() do
            sheet.addFact(safeMediaText(entry.movie.imdbRating), entry.movie.ratingSource == "TMDB" ? "TMDB" : "IMDb")
        if entry.duration do
            addFigure(sheet, sheetDuration(entry.duration))

        if .isArchive and entry.archiveIndex < .archive.entries.count
        {
            if includeAction
            {
                sheet.setAction(strings.cmd_OpenChosen, ViewerCommands.OpenChosen)
                sheet.setSecondaryAction(strings.cmd_Extract, ViewerCommands.ExtractChosen)
            }

            if includeTechnical do
                .describeSelectedTechnical(sheet, includeFile: includeFile)
            return
        }

        if includeAction
        {
            sheet.setAction(.openActionName(), ViewerCommands.OpenChosen)
            if .isArchive do
                sheet.setSecondaryAction(strings.cmd_Extract, ViewerCommands.ExtractChosen)
        }

        if includeTechnical
        {
            .describeSelectedTechnical(sheet, includeFile: includeFile)
        }
        elif includeFile
        {
            sheet.addSection(strings.explore_FileProperties)
            .describeSelectedFile(sheet)
        }

        // A film without online details says how to get them.
        if isFilmFile(entry) and not .window.onlineMovies do
            sheet.addFootnote(strings.explore_OnlineOff, strings.explore_TurnOn, ViewerCommands.OnlineMovies)
    }

    // Returns the title the sheet gives `entry`: what a film or a recording is called, the title
    // a film's own file name gives, or its name.
    private mtd selectionTitle(entry: const *ExplorerEntry)->String
    {
        if not entry.movie.title.isEmpty() do
            return String.from(entry.movie.title)
        if not entry.directory and not entry.music.track.isEmpty() do
            return String.from(entry.music.track)
        if not entry.music.title.isEmpty() do
            return String.from(entry.music.title)
        if isFilmFile(entry)
        {
            let query = MovieQuery.fromFile(entry.name)
            if not query.title.isEmpty() do
                return query.title
        }

        return String.from(entry.name)
    }

    // Returns the identity line of `entry`: a film's year and length, a recording's artist and
    // album, or the kind of a file and where it stands, after the year a film's file name gives.
    private mtd selectionIdentity(entry: const *ExplorerEntry)->String
    {
        let strings = appStrings()
        if not entry.movie.title.isEmpty()
        {
            var parts: Array'String
            if entry.movie.date.length >= 4 do
                parts.add(String.from(entry.movie.date.toString()[0 until 4]))
            if entry.duration >= 60
            {
                let minutes = Format.toString("%{02}", (entry.duration / 60) % 60)
                parts.add(Format.toString(strings.explore_Length, entry.duration / 3600, minutes))
            }

            return parts.isEmpty() ? String.from(entry.name) : joinMeasures(parts.toSlice())
        }

        if not entry.music.track.isEmpty() or not entry.music.title.isEmpty()
        {
            var parts: Array'String
            parts.add(safeMediaText(entry.music.artist))
            if not entry.directory and not entry.music.track.isEmpty() do
                parts.add(safeMediaText(entry.music.title))
            elif entry.music.date.length do
                parts.add(safeMediaText(entry.music.date))
            let identity = joinMeasures(parts.toSlice())
            return identity.isEmpty() ? String.from(entry.name) : identity
        }

        // A file is placed by its kind and by the folder, or the archive folder, it stands in.
        var place = String.from(.location)
        if place.length and place.back() == '/' do
            place.removeBack()
        let kind = String.toUpper(Path.extension(entry.name) orelse "", .Unicode)
        if entry.directory or kind.length <= 1 do
            return place
        let identity = Format.toString("% · %", kind.toString()[1 to], place)
        let year     = isFilmFile(entry) ? MovieQuery.fromFile(entry.name).year : String.from("")
        return year.isEmpty() ? identity : Format.toString("% · %", year, identity)
    }

    // Adds the measurements already read for a thumbnail or a listing cell; the size of a picture
    // is one of the figures heading the sheet.
    private mtd describeTechnical(sheet: *InfoSheet, entry: const *ExplorerEntry, labelled = true)
    {
        var data = MediaInfoData{}
        if labelled do
            data.add(.Technical, group: true)
        for row in entry.technical.rows do
            data.rows.add(row)
        if entry.width and entry.height do
            data.add(.Dimensions, Format.toString("% × % px", entry.width, entry.height))
        if entry.pages do
            data.add(.Pages, Format.toString("%", entry.pages))
        if entry.lines do
            data.add(.Lines, Format.toString("%", entry.lines))
        if entry.sections do
            data.add(.Sections, Format.toString("%", entry.sections))
        if entry.members do
            data.add(.Members, Format.toString("%", entry.members))
        if not entry.face.isEmpty() do
            data.add(.Typeface, entry.face)
        data.describe(sheet)
    }

    // Adds the readings of the file of the chosen item: its name when the sheet is titled by
    // what it holds, and when it changed.
    mtd describeSelectedFile(sheet: *InfoSheet)
    {
        if not .hasSubject do
            return
        let entry   = &.entry
        let strings = appStrings()
        if .selectionTitle(entry) != entry.name do
            sheet.addReading(strings.explore_Name, entry.name)
        addSheetReading(sheet, strings.explore_Modified, entry.modified, mono: true)
    }

    // Films and recordings keep the same two pages even while online enrichment is off or pending.
    mtd hasMediaSelection()->bool => .hasSubject and
                                     (.kind == "video" or .kind == "sound" or not .entry.movie.title.isEmpty() or not .entry.music.title.isEmpty() or not .entry.music.track.isEmpty())

    // Adds the technical page of the chosen item: what its thumbnail measured, then its file.
    //
    // On its own page the readings need no section label: the page is named for them.
    mtd describeSelectedTechnical(sheet: *InfoSheet, includePreview = true, includeFile = true, labelled = true)
    {
        if not .hasSubject do
            return
        let entry = &.entry
        if includePreview
        {
            let instance = .session()
            if instance and instance.localInformation do
                instance.localInformation(sheet)
            elif instance and not instance.details.isEmpty() do
                sheet.addText(instance.details)
            else do
                .describeTechnical(sheet, entry, labelled)
            if instance and not instance.failureReason.isEmpty() do
                sheet.addNote(instance.failureReason)
            elif not .extractionFailure.isEmpty() do
                sheet.addNote(.extractionFailure)
        }

        if not includeFile do
            return
        if entry.directory and entry.children != Swag.U64.Max do
            addFigure(sheet, entry.children == 1 ? appStrings().explore_OneItem : Format.toString(appStrings().explore_Count, entry.children))
        elif not entry.directory do
            addFigure(sheet, StrConv.toDisplaySize(entry.size))
        if .isArchive and entry.archiveIndex < .archive.entries.count
        {
            let strings = appStrings()
            let member  = &.archive.entries[entry.archiveIndex]
            sheet.addSection(strings.explore_Archive)
            sheet.addReading(strings.explore_Compressed, StrConv.toDisplaySize(member.compressedSize))
            sheet.addReading(strings.explore_Compression,
                             member.method == 0 ? strings.explore_Stored : strings.explore_Deflated,
                             mono: false)
            let crc = Format.toString("%{X08}", member.crc32)
            sheet.addReading("CRC-32", Format.toString("% %", crc.toString()[0 until 4], crc.toString()[4 to]))
        }

        sheet.addSection(appStrings().explore_FileProperties)
        .describeSelectedFile(sheet)
        if not .kind.isEmpty()
        {
            for &plugin in .window.index.plugins where plugin.key == .kind
            {
                sheet.addReading(appStrings().ui_Viewer, plugin.displayName(), mono: false)
                break
            }
        }
    }
}

impl IWnd for ViewerInformation
{
    mtd impl onTaskEvent(evt: *TaskEvent)
    {
        if .preview.claim(evt)
        {
            .preview.wait()
            if not .preview.task.isCancelled() and
               .preview.path == .entry.path and
               (.preview.opening ? .preview.archivePath == .archivePath : .preview.settings == .settings)
            {
                if .preview.opening
                {
                    .extractionFailure = .preview.error
                    .extracted         = .preview.temporary
                    .preview.temporary.clear()
                    if not .extracted.isEmpty() do
                        .window.privacy.inherit(.extracted, .archivePath)
                }

                .onlinePending  = .preview.needsOnline
                .entry.duration = Math.max(.entry.duration, .preview.durationHint)
                .loadedPath     = .preview.path
                .loadedSettings = .preview.settings
                if .preview.image.isValid()
                {
                    .app().renderer.removeTexture(&.picture)
                    .picture        = .app().renderer.addImage(&.preview.image)
                    .entry.texture  = .picture
                    .entry.duration = thumbnailDuration(&.preview.image)
                    let movie = MovieSummary.fromImage(&.preview.image)
                    let music = MusicSummary.fromImage(&.preview.image)
                    if not movie.title.isEmpty() do
                        .entry.movie = movie
                    if not music.title.isEmpty() or not music.track.isEmpty() do
                        .entry.music = music
                }

                if .preview.needsOnline
                {
                    .loadedSettings.clear()
                    .preview.online = true
                }
            }

            if not .preview.temporary.isEmpty()
            {
                discard catch File.delete(.preview.temporary)
                .preview.temporary.clear()
            }
        }
        else
        {
            evt.accepted = false
        }

        .request()
        if .window.infoSheet.isLocallyVisible() do
            .window.refreshInformation()
    }

    mtd impl onCommandEvent(evt: *CommandEvent)
    {
        if evt.id != "scope.information.ready"
        {
            evt.accepted = false
            return
        }

        .refreshPosted = false
        .request()
        if .window.infoSheet.isLocallyVisible() do
            .window.refreshInformation()
    }

    mtd impl onDestroyEvent(_: *DestroyEvent)
    {
        .preview.task.cancel()
        .preview.wait()
        .app().renderer.removeTexture(&.picture)
        if not .extracted.isEmpty() do
            discard catch File.delete(.extracted)
        for file in .retiredExtractions do
            discard catch File.delete(file[])
    }
}

private func isFilmFile(entry: const *ExplorerEntry)->bool => not entry.directory and not albumAudio(entry.name) and Reader.canOpen(entry.name)

// Adds a reading of `value` under `label` to the sheet, unless nothing is known of it.
private func addSheetReading(sheet: *InfoSheet, label, value: string, mono = false)
{
    if value.count do
        sheet.addReading(label, safeMediaText(value), mono: mono)
}
