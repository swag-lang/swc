#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Gui, Viewers

// Resource syntax must not leak assignment punctuation into document labels and notices.
#test
{
    var host: Testing.HeadlessHost
    host.setup(560, 400)
    defer discard catch host.app.setLanguage(ReferenceLanguage)
    Docx.registerTexts(&host.app)
    Rtf.registerTexts(&host.app)
    Pptx.registerTexts(&host.app)
    expect host.app.setLanguage("fr")
    Swag.require(Docx.texts().ui_Name == "Document Word")
    Swag.require(Docx.texts().ui_OneTable == " · 1 tableau")
    Swag.require(Docx.texts().ui_PageElementsSimplified == " · en-têtes et pieds de page simplifiés")
    Swag.require(Docx.texts().ui_SectionLayoutSimplified == " · certaines mises en page de section sont simplifiées")
    Swag.require(Docx.texts().ui_FootnotesTitle == "Notes de bas de page")
    Swag.require(Docx.texts().ui_FootnoteOmitted == "[Note de bas de page non affichée]")
    Swag.require(Docx.texts().ui_FootnoteReturn == "Retour à la référence %")
    Swag.require(Docx.texts().ui_CommentsTitle == "Commentaires")
    Swag.require(Docx.texts().ui_CommentOmitted == "[Commentaire non affiché]")
    Swag.require(Docx.texts().ui_CommentReturn == "Retour au passage commenté")
    Swag.require(Docx.texts().ui_CommentsSimplified == " · plages et placement des commentaires simplifiés")
    Swag.require(Docx.texts().ui_LinksSimplified == " · certains liens sont simplifiés")
    Swag.require(Rtf.texts().ui_Name == "Document de texte enrichi")
    Swag.require(Rtf.texts().ui_ImageOmitted == "[Image non affichée]")
    Swag.require(Pptx.texts().ui_Name == "Présentation")
    Swag.require(Pptx.texts().ui_Previous == "Diapositive précédente")
    Swag.require(Format.toString(Pptx.texts().ui_CurrentSlide, 1, 2) == "Présentation · diapositive 1 sur 2")
}
