use serde::{Deserialize, Serialize};
use serde_json::{json, Value};
use std::time::Duration;

const DEFAULT_URL: &str = "http://127.0.0.1:8788/mcp";
const DEFAULT_HTTP_TIMEOUT_SECS: u64 = 35;
const PROTOCOL_VERSION: &str = "2025-03-26";

#[derive(Debug, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Defaults {
    pub url: String,
    pub bearer: String,
}

#[derive(Debug, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct McpTool {
    pub name: String,
    #[serde(default)]
    pub description: String,
    #[serde(default, rename = "inputSchema")]
    pub input_schema: Value,
}

#[derive(Debug, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ConnectResult {
    pub server_info: Value,
    pub tools: Vec<McpTool>,
    pub initialize: Value,
}

#[derive(Debug, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct CallResult {
    pub rpc: Value,
    pub payload: Value,
    pub is_error: bool,
    pub elapsed_ms: u64,
}

#[tauri::command]
fn get_defaults() -> Defaults {
    Defaults {
        url: std::env::var("MAILGENT_MCP_URL").unwrap_or_else(|_| DEFAULT_URL.to_string()),
        bearer: std::env::var("MAILGENT_BEARER").unwrap_or_default(),
    }
}

#[tauri::command]
async fn mcp_connect(url: String, bearer: Option<String>) -> Result<ConnectResult, String> {
    let client = http_client(DEFAULT_HTTP_TIMEOUT_SECS)?;
    let init = rpc_post(
        &client,
        &url,
        bearer.as_deref(),
        "initialize",
        json!({
            "protocolVersion": PROTOCOL_VERSION,
            "capabilities": {},
            "clientInfo": { "name": "mailgent-mcp-tester", "version": "0.1.0" }
        }),
        1,
    )
    .await?;

    if init.get("error").is_some() {
        return Err(format!("initialize failed: {init}"));
    }

    // Best-effort notification (MailGent returns 202; fake may ignore).
    let _ = notify_initialized(&client, &url, bearer.as_deref()).await;

    let listed = rpc_post(
        &client,
        &url,
        bearer.as_deref(),
        "tools/list",
        json!({}),
        2,
    )
    .await?;

    if let Some(err) = listed.get("error") {
        return Err(format!("tools/list failed: {err}"));
    }

    let tools = listed
        .pointer("/result/tools")
        .and_then(|v| serde_json::from_value::<Vec<McpTool>>(v.clone()).ok())
        .unwrap_or_default();

    let server_info = init
        .pointer("/result/serverInfo")
        .cloned()
        .unwrap_or(Value::Null);

    Ok(ConnectResult {
        server_info,
        tools,
        initialize: init,
    })
}

#[tauri::command]
async fn mcp_call(
    url: String,
    bearer: Option<String>,
    name: String,
    arguments: Value,
    timeout_secs: Option<u64>,
) -> Result<CallResult, String> {
    let soft = arguments
        .get("timeout")
        .and_then(|v| v.as_u64().or_else(|| v.as_f64().map(|f| f as u64)))
        .unwrap_or(0);
    let http_timeout = timeout_secs
        .unwrap_or(DEFAULT_HTTP_TIMEOUT_SECS)
        .max(soft.saturating_add(10))
        .max(DEFAULT_HTTP_TIMEOUT_SECS);

    let client = http_client(http_timeout)?;
    let started = std::time::Instant::now();
    let rpc = rpc_post(
        &client,
        &url,
        bearer.as_deref(),
        "tools/call",
        json!({ "name": name, "arguments": arguments }),
        uuid::Uuid::new_v4().as_u128() as u64,
    )
    .await?;
    let elapsed_ms = started.elapsed().as_millis() as u64;
    let (payload, is_error) = tool_text_payload(&rpc);
    Ok(CallResult {
        rpc,
        payload,
        is_error,
        elapsed_ms,
    })
}

fn http_client(timeout_secs: u64) -> Result<reqwest::Client, String> {
    reqwest::Client::builder()
        .timeout(Duration::from_secs(timeout_secs))
        .build()
        .map_err(|e| e.to_string())
}

