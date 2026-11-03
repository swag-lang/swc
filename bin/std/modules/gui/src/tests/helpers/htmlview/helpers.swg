#global if #command == Swag.CompilerCommand.Test
#global internal

using Core, Pixel

func guiFixturePath(name: string)->String => Path.combine(testSourceRoot(#curlocation), Format.toString("datas/%", name).toString())

func htmlFixturePath()->String => guiFixturePath("html.comprehensive.html")

func parseDocument(source: string)->HtmlDocument
{
    var result = HtmlDocument.create()
    var parser: HtmlParser
    parser.start(&result)
    parser.feed(source)
    parser.finish()
    return result
}
