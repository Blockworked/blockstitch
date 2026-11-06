# Blockstitch: the shared block editor (Rust core in crates/, QML in qml/).

default: test

# Core and FFI tests (no Qt needed).
test-core:
    cd crates/blockstitch-core && cargo test
    cd crates/blockstitch-ffi && cargo test

# QML tests; needs Qt 6's qmltestrunner on PATH.
test-qml:
    tests/qml/run.sh

test: test-core test-qml

# The QML crate (needs Qt 6.10 and qmake6, or QMAKE set).
build:
    cargo build
