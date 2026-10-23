/* C ABI over blockstitch-core (crates/blockstitch-ffi, ABI version 2). A host
 * crate's static library exports these through `export_abi!`, so the
 * commands are that host's. Strings are UTF-8. Inputs are borrowed for the
 * call; every returned string must be passed back to bs_string_free. One
 * thread per session. */
#ifndef BLOCKSTITCH_FFI_H
#define BLOCKSTITCH_FFI_H
#include <stdint.h>
#ifdef __cplusplus
extern "C" {
#endif
uint32_t bs_abi_version(void);
uint32_t bs_session_new(void);
void bs_session_free(uint32_t session);
/* {"command": name, "args": {...}} -> {"ok": bool, "result": ..., "error": str|null} */
char *bs_dispatch(uint32_t session, const char *command);
void bs_string_free(char *text);
#ifdef __cplusplus
}
#endif
#endif