async fn rpc_post(
    client: &reqwest::Client,
    url: &str,
    bearer: Option<&str>,
    method: &str,
    params: Value,
    req_id: u64,
) -> Result<Value, String> {
    let body = json!({
        "jsonrpc": "2.0",
        "id": req_id,
        "method": method,
        "params": params,
    });

    let mut req = client
        .post(url)
        .header("Content-Type", "application/json")
        .header("Accept", "application/json, text/event-stream")
        .json(&body);

    if let Some(token) = bearer.filter(|t| !t.is_empty()) {
        req = req.bearer_auth(token);
    }

    let response = req.send().await.map_err(|e| e.to_string())?;
    let status = response.status();
    let text = response.text().await.map_err(|e| e.to_string())?;

    if !status.is_success() {
        return Err(format!("HTTP {status}: {text}"));
    }
    if text.trim().is_empty() {
        return Ok(Value::Null);
    }
    serde_json::from_str(&text).map_err(|e| format!("bad JSON ({e}): {text}"))
}

async fn notify_initialized(
    client: &reqwest::Client,
    url: &str,
    bearer: Option<&str>,
) -> Result<(), String> {
    let body = json!({
        "jsonrpc": "2.0",
        "method": "notifications/initialized",
        "params": {}
    });
    let mut req = client
        .post(url)
        .header("Content-Type", "application/json")
        .json(&body);
    if let Some(token) = bearer.filter(|t| !t.is_empty()) {
        req = req.bearer_auth(token);
    }
    let _ = req.send().await.map_err(|e| e.to_string())?;
    Ok(())
}

/// Decode MCP tools/call result content[0].text JSON (same as harness.py tool_text_payload).
fn tool_text_payload(rpc: &Value) -> (Value, bool) {
    if let Some(err) = rpc.get("error") {
        return (err.clone(), true);
    }
    let result = rpc.get("result").cloned().unwrap_or(Value::Null);
    let is_error = result
        .get("isError")
        .and_then(|v| v.as_bool())
        .unwrap_or(false);
    let content = result
        .get("content")
        .and_then(|c| c.as_array())
        .cloned()
        .unwrap_or_default();
    let text = content
        .first()
        .and_then(|c| c.get("text"))
        .and_then(|t| t.as_str())
        .unwrap_or("");

    if text.is_empty() {
        return (result, is_error);
    }

    match serde_json::from_str::<Value>(text) {
        Ok(parsed) => (parsed, is_error),
        Err(_) if is_error || text.starts_with('{') => {
            if is_error {
                (json!({ "error": text, "isError": true }), true)
            } else {
                (json!({ "text": text }), false)
            }
        }
        Err(_) => (json!({ "text": text }), is_error),
    }
}

/// Persist a session export under Scripts/mcp-tester/exports/ for agent verification.
/// Always writes `last-session.json`. When `stamp_name` is set (e.g. `session-2026….json`),
/// also writes that sibling file and returns its path.
#[tauri::command]
fn save_session_export(json: String, stamp_name: Option<String>) -> Result<String, String> {
    let dir = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../exports");
    std::fs::create_dir_all(&dir).map_err(|e| format!("create exports dir: {e}"))?;

    let latest = dir.join("last-session.json");
    std::fs::write(&latest, json.as_bytes()).map_err(|e| format!("write last-session.json: {e}"))?;

    if let Some(name) = stamp_name.filter(|n| !n.is_empty()) {
        let safe = name
            .chars()
            .map(|c| {
                if c.is_ascii_alphanumeric() || c == '-' || c == '_' || c == '.' {
                    c
                } else {
                    '-'
                }
            })
            .collect::<String>();
        let stamped = dir.join(&safe);
        std::fs::write(&stamped, json.as_bytes()).map_err(|e| format!("write {safe}: {e}"))?;
        return Ok(stamped
            .canonicalize()
            .unwrap_or(stamped)
            .display()
            .to_string());
    }

    Ok(latest
        .canonicalize()
        .unwrap_or(latest)
        .display()
        .to_string())
}

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tauri::Builder::default()
        .plugin(tauri_plugin_opener::init())
        .invoke_handler(tauri::generate_handler![
            get_defaults,
            mcp_connect,
            mcp_call,
            save_session_export
        ])
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn decodes_tool_text_json() {
        let rpc = json!({
            "jsonrpc": "2.0",
            "id": 1,
            "result": {
                "content": [{ "type": "text", "text": "{\"status\":\"ok\",\"askId\":\"a1\"}" }]
            }
        });
        let (payload, is_error) = tool_text_payload(&rpc);
        assert!(!is_error);
        assert_eq!(payload["status"], "ok");
        assert_eq!(payload["askId"], "a1");
    }

    #[test]
    fn decodes_is_error_text() {
        let rpc = json!({
            "result": {
                "isError": true,
                "content": [{ "type": "text", "text": "boom" }]
            }
        });
        let (payload, is_error) = tool_text_payload(&rpc);
        assert!(is_error);
        assert_eq!(payload["error"], "boom");
    }
}
