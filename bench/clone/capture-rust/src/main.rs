#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

mod app;
mod commands;
mod controls;
mod document;
mod gizmo;
mod icons;
mod library;
mod native;
mod renderer;
mod scc;
mod storage;
mod stroke;
mod tagbin;
mod theme;

use eframe::egui::{self, pos2};
use std::path::PathBuf;

fn demo_document(objects: usize) -> document::Document {
    use document::*;
    let mut doc = Document::blank(1280, 720);
    doc.title = "Capture".into();
    for i in 0..objects {
        let mut style = Style::default();
        style.fill = [
            [232, 8, 8, 255],
            [96, 196, 71, 255],
            [25, 156, 244, 255],
            [253, 223, 27, 255],
        ][i % 4];
        style.font_size = 28.;
        let tool = [
            Tool::Arrow,
            Tool::Shape,
            Tool::Text,
            Tool::Step,
            Tool::Callout,
            Tool::Draw,
        ][i % 6];
        let x = 40. + (i * 173 % 1060) as f32;
        let y = 40. + (i * 97 % 550) as f32;
        doc.create(tool, pos2(x, y), style);
        let form = doc.forms.last_mut().unwrap();
        form.draw_to(pos2(x, y), pos2(x + 130., y + 70.), false);
        if tool == Tool::Step {
            form.bounds[2] = 48.;
            form.bounds[3] = 48.;
        }
        form.text = format!("Capture {}", i + 1);
    }
    doc
}

fn reference_document() -> document::Document {
    let mut doc = document::Document::blank(400, 240);
    let id = doc.create(
        document::Tool::Text,
        pos2(48., 40.),
        document::Style::default(),
    );
    let form = doc.forms.iter_mut().find(|f| f.id == id).unwrap();
    form.bounds = [48., 40., 144., 80.];
    form.text = "Theme".into();
    form.style.fill = [255, 0, 0, 255];
    doc
}

fn main() {
    std::panic::set_hook(Box::new(|info| {
        let root = storage::data_root();
        let _ = std::fs::create_dir_all(&root);
        let _ = std::fs::write(
            root.join("crash.log"),
            format!("{info}\n{}", std::backtrace::Backtrace::force_capture()),
        );
    }));
    if let Err(error) = run() {
        eprintln!("{error}");
        let path = std::env::temp_dir().join("swagcapture-rust-error.txt");
        let _ = std::fs::write(path, &error);
        std::process::exit(1);
    }
}

