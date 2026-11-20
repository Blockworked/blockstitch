use cxx_qt_build::{CxxQtBuilder, QmlFile, QmlModule};
use serde_json::Value;
use std::collections::BTreeSet;
use std::path::PathBuf;

// qml/module.json is the one list of the module's files; cmake/BlockstitchQml.cmake reads it too.
const MANIFEST: &str = "qml/module.json";

fn main() {
    println!("cargo:rerun-if-changed={MANIFEST}");
    let text = std::fs::read_to_string(MANIFEST).expect("cannot read qml/module.json");
    let manifest: Value = serde_json::from_str(&text).expect("qml/module.json is not valid JSON");
    let strings = |key: &str| -> Vec<String> {
        manifest[key]
            .as_array()
            .unwrap_or_else(|| panic!("qml/module.json: `{key}` must be a list"))
            .iter()
            .map(|v| {
                v.as_str()
                    .expect("qml/module.json: lists hold strings")
                    .to_owned()
            })
            .collect()
    };
    let field = |key: &str| {
        manifest[key]
            .as_str()
            .unwrap_or_else(|| panic!("qml/module.json: `{key}` missing"))
            .to_owned()
    };

    let dir = format!("qml/{}", field("dir"));
    println!("cargo:rerun-if-changed={dir}");
    let files = strings("files");
    let singletons = strings("singletons");
    check_listing(&dir, &files, &singletons);

    let (major, minor) = field("version")
        .split_once('.')
        .and_then(|(a, b)| Some((a.parse().ok()?, b.parse().ok()?)))
        .expect("qml/module.json: `version` must be MAJOR.MINOR");
    let module = files.iter().fold(
        QmlModule::new(field("uri").as_str()).version(major, minor),
        |module, name| {
            module.qml_file(
                QmlFile::from(format!("{dir}/{name}")).singleton(singletons.contains(name)),
            )
        },
    );
    strings("qt_modules")
        .iter()
        .fold(CxxQtBuilder::new_qml_module(module), |builder, qt| {
            builder.qt_module(qt)
        })
        .qrc(folder_qmldir(&field("uri"), &dir, &singletons))
        .build();
}

/// A qmldir for the folder the files sit in inside the module. A file's own
/// folder is imported before the module, and without a qmldir there every
/// file is a plain type: where Qt resolves a name at run time instead of in
/// the compiled code (Qt 6.12 does for `Motion`), a singleton then comes
/// back as a type with no properties. The .qrc gets its own name because
/// rcc names its init function after the file, and a host's resources_0.qrc
/// would otherwise replace this one at link time.
fn folder_qmldir(uri: &str, dir: &str, singletons: &[String]) -> PathBuf {
    let out = PathBuf::from(std::env::var("OUT_DIR").unwrap()).join("folder_qmldir");
    std::fs::create_dir_all(&out).expect("cannot create the folder qmldir directory");
    let text: String = singletons
        .iter()
        .map(|name| format!("singleton {} 1.0 {name}\n", name.trim_end_matches(".qml")))
        .collect();
    std::fs::write(out.join("qmldir"), text).expect("cannot write the folder qmldir");
    let prefix = format!("/qt/qml/{}/{dir}", uri.replace('.', "/"));
    let qrc = out.join("blockstitch_folder_qmldir.qrc");
    std::fs::write(
        &qrc,
        format!("<RCC>\n  <qresource prefix=\"{prefix}\">\n    <file>qmldir</file>\n  </qresource>\n</RCC>\n"),
    )
    .expect("cannot write the folder qmldir .qrc");
    qrc
}

/// Every .qml file in the directory is listed, and every listed file exists.
fn check_listing(dir: &str, files: &[String], singletons: &[String]) {
    let listed: BTreeSet<&str> = files.iter().map(String::as_str).collect();
    let on_disk: BTreeSet<String> = std::fs::read_dir(dir)
        .unwrap_or_else(|e| panic!("cannot read {dir}: {e}"))
        .flatten()
        .filter_map(|e| e.file_name().into_string().ok())
        .filter(|name| name.ends_with(".qml"))
        .collect();
    let unlisted: Vec<_> = on_disk
        .iter()
        .filter(|n| !listed.contains(n.as_str()))
        .collect();
    let missing: Vec<_> = listed.iter().filter(|n| !on_disk.contains(**n)).collect();
    let stray: Vec<_> = singletons
        .iter()
        .filter(|n| !listed.contains(n.as_str()))
        .collect();
    if !unlisted.is_empty()
        || !missing.is_empty()
        || !stray.is_empty()
        || listed.len() != files.len()
    {
        panic!(
            "qml/module.json is out of step with {dir}: not listed {unlisted:?}, missing {missing:?}, \
             singletons not in files {stray:?}, duplicates {}",
            files.len() - listed.len()
        );
    }
}
