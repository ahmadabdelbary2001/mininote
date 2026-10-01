use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Note {
    pub id: Option<i64>,
    pub title: String,
    pub content: String,
    pub created_at: String,
    pub updated_at: String,
}

#[derive(Debug, Clone)]
pub struct CreateNoteDto {
    pub title: String,
    pub content: String,
}

#[derive(Debug, Clone)]
pub struct UpdateNoteDto {
    pub id: i64,
    pub title: String,
    pub content: String,
}