fn run() -> Result<(), String> {
    native::enable_dpi();
    let args: Vec<_> = std::env::args().skip(1).collect();
    let value = |name: &str| {
        args.iter()
            .position(|a| a == name)
            .and_then(|i| args.get(i + 1))
            .cloned()
    };
    let has = |name: &str| args.iter().any(|a| a == name);
    let objects = value("--objects")
        .and_then(|n| n.parse().ok())
        .unwrap_or(12);
    let root = value("--data-dir")
        .map(PathBuf::from)
        .unwrap_or_else(storage::data_root);
    if let Some(path) = value("--import-settings") {
        storage::Settings::import_swag(&PathBuf::from(path), &root)?;
        return Ok(());
    }
    if has("--audit-library") {
        let report = value("--report").ok_or("--audit-library needs --report.")?;
        let settings = storage::Settings::load(&root);
        let mut entries = vec![];
        for path in storage::recent_paths(&settings.library) {
            entries.push(match storage::load(&path) {
                Ok(doc) => serde_json::json!({ "path": path, "width": doc.width,
                    "height": doc.height, "objects": doc.forms.len(), "error": null }),
                Err(error) => serde_json::json!({ "path": path, "error": error }),
            });
        }
        storage::atomic_write(
            &PathBuf::from(report),
            &serde_json::to_vec_pretty(&entries).map_err(|e| e.to_string())?,
        )?;
        return Ok(());
    }
    if let Some(path) = value("--licenses") {
        std::fs::write(path, theme::LICENSES).map_err(|e| e.to_string())?;
        return Ok(());
    }
    if let Some(path) = value("--save-demo") {
        storage::save(&PathBuf::from(path), &demo_document(objects))?;
        return Ok(());
    }
    if let Some(path) = value("--roundtrip") {
        let output = value("--save-as").ok_or("--roundtrip needs --save-as.")?;
        let doc = storage::load(&PathBuf::from(path))?;
        storage::save(&PathBuf::from(output), &doc)?;
        return Ok(());
    }
    if let Some(path) = value("--export-demo") {
        renderer::export(&demo_document(objects))?
            .save(path)
            .map_err(|e| e.to_string())?;
        return Ok(());
    }
    if let Some(path) = value("--render-ui") {
        let ctx = egui::Context::default();
        ctx.style_mut(|s| s.animation_time = 0.);
        let mut app = app::CaptureApp::new(&ctx, root);
        app.doc = if has("--reference-ui") {
            reference_document()
        } else {
            demo_document(objects)
        };
        app.show_caption = !has("--no-caption");
        if let Some(path) = value("--open") {
            app.load(PathBuf::from(path));
        }
        if has("--reference-ui") {
            app.selection.insert(app.doc.forms[0].id);
        }
        if has("--light") {
            app.execute(&ctx, commands::Command::ThemeLight);
        }
        if has("--french") {
            app.execute(&ctx, commands::Command::French);
        }
        if has("--lens") {
            app.execute(&ctx, commands::Command::Lens);
        }
        let mut raster = renderer::Rasterizer::default();
        let (width, height) = if has("--reference-ui") {
            (1024, 640)
        } else {
            (1200, 800)
        };
        let mut output = image::RgbaImage::new(width, height);
        for index in 0..6 {
            let frame = ctx.run(
                egui::RawInput {
                    time: Some(index as f64 * 0.25),
                    screen_rect: Some(egui::Rect::from_min_size(
                        egui::Pos2::ZERO,
                        egui::vec2(width as f32, height as f32),
                    )),
                    ..Default::default()
                },
                |ctx| app.ui(ctx),
            );
            let shapes = ctx.tessellate(frame.shapes, 1.);
            output = raster.render(width, height, &shapes, &frame.textures_delta)?;
        }
        output.save(path).map_err(|e| e.to_string())?;
        return Ok(());
    }
    let icon = image::load_from_memory(theme::ICON)
        .map_err(|e| e.to_string())?
        .to_rgba8();
    let settings = storage::Settings::load(&root);
    let mut viewport = egui::ViewportBuilder::default()
        .with_title("Swag Capture · Rust")
        .with_inner_size([1200., 800.])
        .with_min_inner_size([1024., 512.])
        .with_decorations(false)
        .with_icon(egui::IconData {
            width: icon.width(),
            height: icon.height(),
            rgba: icon.into_raw(),
        });
    if !has("--demo") && !has("--smoke") && !has("--reference-ui") && !has("--benchmark") {
        if let Some([x, y, w, h]) = settings.window_rect {
            viewport = viewport.with_position([x, y]).with_inner_size([w, h]);
        }
        viewport = viewport.with_maximized(settings.maximized);
    }
    let options = eframe::NativeOptions {
        viewport,
        renderer: eframe::Renderer::Glow,
        vsync: true,
        multisampling: 4,
        ..Default::default()
    };
    eframe::run_native(
        "Swag Capture · Rust",
        options,
        Box::new(move |cc| {
            let mut app = app::CaptureApp::new(&cc.egui_ctx, root);
            if !has("--demo")
                && !has("--reference-ui")
                && !has("--benchmark")
                && value("--open").is_none()
            {
                app.load_recent();
            }
            if has("--reference-ui") {
                app.doc = reference_document();
                app.selection.insert(app.doc.forms[0].id);
            }
            if (has("--demo") || has("--benchmark")) && !has("--reference-ui") {
                app.doc = demo_document(objects);
            }
            if let Some(path) = value("--open") {
                app.load(PathBuf::from(path));
            }
            if has("--light") {
                app.execute(&cc.egui_ctx, commands::Command::ThemeLight);
            }
            if has("--french") {
                app.execute(&cc.egui_ctx, commands::Command::French);
            }
            if has("--smoke") {
                app.smoke_frames =
                    Some(value("--frames").and_then(|n| n.parse().ok()).unwrap_or(30));
            }
            if has("--library-smoke") {
                app.library_smoke = true;
                app.execute(&cc.egui_ctx, commands::Command::Library);
            }
            if has("--capture-smoke") {
                app.capture_smoke = true;
                app.settings.capture_to_clipboard = false;
                app.settings.capture_to_editor = true;
                app.settings.hide_before_capture = true;
                app.settings.capture_delay = 0;
            }
            if has("--benchmark") {
                app.benchmark_frames = Some(
                    value("--frames")
                        .and_then(|n| n.parse().ok())
                        .unwrap_or(600),
                );
            }
            app.report = value("--report").map(PathBuf::from);
            app.screenshot = value("--screenshot").map(PathBuf::from);
            Ok(Box::new(app))
        }),
    )
    .map_err(|e| e.to_string())
}
