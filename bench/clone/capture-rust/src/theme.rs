use eframe::egui::{
    self, Color32, FontData, FontDefinitions, FontFamily, FontId, Stroke, TextStyle,
};
use std::collections::HashMap;

pub const INSET: f32 = 24.;
pub const INSPECTOR: f32 = 304.;
pub const STRIP: f32 = 52.;
pub const CELL: f32 = 30.;
pub const CORNER: u8 = 12;
pub const ICON: &[u8] = include_bytes!("../../../../bin/apps/modules/swagcapture/datas/appicon.png");
pub const LICENSES: &str = include_str!(concat!(env!("OUT_DIR"), "/licenses.txt"));

pub fn font_key(name: &str, bold: bool, italic: bool) -> String {
    format!(
        "{name}{}{}",
        if bold { " Bold" } else { "" },
        if italic { " Italic" } else { "" }
    )
}

pub fn fonts_for<'a>(names: impl Iterator<Item = &'a str>) -> FontDefinitions {
    let mut fonts = FontDefinitions::default();
    for (name, bytes) in [
        (
            "Inter",
            include_bytes!("../../../../bin/std/modules/gui/src/theme/inter-regular.ttf").as_slice(),
        ),
        (
            "Inter Bold",
            include_bytes!("../../../../bin/std/modules/gui/src/theme/inter-bold.ttf").as_slice(),
        ),
        (
            "Inter Italic",
            include_bytes!("../../../../bin/std/modules/gui/src/theme/inter-italic.ttf").as_slice(),
        ),
        (
            "Inter Bold Italic",
            include_bytes!("../../../../bin/std/modules/gui/src/theme/inter-bolditalic.ttf")
                .as_slice(),
        ),
        (
            "Roboto Mono",
            include_bytes!("../../../../bin/std/modules/gui/src/theme/robotomono-regular.ttf")
                .as_slice(),
        ),
    ] {
        fonts
            .font_data
            .insert(name.into(), FontData::from_static(bytes).into());
        fonts
            .families
            .insert(FontFamily::Name(name.into()), vec![name.into()]);
    }
    let names: std::collections::BTreeSet<_> = names
        .chain([
            "Arial",
            "Segoe UI",
            "Times New Roman",
            "Consolas",
            "Roboto Mono",
        ])
        .collect();
    for name in names {
        for (bold, italic) in [(false, false), (true, false), (false, true), (true, true)] {
            let key = font_key(name, bold, italic);
            if fonts.font_data.contains_key(&key) {
                continue;
            }
            if let Some(bytes) = crate::native::font_bytes(name, bold, italic) {
                fonts
                    .font_data
                    .insert(key.clone(), FontData::from_owned(bytes).into());
                fonts
                    .families
                    .insert(FontFamily::Name(key.clone().into()), vec![key]);
            }
        }
    }
    fonts
        .families
        .get_mut(&FontFamily::Proportional)
        .unwrap()
        .insert(0, "Inter".into());
    fonts
        .families
        .get_mut(&FontFamily::Monospace)
        .unwrap()
        .insert(0, "Roboto Mono".into());
    fonts
}

#[derive(Clone, Copy)]
pub struct Palette {
    pub ground: Color32,
    pub surface: Color32,
    pub raised: Color32,
    pub line: Color32,
    pub text: Color32,
    pub soft: Color32,
    pub faint: Color32,
    pub arc: Color32,
    pub selection: Color32,
    pub primary: Color32,
}

