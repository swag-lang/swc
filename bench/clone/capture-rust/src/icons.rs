//! The original Capture vector atlas, rasterized once at a high display density.
use eframe::egui::*;

pub fn paint(painter: &Painter, rect: Rect, index: usize, color: Color32) {
    let ctx = painter.ctx();
    let key = Id::new("capture-vector-atlas");
    let texture = ctx
        .data_mut(|d| d.get_temp::<TextureHandle>(key))
        .unwrap_or_else(|| {
            let svg = include_bytes!("../../../../bin/apps/modules/swagcapture/datas/icons.svg");
            let tree = resvg::usvg::Tree::from_data(svg, &resvg::usvg::Options::default())
                .expect("Embedded icon atlas");
            let mut pixels = resvg::tiny_skia::Pixmap::new(768, 480).unwrap();
            resvg::render(
                &tree,
                resvg::tiny_skia::Transform::from_scale(4., 4.),
                &mut pixels.as_mut(),
            );
            let texture = ctx.load_texture(
                "Capture icons",
                ColorImage::from_rgba_premultiplied([768, 480], pixels.data()),
                TextureOptions::LINEAR,
            );
            ctx.data_mut(|d| d.insert_temp(key, texture.clone()));
            texture
        });
    let x = (index % 8) as f32 / 8.;
    let y = (index / 8) as f32 / 5.;
    painter.image(
        texture.id(),
        rect,
        Rect::from_min_max(pos2(x, y), pos2(x + 1. / 8., y + 1. / 5.)),
        color,
    );
}

pub fn tool(painter: &Painter, rect: Rect, tool: crate::document::Tool, color: Color32) {
    use crate::document::Tool;
    let index = match tool {
        Tool::Shape => 0,
        Tool::Line => 1,
        Tool::Polygon => 2,
        Tool::Arrow => 3,
        Tool::Text => 4,
        Tool::Draw => 7,
        Tool::Highlight => 9,
        Tool::Select => 10,
        Tool::Step => 11,
        Tool::Image => 12,
        Tool::PixelSelection => 16,
        Tool::Callout => {
            let body = Rect::from_center_size(rect.center() - vec2(0., 2.), vec2(10., 6.));
            painter.rect_stroke(body, 3, Stroke::new(1.4_f32, color), StrokeKind::Middle);
            painter.line_segment(
                [
                    body.left_bottom() + vec2(3., 0.),
                    body.left_bottom() + vec2(3., 3.),
                ],
                Stroke::new(1.4_f32, color),
            );
            painter.line_segment(
                [
                    body.left_bottom() + vec2(3., 3.),
                    body.left_bottom() + vec2(6., 0.),
                ],
                Stroke::new(1.4_f32, color),
            );
            return;
        }
    };
    paint(painter, rect, index, color);
}
