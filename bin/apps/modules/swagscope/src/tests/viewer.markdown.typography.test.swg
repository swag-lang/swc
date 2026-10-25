#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Pixel, Gui

// One specimen exercises the title hierarchy, prose rhythm, quote and code of each appearance.
func assertMarkdownTypography(theme: u32, name: string, width = 960'u32, dpiScale = 1'f32)
{
    var host: Testing.HeadlessHost
    host.setup(width, 1200, dpiScale)
    defer host.shutdown()
    let source = """# A quiet document

                    A reading theme gives words room to breathe. **Emphasis** stays within the
                    sentence, and a [link](https://example.com) keeps its own place.

                    ## A section of the manuscript

                    > *A short quotation, with a fine leading rule.*

                    A second paragraph follows the quotation without an oversized gap.

                    ### A smaller heading that wraps naturally in a narrow reading column

                    - A list item with **bold words**.
                    - Another item in the same list.

                    #### Fourth level

                    Ordinary prose separates the levels.

                    ##### Fifth level

                    A short paragraph.

                    ###### Sixth level

                    ```swag
                    let count = 42
                    ```"""
    let view   = Markdown.View.createText(&host.root, source)
    view.resize(width, 1200)
    Viewers.MarkdownText.applyViewerStyle(view, theme, 1)
    view.applyLayout()
    Testing.assertContentFits(view)
    var image = host.render(view)
    Pixel.Testing.assertImageGolden(&image, name)
}

#[Swag.TestTag("golden")]
#test { assertMarkdownTypography(1, "viewer.markdown.typography.github") }

#[Swag.TestTag("golden")]
#test { assertMarkdownTypography(2, "viewer.markdown.typography.newsprint") }

#[Swag.TestTag("golden")]
#test { assertMarkdownTypography(3, "viewer.markdown.typography.night") }

#[Swag.TestTag("golden")]
#test { assertMarkdownTypography(4, "viewer.markdown.typography.pixyll") }

#[Swag.TestTag("golden")]
#test { assertMarkdownTypography(5, "viewer.markdown.typography.whitey") }

#[Swag.TestTag("golden")]
#test { assertMarkdownTypography(5, "viewer.markdown.typography.whitey.narrow", 640, 1.5) }
