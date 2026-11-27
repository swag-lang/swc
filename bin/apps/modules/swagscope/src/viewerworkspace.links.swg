#global internal

using Core, Gui

impl ViewerWorkspace
{
    mtd canLinkFraming()->bool
    {
        let scene = unwrap .scene()
        var images: u32
        for view in scene.views where sceneImage(view.document)
        {
            images += 1
        }

        return images >= 2
    }

    mtd canLinkScroll()->bool
    {
        let scene = unwrap .scene()
        var pages, editors, others, scrolls: u32
        for view in scene.views
        {
            let content = view.document?.currentView
            let scroll  = firstDocumentScroll(content)
            if not scroll and not (content is Viewers.PdfDocument.Panel)
            {
                continue
            }

            if content is Viewers.PdfDocument.Panel
            {
                pages += 1
            }
            else if sceneTextEditor(view.document)
            {
                editors += 1
            }
            else
            {
                others += 1
            }

            if scroll
            {
                scrolls += 1
            }
        }

        return pages >= 2 or editors >= 2 or others > 0 and scrolls >= 2
    }

    mtd canLinkExplorer()->bool
    {
        if not .isTiled()
        {
            return false
        }

        let scene = unwrap .scene()
        if scene.compared
        {
            return false
        }

        for view, index in scene.views
        {
            if let document = view.document where document.isExploring() and
                                                  not document.explorer!.listing.isArchive and
                                                  .explorerContentCell(scene, index) != Swag.U64.Max
            {
                return true
            }
        }

        return false
    }

    mtd hasViewLinks()->bool =>
        .canLinkExplorer() or (.documentCount() > 1 and (.isMediaScene() or .canLinkFraming() or .canLinkScroll()))

    // Prefer an existing content panel after the Explorer in grid order, then a vacant cell.
    private mtd explorerContentCell(scene: const *ViewerScene, source: u64)->u64
    {
        let cells   = scene.cellCount()
        let first   = scene.cellOf(source)
        var vacancy = Swag.U64.Max
        for distance in 1 until cells
        {
            let cell  = (first + distance) % cells
            let index = scene.viewInCell(cell)
            if index == Swag.U64.Max
            {
                if vacancy == Swag.U64.Max
                {
                    vacancy = cell
                }
            }
            else if let document = scene.views[index].document where not document.isExploring()
            {
                return cell
            }
        }

        return vacancy
    }

    mtd openLinkedExplorerFile(source: *ViewerWindow, path: string, singleClick = false)->bool
    {
        let scene = .scene()
        if not scene or
           not .isTiled() or
           scene.compared or
           not scene.linked or
           not scene.links.explorer or
           (singleClick and not scene.links.explorerSingleClick)
        {
            return false
        }

        for view, index in scene.views where view.document == source
        {
            let cell = .explorerContentCell(scene, index)
            if cell == Swag.U64.Max
            {
                return false
            }

            let target = scene.viewInCell(cell)
            if target == Swag.U64.Max
            {
                scene.views.add({path: String.from(path), cellPlusOne: cell + 1})
                ViewerWorkspace.attachDocument(me, scene.views.backPtr(), remember: true)
                .layoutScene()
            }
            else
            {
                let document = unwrap scene.views[target].document
                if not Path.equals(document.pendingFile, path) and
                   (not document.pendingFile.isEmpty() or not Path.equals(document.currentFile, path))
                {
                    .replaceDocument(target, path, select: false)
                }
            }

            return true
        }

        return false
    }

    mtd registerReadingLinks(document: *ViewerWindow)
    {
        if not document.currentView
        {
            return
        }

        let workspace = me
        if document.currentView is Viewers.PdfDocument.Panel as pdf
        {
            pdf.pdfView.sigPageChanged += func|workspace, document|(_)
            {
                workspace.linkReading(document)
            }
        }
        else if let scroll = firstDocumentScroll(document.currentView)
        {
            scroll.sigScrollPositionChanged += func|workspace, document|(_, _, _)
            {
                workspace.linkReading(document)
            }
        }

        if let image = sceneImage(document)
        {
            image.sigZoomChanged += func|workspace, document|(_) { workspace.linkReading(document) }
            image.sigPanChanged  += func|workspace, document|(_) { workspace.linkReading(document) }
        }
    }

    mtd linkReading(document: *ViewerWindow)
    {
        let scene = .scene()
        if not scene or
           not scene.linked or
           scene.views.count < 2 or
           .readingLinksBusy or
           .activeDocument() != document
        {
            return
        }

        .readingLinksBusy = true
        defer .readingLinksBusy = false

        if scene.links.framing
        {
            let source = sceneImage(document)
            if source
            {
                for view in scene.views where view.document != document
                {
                    let target = sceneImage(view.document)
                    if target
                    {
                        linkImages(source, target)
                    }
                }
            }
        }

        if scene.links.scroll
        {
            if document.currentView is Viewers.PdfDocument.Panel as pdf
            {
                let page = pdf.pdfView.pageIndex
                for &view in scene.views where view.document != document
                {
                    if view.document?.currentView is Viewers.PdfDocument.Panel as other where other.pdfView.pageIndex != page
                    {
                        other.pdfView.showPage(page)
                    }
                }
            }
            else if let source = sceneTextEditor(document)
            {
                let line = source.topLogicalLineNumber()
                if line
                {
                    for view in scene.views where view.document != document
                    {
                        if let target = sceneTextEditor(view.document)
                        {
                            discard target.scrollToLogicalLine(line)
                        }
                    }
                }
            }
            else if let source = firstDocumentScroll(document.currentView)
            {
                let pos = source.scrollPosition()
                for view in scene.views where view.document != document
                {
                    if let target = firstDocumentScroll(view.document?.currentView)
                    {
                        target.setScrollPos(pos)
                    }
                }
            }
        }
    }
}

private func firstDocumentScroll(wnd: *Wnd?)->*ScrollWnd?
{
    if not wnd
    {
        return null
    }

    if wnd is ScrollWnd as scroll
    {
        return scroll
    }

    for child in wnd.children
    {
        if let scroll = firstDocumentScroll(child[])
        {
            return scroll
        }
    }

    return null
}

private func sceneTextEditor(document: *ViewerWindow?)->*RichEditCtrl?
{
    switch document?.currentView
    {
    case Viewers.PlainText.Panel as text: return text.editor
    case Viewers.Code.Panel as code:      return code.editor
    default: return null
    }
}

private func sceneImage(document: *ViewerWindow?)->*ImageView?
{
    switch document?.currentView
    {
    case Viewers.Picture.Panel as picture: return picture.imageView
    case Viewers.Film.Panel as film:       return film.imageView
    default: return null
    }
}

private func linkImages(source, target: *ImageView)
{
    let from = source.clientRect()
    let into = target.clientRect()
    if source.isFitted
    {
        if not target.isFitted
        {
            target.zoomToFit()
        }
    }
    else
    {
        let zoom = source.zoom * target.fittedZoom() / Math.max(source.fittedZoom(), 0.001)
        if target.isFitted or Math.abs(target.zoom - zoom) > 0.001
        {
            target.setZoom(zoom)
        }
    }

    let offset = Math.Point{
        source.panOffset.x * into.width / Math.max(from.width, 1),
        source.panOffset.y * into.height / Math.max(from.height, 1)}
    if target.panOffset != offset
    {
        target.setPanOffset(offset)
    }
}