impl Palette {
    pub fn new(dark: bool) -> Self {
        let c = |rgb: u32| Color32::from_rgb((rgb >> 16) as u8, (rgb >> 8) as u8, rgb as u8);
        if dark {
            Self {
                ground: c(0x17181c),
                surface: c(0x1f2026),
                raised: c(0x2a2c33),
                line: c(0x33353d),
                text: c(0xecedf0),
                soft: c(0xa3a6b0),
                faint: c(0x737783),
                arc: c(0x38bdf8),
                selection: c(0x213e4c),
                primary: c(0xf7f900),
            }
        } else {
            Self {
                ground: c(0xf5f4f0),
                surface: c(0xffffff),
                raised: c(0xebEae5),
                line: c(0xe0ded7),
                text: c(0x1a1b1e),
                soft: c(0x55585f),
                faint: c(0x72757c),
                arc: c(0x0a7fb5),
                selection: c(0xdceffa),
                primary: c(0x1a1b1e),
            }
        }
    }

    pub fn apply(self, ctx: &egui::Context, dark: bool) {
        ctx.set_theme(if dark {
            egui::ThemePreference::Dark
        } else {
            egui::ThemePreference::Light
        });
        let mut visuals = if dark {
            egui::Visuals::dark()
        } else {
            egui::Visuals::light()
        };
        visuals.panel_fill = self.ground;
        visuals.window_fill = self.surface;
        visuals.extreme_bg_color = self.ground;
        visuals.faint_bg_color = self.raised;
        visuals.override_text_color = Some(self.text);
        visuals.window_stroke = Stroke::new(1.0_f32, self.line);
        visuals.window_corner_radius = CORNER.into();
        visuals.selection.bg_fill = self.selection;
        visuals.selection.stroke = Stroke::new(1.0_f32, self.arc);
        visuals.hyperlink_color = self.arc;
        visuals.widgets.inactive.bg_fill = self.surface;
        visuals.widgets.inactive.weak_bg_fill = self.surface;
        visuals.widgets.inactive.bg_stroke = Stroke::new(1.0_f32, self.line);
        visuals.widgets.inactive.fg_stroke = Stroke::new(1.0_f32, self.soft);
        visuals.widgets.hovered.bg_fill = self.raised;
        visuals.widgets.hovered.weak_bg_fill = self.raised;
        visuals.widgets.active.bg_fill = self.selection;
        visuals.widgets.active.fg_stroke = Stroke::new(1.0_f32, self.arc);
        visuals.widgets.noninteractive.fg_stroke = Stroke::new(1.0_f32, self.soft);
        visuals.widgets.hovered.fg_stroke = Stroke::new(1.0_f32, self.text);
        visuals.widgets.inactive.corner_radius = 6.into();
        visuals.widgets.active.corner_radius = 6.into();
        visuals.widgets.hovered.corner_radius = 6.into();
        ctx.set_visuals(visuals);
        ctx.style_mut(|style| {
            style.spacing.item_spacing = egui::vec2(8., 8.);
            style.spacing.button_padding = egui::vec2(8., 5.);
            style.spacing.interact_size.y = 28.;
            style
                .text_styles
                .insert(TextStyle::Body, FontId::proportional(13.));
            style
                .text_styles
                .insert(TextStyle::Button, FontId::proportional(13.));
            style.text_styles.insert(
                TextStyle::Heading,
                FontId::new(21., FontFamily::Name("Inter Bold".into())),
            );
            style
                .text_styles
                .insert(TextStyle::Monospace, FontId::monospace(12.));
        });
    }

    pub fn frame(self) -> egui::Frame {
        egui::Frame::new()
            .fill(self.surface)
            .stroke(Stroke::new(1.0_f32, self.line))
            .corner_radius(CORNER)
            .inner_margin(20)
            .shadow(egui::Shadow {
                offset: [0, 24],
                blur: 64,
                spread: 0,
                color: Color32::from_black_alpha(32),
            })
    }
}

pub struct Strings {
    translations: HashMap<String, String>,
    pub french: bool,
}

