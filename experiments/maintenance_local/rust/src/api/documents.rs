use anyhow::{anyhow, Result};
use automerge::{sync::{Message, State, SyncDoc}, transaction::Transactable,
    ActorId, AutoCommit, ReadDoc, ScalarValue, Value, ROOT};
use serde_json::{json, Map, Value as Json};

fn read(bytes: &[u8]) -> Result<AutoCommit> {
    if bytes.len() > 16 * 1024 * 1024 { return Err(anyhow!("Document exceeds lab limit")); }
    Ok(AutoCommit::load(bytes)?)
}

pub fn create_document(actor: String, fields_json: String) -> Result<Vec<u8>> {
    let mut doc = AutoCommit::new();
    doc.set_actor(ActorId::from(actor.as_bytes()));
    put(&mut doc, &fields_json)?;
    Ok(doc.save())
}

fn put(doc: &mut AutoCommit, fields: &str) -> Result<()> {
    let parsed: Map<String, Json> = serde_json::from_str(fields)?;
    for (key, value) in parsed {
        // Automerge may optimize a put of the winning conflicted value into
        // deleting only the losers. A concurrent update can then replace that
        // old winning op and silently discard the user's new choice. Record an
        // explicit fresh assignment, within this same uncommitted transaction.
        if doc.get_all(ROOT, &key)?.len() > 1 {
            doc.delete(ROOT, &key)?;
        }
        doc.put(ROOT, key, serde_json::to_string(&value)?)?;
    }
    doc.commit();
    Ok(())
}

pub fn edit_document(bytes: Vec<u8>, actor: String, fields_json: String) -> Result<Vec<u8>> {
    let mut doc = read(&bytes)?;
    doc.set_actor(ActorId::from(actor.as_bytes()));
    put(&mut doc, &fields_json)?;
    Ok(doc.save())
}

pub fn merge_documents(left: Vec<u8>, right: Vec<u8>) -> Result<Vec<u8>> {
    let mut a = read(&left)?;
    let mut b = read(&right)?;
    a.merge(&mut b)?;
    Ok(a.save())
}

pub fn document_values(bytes: Vec<u8>) -> Result<String> {
    let doc = read(&bytes)?;
    let mut fields = Map::new();
    for key in doc.keys(ROOT) {
        let mut values = Vec::new();
        for (value, _) in doc.get_all(ROOT, &key)? {
            match value {
                Value::Scalar(s) => match s.as_ref() {
                    ScalarValue::Str(v) => values.push(serde_json::from_str::<Json>(v)?),
                    _ => return Err(anyhow!("Unexpected field type")),
                },
                _ => return Err(anyhow!("Unexpected object field")),
            }
        }
        values.sort_by_key(|v| v.to_string());
        values.dedup();
        fields.insert(key, json!(values));
    }
    Ok(serde_json::to_string(&fields)?)
}

pub struct SyncPacket {
    pub document: Vec<u8>,
    pub message: Option<Vec<u8>>,
}

// In-flight sync state is session state. State::encode only stores shared heads;
// using it between individual messages would lose protocol acknowledgements.
#[flutter_rust_bridge::frb(opaque)]
pub struct DocumentSession { state: State }

pub fn new_session() -> DocumentSession { DocumentSession { state: State::new() } }

impl DocumentSession {
    pub fn step(&mut self, bytes: Vec<u8>, incoming: Option<Vec<u8>>) -> Result<SyncPacket> {
        let mut doc = read(&bytes)?;
        if let Some(message) = incoming {
            if message.len() > 16 * 1024 * 1024 { return Err(anyhow!("Sync frame exceeds lab limit")); }
            doc.sync().receive_sync_message(&mut self.state, Message::decode(&message)?)?;
        }
        let message = doc.sync().generate_sync_message(&mut self.state).map(|m| m.encode());
        Ok(SyncPacket { document: doc.save(), message })
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn restart_merge_and_explicit_conflict_resolution() -> Result<()> {
        let base = create_document("seed".into(), r#"{"meter":10,"notes":""}"#.into())?;
        let a = edit_document(base.clone(), "phone".into(), r#"{"meter":12}"#.into())?;
        let b = edit_document(base, "office".into(), r#"{"meter":13,"notes":"Check belt"}"#.into())?;
        let merged = merge_documents(a.clone(), b.clone())?;
        assert_eq!(document_values(merged.clone())?, document_values(merge_documents(b,a)?)?);
        let fields: Json = serde_json::from_str(&document_values(merged.clone())?)?;
        assert_eq!(fields["meter"], json!([12,13]));
        let resolved = edit_document(merged, "office".into(), r#"{"meter":13}"#.into())?;
        let fields: Json = serde_json::from_str(&document_values(resolved)?)?;
        assert_eq!(fields["meter"], json!([13]));
        Ok(())
    }

    #[test]
    fn native_protocol_converges_after_independent_changes() -> Result<()> {
        let base = create_document("seed".into(), "{}".into())?;
        let mut a = edit_document(base.clone(), "a".into(), r#"{"a":true}"#.into())?;
        let mut b = edit_document(base, "b".into(), r#"{"b":true}"#.into())?;
        let (mut sa, mut sb, mut incoming) = (new_session(),new_session(),None);
        for _ in 0..12 {
            let p = sa.step(a, incoming)?; a=p.document;
            let q = sb.step(b, p.message)?; b=q.document; incoming=q.message;
        }
        assert_eq!(document_values(a)?, document_values(b)?);
        Ok(())
    }

    #[test]
    fn malformed_persistence_fails_without_empty_fallback() {
        assert!(document_values(vec![1,2,3]).is_err());
    }

    #[test]
    fn older_conflict_choice_remains_concurrent_with_a_later_edit() -> Result<()> {
        let base = create_document("seed".into(), r#"{"notes":"initial"}"#.into())?;
        let a = edit_document(base.clone(), "a".into(), r#"{"notes":"left"}"#.into())?;
        let b = edit_document(base, "b".into(), r#"{"notes":"right"}"#.into())?;
        let shown = merge_documents(a, b)?;
        let later = edit_document(shown.clone(), "later".into(), r#"{"notes":"new arrival"}"#.into())?;
        for choice in ["left", "right"] {
            let selected = edit_document(shown.clone(), "resolver".into(), json!({"notes":choice}).to_string())?;
            let merged = merge_documents(later.clone(), selected)?;
            let values: Json = serde_json::from_str(&document_values(merged)?)?;
            let notes = values["notes"].as_array().unwrap();
            assert_eq!(notes.len(), 2);
            assert!(notes.contains(&json!(choice)));
            assert!(notes.contains(&json!("new arrival")));
        }
        Ok(())
    }
}
