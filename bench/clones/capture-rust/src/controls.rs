//! Controls with Capture's inspector geometry and keyboard behavior.
use crate::theme::Palette;
use eframe::egui::*;

pub fn row(ui: &mut Ui, label: &str, add: impl FnOnce(&mut Ui)) {
    ui.allocate_ui_with_layout(
        vec2(264., 30.),
        Layout::left_to_right(Align::Center),
        |ui| {
            ui.spacing_mut().item_spacing.x = 0.;
            let (rect, _) = ui.allocate_exact_size(vec2(100., 28.), Sense::hover());
            ui.painter().text(
                rect.left_center(),
                Align2::LEFT_CENTER,
                label,
                FontId::proportional(13.),
                ui.visuals().text_color(),
            );
            ui.allocate_ui_with_layout(vec2(164., 28.), Layout::left_to_right(Align::Center), add);
        },
    );
}

pub fn slider(
    ui: &mut Ui,
    label: &str,
    value: &mut f32,
    range: std::ops::RangeInclusive<f32>,
    suffix: &str,
    p: Palette,
) {
    row(ui, label, |ui| {
        let (rect, mut response) = ui.allocate_exact_size(vec2(96., 28.), Sense::click_and_drag());
        let track = Rect::from_center_size(rect.center(), vec2(84., 2.));
        if response.clicked() {
            response.request_focus();
        }
        if response.dragged() || response.clicked() {
            if let Some(pointer) = response.interact_pointer_pos() {
                let t = ((pointer.x - track.left()) / track.width()).clamp(0., 1.);
                *value = (*range.start() + t * (*range.end() - *range.start())).round();
                response.mark_changed();
            }
        }
        if response.has_focus() {
            let step = ui.input(|i| if i.modifiers.shift { 10. } else { 1. });
            if ui.input(|i| i.key_pressed(Key::ArrowRight)) {
                *value = (*value + step).min(*range.end());
            }
            if ui.input(|i| i.key_pressed(Key::ArrowLeft)) {
                *value = (*value - step).max(*range.start());
            }
        }
        let t = ((*value - *range.start()) / (*range.end() - *range.start())).clamp(0., 1.);
        let knob = pos2(track.left() + track.width() * t, track.center().y);
        ui.painter().line_segment(
            [track.left_center(), track.right_center()],
            Stroke::new(2.0_f32, p.raised),
        );
        ui.painter()
            .line_segment([track.left_center(), knob], Stroke::new(2.0_f32, p.arc));
        ui.painter()
            .circle(knob, 6., Color32::WHITE, Stroke::new(1.0_f32, p.faint));
        if response.has_focus() {
            ui.painter()
                .circle_stroke(knob, 9., Stroke::new(1.0_f32, p.primary));
        }
        ui.add_space(20.);
        ui.add_sized(
            [48., 28.],
            DragValue::new(value)
                .range(range)
                .speed(1.)
                .max_decimals(0)
                .suffix(suffix),
        );
    });
}

pub fn color(ui: &mut Ui, label: &str, rgba: &mut [u8; 4], p: Palette) {
    row(ui, label, |ui| {
        ui.add_space(8.);
        ui.scope(|ui| {
            ui.spacing_mut().interact_size = vec2(18., 18.);
            ui.color_edit_button_srgba_unmultiplied(rgba);
        });
        ui.add_space(12.);
        let text = if rgba[3] == 0 {
            "none".into()
        } else {
            format!("{:02X}{:02X}{:02X}", rgba[0], rgba[1], rgba[2])
        };
        ui.label(
            RichText::new(text)
                .font(FontId::monospace(12.))
                .color(p.soft),
        );
    });
}

pub fn choice(ui: &mut Ui, label: &str, value: &mut u32, names: &[&str]) {
    row(ui, label, |ui| {
        ComboBox::from_id_salt(label)
            .width(154.)
            .selected_text(names.get(*value as usize).copied().unwrap_or(names[0]))
            .show_ui(ui, |ui| {
                for (i, name) in names.iter().enumerate() {
                    ui.selectable_value(value, i as u32, *name);
                }
            });
    });
}

pub fn segments(ui: &mut Ui, value: &mut u32, labels: &[&str], p: Palette) {
    let width = ui.available_width().min(154.) / labels.len() as f32;
    ui.spacing_mut().item_spacing.x = 0.;
    for (i, label) in labels.iter().enumerate() {
        let (r, response) = ui.allocate_exact_size(vec2(width, 26.), Sense::click());
        let chosen = *value == i as u32;
        ui.painter()
            .rect_filled(r, 5, if chosen { p.selection } else { p.raised });
        ui.painter().text(
            r.center(),
            Align2::CENTER_CENTER,
            *label,
            if *label == "Aa" {
                FontId::new(
                    12.,
                    FontFamily::Name(
                        crate::theme::font_key("Inter", i & 1 != 0, i & 2 != 0).into(),
                    ),
                )
            } else {
                FontId::proportional(12.)
            },
            if chosen { p.text } else { p.soft },
        );
        if response.clicked() {
            *value = i as u32;
            response.request_focus();
        }
    }
}

