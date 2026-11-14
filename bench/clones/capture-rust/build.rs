use std::{env, fs, path::PathBuf, process::Command};

fn main() {
    println!("cargo:rerun-if-changed=Cargo.lock");
    println!("cargo:rerun-if-changed=../../../bin/apps/modules/swagcapture/datas/appicon.ico");
    if env::var("CARGO_CFG_TARGET_OS").as_deref() != Ok("windows") {
        return;
    }
    let out = PathBuf::from(env::var_os("OUT_DIR").unwrap());
    fs::write(out.join("licenses.txt"), dependency_notices()).unwrap();
    let icon = PathBuf::from("../../../bin/apps/modules/swagcapture/datas/appicon.ico")
        .canonicalize()
        .unwrap();
    let icon = icon
        .to_string_lossy()
        .trim_start_matches(r"\\?\")
        .replace('\\', "/");
    let rc = out.join("capture.rc");
    let res = out.join("capture.res");
    fs::write(&rc, format!("1 ICON \"{icon}\"\n")).unwrap();
    let kits = PathBuf::from(
        env::var_os("ProgramFiles(x86)").unwrap_or_else(|| "C:/Program Files (x86)".into()),
    )
    .join("Windows Kits/10/bin");
    let mut compilers: Vec<_> = fs::read_dir(kits)
        .into_iter()
        .flatten()
        .flatten()
        .map(|e| e.path().join("x64/rc.exe"))
        .filter(|p| p.is_file())
        .collect();
    compilers.sort();
    let compiler = compilers.pop().unwrap_or_else(|| PathBuf::from("rc.exe"));
    let status = Command::new(compiler)
        .arg("/nologo")
        .arg("/fo")
        .arg(&res)
        .arg(&rc)
        .status()
        .expect("Windows SDK resource compiler is required");
    assert!(
        status.success(),
        "Application icon resource compilation failed"
    );
    println!("cargo:rustc-link-arg={}", res.display());
}

fn dependency_notices() -> String {
    let mut result = String::from("Swag Capture Rust — dependency notices\n\n");
    for font in ["INTER-OFL.txt", "ROBOTO-MONO-OFL.txt"] {
        let path = PathBuf::from("../../bin/std/modules/gui/src/theme").join(font);
        println!("cargo:rerun-if-changed={}", path.display());
        result.push_str(&fs::read_to_string(path).expect("Font license is required"));
        result.push_str("\n\n");
    }
    let cargo = env::var_os("CARGO_HOME")
        .map(PathBuf::from)
        .unwrap_or_else(|| {
            PathBuf::from(env::var_os("USERPROFILE").expect("Cargo home is required"))
                .join(".cargo")
        });
    let registries: Vec<_> = fs::read_dir(cargo.join("registry/src"))
        .into_iter()
        .flatten()
        .flatten()
        .map(|e| e.path())
        .collect();
    let lock = fs::read_to_string("Cargo.lock").unwrap();
    for package in lock.split("[[package]]").skip(1) {
        let attribute = |key: &str| {
            package.lines().find_map(|line| {
                line.strip_prefix(&format!("{key} = \""))
                    .and_then(|s| s.strip_suffix('"'))
            })
        };
        let (Some(name), Some(version)) = (attribute("name"), attribute("version")) else {
            continue;
        };
        let stem = format!("{name}-{version}");
        let Some(root) = registries
            .iter()
            .map(|p| p.join(&stem))
            .find(|p| p.is_dir())
        else {
            continue;
        };
        result.push_str(&format!("\n===== {stem} =====\n"));
        let mut paths: Vec<_> = fs::read_dir(&root)
            .into_iter()
            .flatten()
            .flatten()
            .map(|e| e.path())
            .filter(|p| {
                let n = p
                    .file_name()
                    .unwrap_or_default()
                    .to_string_lossy()
                    .to_uppercase();
                n.starts_with("LICENSE")
                    || n.starts_with("LICENCE")
                    || n.starts_with("COPYING")
                    || n.starts_with("NOTICE")
                    || n.starts_with("COPYRIGHT")
            })
            .collect();
        paths.sort();
        for path in paths {
            if path.is_file() {
                if let Ok(text) = fs::read_to_string(&path) {
                    result.push_str(&text);
                    result.push('\n');
                }
            } else if path.is_dir() {
                let mut files: Vec<_> = fs::read_dir(path)
                    .into_iter()
                    .flatten()
                    .flatten()
                    .map(|e| e.path())
                    .filter(|p| p.is_file())
                    .collect();
                files.sort();
                for file in files {
                    if let Ok(text) = fs::read_to_string(file) {
                        result.push_str(&text);
                        result.push('\n');
                    }
                }
            }
        }
    }
    result
}
