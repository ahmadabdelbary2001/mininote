use crate::db::NoteRepository;
use crate::note::{CreateNoteDto, Note, UpdateNoteDto};
use std::ffi::{CStr, CString};
use std::os::raw::c_char;
use std::sync::Mutex;

static REPO: Mutex<Option<NoteRepository>> = Mutex::new(None);
static LAST_ERROR: Mutex<Option<String>> = Mutex::new(None);

fn set_last_error(message: impl Into<String>) {
    let mut guard = LAST_ERROR.lock().unwrap();
    *guard = Some(message.into());
}

fn clear_last_error() {
    let mut guard = LAST_ERROR.lock().unwrap();
    *guard = None;
}

fn string_from_ptr(value: *const c_char, field_name: &str) -> Result<String, String> {
    if value.is_null() {
        return Err(format!("{field_name} pointer is null"));
    }

    let c_str = unsafe { CStr::from_ptr(value) };
    c_str
        .to_str()
        .map(|value| value.to_owned())
        .map_err(|_| format!("{field_name} is not valid UTF-8"))
}

fn into_c_string(value: String) -> *mut c_char {
    CString::new(value)
        .expect("CString::new failed because the string contains an interior null byte")
        .into_raw()
}

fn repo() -> Result<std::sync::MutexGuard<'static, Option<NoteRepository>>, String> {
    Ok(REPO
        .lock()
        .map_err(|_| "Failed to lock repository state".to_string())?)
}

pub fn init_db(db_path: String) -> Result<(), String> {
    let repo = NoteRepository::new(db_path).map_err(|e| e.to_string())?;
    let mut global_repo = repo()?;
    *global_repo = Some(repo);
    Ok(())
}

pub fn fetch_notes() -> Result<Vec<Note>, String> {
    let guard = repo()?;
    let repo = guard.as_ref().ok_or("Database not initialized")?;
    repo.get_all().map_err(|e| e.to_string())
}

pub fn add_note(title: String, content: String) -> Result<Note, String> {
    let guard = repo()?;
    let repo = guard.as_ref().ok_or("Database not initialized")?;
    repo.create(CreateNoteDto { title, content })
        .map_err(|e| e.to_string())
}

pub fn edit_note(id: i64, title: String, content: String) -> Result<(), String> {
    let guard = repo()?;
    let repo = guard.as_ref().ok_or("Database not initialized")?;
    repo.update(UpdateNoteDto { id, title, content })
        .map_err(|e| e.to_string())
}

pub fn remove_note(id: i64) -> Result<(), String> {
    let guard = repo()?;
    let repo = guard.as_ref().ok_or("Database not initialized")?;
    repo.delete(id).map_err(|e| e.to_string())
}

#[unsafe(no_mangle)]
pub extern "C" fn c_init_db(path: *const c_char) -> i32 {
    clear_last_error();

    match string_from_ptr(path, "path").and_then(init_db) {
        Ok(()) => 0,
        Err(error) => {
            set_last_error(error);
            -1
        }
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn c_fetch_notes_json() -> *mut c_char {
    clear_last_error();

    match fetch_notes().and_then(|notes| serde_json::to_string(&notes).map_err(|e| e.to_string())) {
        Ok(json) => into_c_string(json),
        Err(error) => {
            set_last_error(error);
            std::ptr::null_mut()
        }
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn c_add_note_json(title: *const c_char, content: *const c_char) -> *mut c_char {
    clear_last_error();

    let result = string_from_ptr(title, "title")
        .and_then(|title| string_from_ptr(content, "content").map(|content| (title, content)))
        .and_then(|(title, content)| add_note(title, content))
        .and_then(|note| serde_json::to_string(&note).map_err(|e| e.to_string()));

    match result {
        Ok(json) => into_c_string(json),
        Err(error) => {
            set_last_error(error);
            std::ptr::null_mut()
        }
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn c_edit_note(id: i64, title: *const c_char, content: *const c_char) -> i32 {
    clear_last_error();

    let result = string_from_ptr(title, "title")
        .and_then(|title| string_from_ptr(content, "content").map(|content| (title, content)))
        .and_then(|(title, content)| edit_note(id, title, content));

    match result {
        Ok(()) => 0,
        Err(error) => {
            set_last_error(error);
            -1
        }
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn c_remove_note(id: i64) -> i32 {
    clear_last_error();

    match remove_note(id) {
        Ok(()) => 0,
        Err(error) => {
            set_last_error(error);
            -1
        }
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn c_last_error_message() -> *mut c_char {
    let guard = LAST_ERROR.lock().unwrap();
    let message = guard.clone().unwrap_or_default();
    into_c_string(message)
}

#[unsafe(no_mangle)]
pub extern "C" fn c_free_string(value: *mut c_char) {
    if !value.is_null() {
        unsafe {
            let _ = CString::from_raw(value);
        }
    }
}
