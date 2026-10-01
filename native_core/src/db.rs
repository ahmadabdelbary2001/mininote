use crate::note::{CreateNoteDto, Note, UpdateNoteDto};
use rusqlite::{Connection, Result, params};
use std::path::Path;

pub struct NoteRepository {
    conn: Connection,
}

impl NoteRepository {
    pub fn new<P: AsRef<Path>>(db_path: P) -> Result<Self> {
        let conn = Connection::open(db_path)?;
        let repo = Self { conn };
        repo.init_db()?;
        Ok(repo)
    }

    fn init_db(&self) -> Result<()> {
        self.conn.execute(
            "CREATE TABLE IF NOT EXISTS notes (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                title TEXT NOT NULL,
                content TEXT NOT NULL,
                created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
                updated_at DATETIME DEFAULT CURRENT_TIMESTAMP
            )",
            [],
        )?;
        Ok(())
    }

    pub fn get_all(&self) -> Result<Vec<Note>> {
        let mut stmt = self.conn.prepare(
            "SELECT id, title, content, created_at, updated_at FROM notes ORDER BY updated_at DESC",
        )?;
        let note_iter = stmt.query_map([], |row| {
            Ok(Note {
                id: Some(row.get(0)?),
                title: row.get(1)?,
                content: row.get(2)?,
                created_at: row.get(3)?,
                updated_at: row.get(4)?,
            })
        })?;

        let mut notes = Vec::new();
        for note in note_iter {
            notes.push(note?);
        }
        Ok(notes)
    }

    pub fn create(&self, dto: CreateNoteDto) -> Result<Note> {
        self.conn.execute(
            "INSERT INTO notes (title, content, created_at, updated_at) VALUES (?1, ?2, DATETIME('now'), DATETIME('now'))",
            params![dto.title, dto.content],
        )?;
        let id = self.conn.last_insert_rowid();

        let mut stmt = self.conn.prepare(
            "SELECT id, title, content, created_at, updated_at FROM notes WHERE id = ?1",
        )?;
        stmt.query_row(params![id], |row| {
            Ok(Note {
                id: Some(row.get(0)?),
                title: row.get(1)?,
                content: row.get(2)?,
                created_at: row.get(3)?,
                updated_at: row.get(4)?,
            })
        })
    }

    pub fn update(&self, dto: UpdateNoteDto) -> Result<()> {
        let updated = self.conn.execute(
            "UPDATE notes SET title = ?1, content = ?2, updated_at = DATETIME('now') WHERE id = ?3",
            params![dto.title, dto.content, dto.id],
        )?;
        if updated == 0 {
            return Err(rusqlite::Error::QueryReturnedNoRows);
        }
        Ok(())
    }

    pub fn delete(&self, id: i64) -> Result<()> {
        let deleted = self
            .conn
            .execute("DELETE FROM notes WHERE id = ?1", params![id])?;
        if deleted == 0 {
            return Err(rusqlite::Error::QueryReturnedNoRows);
        }
        Ok(())
    }
}