pub fn quiet(ui: &mut Ui, label: &str, p: Palette) -> Response {
    ui.add(Button::new(RichText::new(label).size(12.).color(p.soft)).frame(false))
}

pub fn line_preset(ui: &Ui, rect: Rect, style: &crate::document::Style, id: Id) {
    use crate::document::{Form, Tool};
    type Cached = (crate::document::Style, TextureHandle);
    let cached = ui.ctx().data(|data| data.get_temp::<Cached>(id));
    let texture = match cached {
        Some((old, texture)) if old == *style => texture,
        _ => {
            let mut sample = style.clone();
            sample.thickness = 6. + style.thickness.clamp(0., 100.) * 0.03;
            sample.start_size = 2. + style.start_size.clamp(0., 8.) * 0.25;
            sample.arrow_size = 2. + style.arrow_size.clamp(0., 8.) * 0.25;
            sample.line_outline = style.line_outline.clamp(0., 20.) * 0.15;
            let start = pos2(12., 45.);
            let end = pos2(84., 15.);
            let mut form = Form::new(0, Tool::Line, start, sample, 1);
            form.draw_to(start, end, false);
            form.control = [40., 0.];
            let Some(raster) = crate::stroke::rasterize(&form, 1.) else {
                return;
            };
            let pixels = &raster.pixels;
            let texture = ui.ctx().load_texture(
                format!("preset-{id:?}"),
                ColorImage::from_rgba_unmultiplied(
                    [pixels.width() as usize, pixels.height() as usize],
                    pixels.as_raw(),
                ),
                TextureOptions::LINEAR,
            );
            ui.ctx()
                .data_mut(|data| data.insert_temp(id, (style.clone(), texture.clone())));
            texture
        }
    };
    let size = texture.size_vec2();
    let scale = (rect.width() / size.x).min(rect.height() / size.y);
    ui.painter().image(
        texture.id(),
        Rect::from_center_size(rect.center(), size * scale),
        Rect::from_min_max(Pos2::ZERO, pos2(1., 1.)),
        Color32::WHITE,
    );
}

/// Compact visual choices used for line styles and endpoint silhouettes.
pub fn line_choices(ui: &mut Ui, label: &str, value: &mut u32, caps: bool, p: Palette) {
    let names: &[&str] = if caps {
        &[
            "None",
            "Triangle",
            "Round",
            "Square",
            "Arrow",
            "Arrow 2",
            "Square Anchor",
            "Round Anchor",
        ]
    } else {
        &["Solid", "Pattern", "Dotted", "Dashed", "Dash Dot"]
    };
    row(ui, label, |ui| {
        let width = 164. / names.len() as f32;
        for (i, name) in names.iter().enumerate() {
            let (r, response) = ui.allocate_exact_size(vec2(width, 26.), Sense::click());
            let chosen = *value == i as u32;
            if chosen || response.hovered() || response.has_focus() {
                ui.painter().rect_filled(r.shrink(1.), 4, p.selection);
            }
            let ink = if chosen { p.text } else { p.soft };
            if caps {
                let end = r.center() + vec2(4., 0.);
                ui.painter()
                    .line_segment([r.center() - vec2(6., 0.), end], Stroke::new(1.5_f32, ink));
                for polygon in crate::stroke::cap_points(end, Vec2::X, 3., i as u32, 2.2) {
                    if i == 5 {
                        for triangle in [[0, 1, 3], [1, 2, 3]] {
                            ui.painter().add(Shape::convex_polygon(
                                triangle.map(|j| polygon[j]).to_vec(),
                                ink,
                                Stroke::NONE,
                            ));
                        }
                    } else {
                        ui.painter()
                            .add(Shape::convex_polygon(polygon, ink, Stroke::NONE));
                    }
                }
            } else {
                let spans: &[f32] = match i {
                    0 => &[100.],
                    3 => &[6., 3.],
                    4 => &[6., 3., 2., 3.],
                    _ => &[2., 3.],
                };
                let mut x = r.left() + 5.;
                let mut n = 0;
                while x < r.right() - 5. {
                    let end = (x + spans[n % spans.len()]).min(r.right() - 5.);
                    if n % 2 == 0 {
                        ui.painter().line_segment(
                            [pos2(x, r.center().y), pos2(end, r.center().y)],
                            Stroke::new(1.5_f32, ink),
                        );
                    }
                    x = end;
                    n += 1;
                }
            }
            if response.clicked() {
                *value = i as u32;
                response.request_focus();
            }
            if response.has_focus() {
                let delta = ui.input(|input| {
                    input.key_pressed(Key::ArrowRight) as i32
                        - input.key_pressed(Key::ArrowLeft) as i32
                });
                if delta != 0 {
                    *value = (*value as i32 + delta).rem_euclid(names.len() as i32) as u32;
                }
            }
            response.on_hover_text(*name);
        }
    });
}