impl Strings {
    pub fn new(french: bool) -> Self {
        let english = include_str!("../../../../bin/apps/modules/swagcapture/src/localization.swg");
        let french_source =
            include_str!("../../../../bin/apps/modules/swagcapture/datas/lang/fr/capture.tweak");
        let values = |source: &str| -> HashMap<String, String> {
            source
                .lines()
                .filter_map(|line| {
                    let first = line.find('"')?;
                    let last = line.rfind('"')?;
                    if last <= first {
                        return None;
                    }
                    let key = line
                        .trim()
                        .split(|c: char| c == ':' || c.is_whitespace())
                        .next()?;
                    Some((key.to_owned(), line[first + 1..last].to_owned()))
                })
                .collect()
        };
        let en = values(english);
        let fr: HashMap<String, String> = french_source
            .lines()
            .filter_map(|line| {
                let line = line.trim();
                if line.is_empty() || line.starts_with('#') {
                    return None;
                }
                let split = line.find(char::is_whitespace)?;
                Some((line[..split].into(), line[split..].trim().into()))
            })
            .collect();
        let mut translations: HashMap<_, _> = en
            .iter()
            .filter_map(|(key, value)| fr.get(key).map(|f| (value.clone(), f.clone())))
            .collect();
        for (a, b) in [
            ("Commands", "Commandes"),
            ("Dark", "Sombre"),
            ("Light", "Clair"),
            ("System", "Système"),
            ("About", "À propos"),
            ("Cancel", "Annuler"),
            ("Close", "Fermer"),
            ("Save", "Enregistrer"),
            ("Create", "Créer"),
            ("Color", "Couleur"),
            ("Fill", "Remplissage"),
            ("Outline", "Contour"),
            ("Stroke", "Trait"),
            ("Effects", "Effets"),
            ("Thickness", "Épaisseur"),
            ("Opacity", "Opacité"),
            ("Rotate", "Rotation"),
            ("Shadow", "Ombre"),
            ("Font", "Police"),
            ("Size", "Taille"),
            ("Ellipse", "Ellipse"),
            ("Rectangle", "Rectangle"),
            ("Rounded Rectangle", "Rectangle arrondi"),
            ("Blur", "Flou"),
            ("Pixelate", "Pixelliser"),
            ("Zoom", "Zoom"),
            ("Strength", "Force"),
            ("Save Capture…", "Enregistrer la capture…"),
            ("Open Capture…", "Ouvrir une capture…"),
            ("Open Capture", "Ouvrir la capture"),
            ("Editor", "Éditeur"),
            ("No commands found", "Aucune commande trouvée"),
            ("Choose Folder…", "Choisir un dossier…"),
            ("No captures", "Aucune capture"),
            ("Capture", "Capture"),
            ("Name", "Nom"),
            ("Properties", "Propriétés"),
            ("Dimensions", "Dimensions"),
            ("Drag to draw", "Glisser pour dessiner"),
            ("Search commands…", "Rechercher une commande…"),
            ("The operation failed.", "L’opération a échoué."),
            ("Save changes?", "Enregistrer les modifications ?"),
            ("Discard", "Abandonner"),
            ("Snap to Forms", "Aligner sur les objets"),
        ] {
            translations.insert(a.into(), b.into());
        }
        Self {
            translations,
            french,
        }
    }
    pub fn text(&self, english: &str) -> String {
        if self.french {
            self.translations
                .get(english)
                .cloned()
                .unwrap_or_else(|| english.into())
        } else {
            english.into()
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn reference_strings_resolve_to_shipped_french_table() {
        let strings = Strings::new(true);
        assert_ne!(strings.text("Capture Area"), "Capture Area");
        assert_ne!(strings.text("Save as Image…"), "Save as Image…");
        assert_eq!(Strings::new(false).text("Capture Area"), "Capture Area");
    }
    #[test]
    fn native_theme_does_not_override_custom_palette() {
        let ctx = egui::Context::default();
        let p = Palette::new(true);
        p.apply(&ctx, true);
        assert_eq!(ctx.style().visuals.override_text_color, Some(p.text));
        assert_eq!(ctx.theme(), egui::Theme::Dark);
    }
}
