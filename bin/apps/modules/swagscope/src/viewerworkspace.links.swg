#global internal

using Core, Gui

impl ViewerWorkspace
{
    mtd registerReadingLinks(document: *ViewerWindow)
    {
        if not document.currentView do
            return
        let workspace = me
        if document.currentView is Viewers.PdfDocument.Panel as pdf
        {
            pdf.pdfView.sigPageChanged += func|workspace, document|(_)
            {
                workspace.linkReading(document)
            }
        }
        elif let scroll = firstDocumentScroll(document.currentView)
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
           .activeDocument() != document do
            return
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
                    if target do
                        linkImages(source, target)
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
                    if view.document?.currentView is Viewers.PdfDocument.Panel as other where other.pdfView.pageIndex != page do
                        other.pdfView.showPage(page)
                }
            }
            elif let source = sceneTextEditor(document)
            {
                let line = source.topLogicalLineNumber()
                if line
                {
                    for view in scene.views where view.document != document
                    {
                        if let target = sceneTextEditor(view.document) do
                            discard target.scrollToLogicalLine(line)
                    }
                }
            }
            elif let source = firstDocumentScroll(document.currentView)
            {
                let pos = source.scrollPosition()
                for view in scene.views where view.document != document
                {
                    if let target = firstDocumentScroll(view.document?.currentView) do
                        target.setScrollPos(pos)
                }
            }
        }
    }
}

private func firstDocumentScroll(wnd: *Wnd?)->*ScrollWnd?
{
    if not wnd do
        return null
    if wnd is ScrollWnd as scroll do
        return scroll
    for child in wnd.children
    {
        if let scroll = firstDocumentScroll(child[]) do
            return scroll
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
        if not target.isFitted do
            target.zoomToFit()
    }
    else
    {
        let zoom = source.zoom * target.fittedZoom() / Math.max(source.fittedZoom(), 0.001)
        if target.isFitted or Math.abs(target.zoom - zoom) > 0.001 do
            target.setZoom(zoom)
    }

    let offset = Math.Point{
        source.panOffset.x * into.width / Math.max(from.width, 1),
        source.panOffset.y * into.height / Math.max(from.height, 1)}
    if target.panOffset != offset do
        target.setPanOffset(offset)
}
