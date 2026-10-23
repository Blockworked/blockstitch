//! C ABI over blockstitch-core for hosts that can't link Rust directly (Qt
//! for WebAssembly). A host crate implements [`Host`] for its document type
//! and expands [`export_abi!`] once; that gives a static library with the
//! five `bs_*` functions in `include/blockstitch_ffi.h`.
//!
//! Ownership: input strings are borrowed for the call only; output strings
//! are allocated here and must go back through `bs_string_free`.
//! Not thread-safe: a session must be used from one thread at a time.

use std::ffi::{CStr, CString, c_char};
use std::ops::DerefMut;

use blockstitch_core::editor::{EditCommand, EditContext, EditError, EditOutcome, History};
use blockstitch_core::graph::{BlockGraph, BlockKind};
use serde::Deserialize;
use serde::de::DeserializeOwned;
use serde_json::{Value as Json, json};

/// Bumped whenever a signature or the envelope shape changes. Version 2
/// hands the session to a host vocabulary instead of a fixed stand-in.
pub const ABI_VERSION: u32 = 2;

/// One document behind a session handle. `dispatch` gets the command name
/// and its `args` object and answers the `result` of the envelope.
pub trait Host: Default {
    fn dispatch(&mut self, command: &str, args: &Json) -> Result<Json, String>;
}

/// `{"command": name, "args": {...}}`, the line a host sends.
#[derive(Deserialize)]
pub struct Command {
    pub command: String,
    #[serde(default)]
    pub args: Json,
}

/// Reads `args[key]`; a missing key reads as `null`, so `Option` fields work.
pub fn arg<T: DeserializeOwned>(args: &Json, key: &str) -> Result<T, String> {
    serde_json::from_value(args.get(key).cloned().unwrap_or(Json::Null))
        .map_err(|e| format!("bad `{key}`: {e}"))
}

/// Runs one typed edit with the contract's host steps: prepare (read only),
/// checkpoint only a changing edit, commit. `snapshot` is the host's own
/// undo scope (the document around the graph), taken before the commit.
pub fn run_edit<K: BlockKind, D: DerefMut<Target = BlockGraph<K>>, S>(
    doc: &mut D,
    history: &mut History<S>,
    snapshot: impl FnOnce(&D) -> S,
    command: EditCommand<K>,
    ctx: &EditContext,
) -> Result<EditOutcome, EditError> {
    let prepared = doc.prepare_edit(command, ctx)?;
    if prepared.changes() {
        history.checkpoint(snapshot(doc), prepared.coalesce().cloned());
    }
    Ok(doc.commit_edit(prepared))
}

/// The `{"ok", "result", "error"}` envelope as an owned C string.
pub fn respond(result: Result<Json, String>) -> *mut c_char {
    let body = match result {
        Ok(result) => json!({ "ok": true, "result": result, "error": null }),
        Err(error) => json!({ "ok": false, "result": null, "error": error }),
    };
    CString::new(body.to_string()).unwrap_or_default().into_raw()
}

/// Parses a command line and runs it on `host`. A panic becomes an error
/// where unwinding exists; a `panic = "abort"` build (the web) stops instead.
///
/// # Safety
/// `command` must be null or a valid NUL-terminated string.
pub unsafe fn dispatch_raw<H: Host>(host: Option<&mut H>, command: *const c_char) -> *mut c_char {
    if command.is_null() {
        return respond(Err("null command".into()));
    }
    let text = unsafe { CStr::from_ptr(command) }.to_string_lossy();
    let parsed: Command = match serde_json::from_str(&text) {
        Ok(c) => c,
        Err(e) => return respond(Err(format!("bad command: {e}"))),
    };
    let Some(host) = host else {
        return respond(Err("no such session".into()));
    };
    let answer = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
        host.dispatch(&parsed.command, &parsed.args)
    }));
    respond(answer.unwrap_or_else(|_| Err("the core panicked".into())))
}

/// # Safety
/// `text` must come from [`respond`] and not have been freed.
pub unsafe fn free_raw(text: *mut c_char) {
    if !text.is_null() {
        drop(unsafe { CString::from_raw(text) });
    }
}

/// Emits `bs_abi_version`, `bs_session_new`, `bs_session_free`,
/// `bs_dispatch` and `bs_string_free` over sessions of `$host`. Expand it
/// once per linked library.
#[macro_export]
macro_rules! export_abi {
    ($host:ty) => {
        ::std::thread_local! {
            static __BS_FFI_SESSIONS: ::core::cell::RefCell<::std::collections::HashMap<u32, $host>> =
                ::core::cell::RefCell::new(::std::collections::HashMap::new());
            static __BS_FFI_NEXT: ::core::cell::Cell<u32> = const { ::core::cell::Cell::new(1) };
        }

        #[unsafe(no_mangle)]
        pub extern "C" fn bs_abi_version() -> u32 {
            $crate::ABI_VERSION
        }

        /// Opens a session on a fresh host document. Never returns 0.
        #[unsafe(no_mangle)]
        pub extern "C" fn bs_session_new() -> u32 {
            let handle = __BS_FFI_NEXT.with(|n| {
                let h = n.get();
                n.set(h.wrapping_add(1).max(1));
                h
            });
            let host = <$host as ::core::default::Default>::default();
            __BS_FFI_SESSIONS.with(|s| s.borrow_mut().insert(handle, host));
            handle
        }

        #[unsafe(no_mangle)]
        pub extern "C" fn bs_session_free(handle: u32) {
            __BS_FFI_SESSIONS.with(|s| s.borrow_mut().remove(&handle));
        }

        /// # Safety
        /// `command` must be null or a valid NUL-terminated string.
        #[unsafe(no_mangle)]
        pub unsafe extern "C" fn bs_dispatch(handle: u32, command: *const ::core::ffi::c_char) -> *mut ::core::ffi::c_char {
            __BS_FFI_SESSIONS.with(|s| {
                let mut sessions = s.borrow_mut();
                unsafe { $crate::dispatch_raw(sessions.get_mut(&handle), command) }
            })
        }

        /// # Safety
        /// `text` must come from `bs_dispatch` and not have been freed.
        #[unsafe(no_mangle)]
        pub unsafe extern "C" fn bs_string_free(text: *mut ::core::ffi::c_char) {
            unsafe { $crate::free_raw(text) }
        }
    };
}
