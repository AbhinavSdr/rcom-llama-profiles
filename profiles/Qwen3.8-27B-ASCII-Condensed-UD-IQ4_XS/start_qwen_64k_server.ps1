# ==============================================================================
# 0. Process Cleanup
# ==============================================================================
# Gracefully terminate existing instances to avoid port 8080 and VRAM collisions
Get-Process -Name "llama-server" -ErrorAction SilentlyContinue | Stop-Process -Force

# ==============================================================================
# 1. Environment & Runtime Paths
# ==============================================================================
$env:PATH = "C:\Program Files\AMD\ROCm\7.2\bin;C:\LLM\llama-kvstream\build\bin;$env:PATH"
$env:ROCR_VISIBLE_DEVICES = "0"
$env:GPU_MAX_HW_QUEUES = "2"
$env:DEBUG_HIP_FORCE_ASYNC_QUEUE = "1"
$env:DEBUG_HIP_FORCE_GRAPH_QUEUES = "1"

# Windows Streaming Buffer Handling
$env:LLAMA_KV_STREAM_RERESIDE = "1"
$env:LLAMA_KV_STREAM_POOL_CHUNK_MIB = "512"

# Balanced Reasoning: Keeps answers direct and fast while retaining logic checks
$env:LLAMA_ARG_CHAT_TEMPLATE_KWARGS = '{"reasoning_effort":"low"}'

# ==============================================================================
# 2. File & Executable Paths
# ==============================================================================
$SERVER_BIN   = "C:\LLM\llama-kvstream\build\bin\llama-server.exe"
$MODEL_PATH   = "C:\LLM\models\Qwen3.8-27B-ASCII-Condensed-UD-IQ4_XS.gguf"
$TEMPLATE_DIR = "C:\LLM\models\chat_template.jinja"

# ==============================================================================
# 3. Path Pre-flight Validation
# ==============================================================================
if (-not (Test-Path $SERVER_BIN)) {
    Write-Error "llama-server executable not found at: $SERVER_BIN"
    exit 1
}
if (-not (Test-Path $MODEL_PATH)) {
    Write-Error "Model file not found at: $MODEL_PATH"
    exit 1
}
if (-not (Test-Path $TEMPLATE_DIR)) {
    Write-Error "Chat template not found at: $TEMPLATE_DIR"
    exit 1
}

# ==============================================================================
# 4. Balanced 64k Server Arguments
# ==============================================================================
$serverArgs = @(
    "-m", $MODEL_PATH,
    "--alias", "qwen3.8-27b-64k",
    "--host", "127.0.0.1",
    "--port", "8080",
    "-c", "65536",
    "-np", "1",
    "-dev", "ROCm0",
    "-fa", "on",
    "-fit", "off",

    # Balanced KV Precision:
    # 8-bit Keys protect attention accuracy across long context (preventing document hallucination)
    # 4-bit Values cut bus transmission volume and RAM usage in half without loss
    "-ctk", "q8_0",
    "-ctv", "q4_0",
    "-ctkd", "q8_0",
    "-ctvd", "q4_0",

    # Streaming & Memory Paging
    "--kv-stream",
    "--kv-resident-mib", "450",
    "--kv-resident-mib-decode", "1600",

    # Speculative Decoding: Clean MTP without RAM hash-table bloat
    "--spec-type", "draft-mtp",
    "--spec-draft-sampling", "probabilistic",
    "--no-context-shift",

    # Templating & Thinking Engine
    "--jinja",
    "--chat-template-file", $TEMPLATE_DIR,
    "--reasoning-format", "deepseek",

    # Prefill Throughput
    "-b", "2048",
    "-ub", "512"
)

# ==============================================================================
# 5. Launch Engine
# ==============================================================================
Write-Host "Starting Balanced 64k Qwen 3.8 27B on ROCm0 (127.0.0.1:8080)..." -ForegroundColor Cyan
& $SERVER_BIN @serverArgs