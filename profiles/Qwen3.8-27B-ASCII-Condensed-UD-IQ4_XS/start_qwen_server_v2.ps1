# ==============================================================================
# 0. Instance Cleanup (Prevents Port 8080 & VRAM Collisions)
# ==============================================================================
Get-Process -Name "llama-server" -ErrorAction SilentlyContinue | Stop-Process -Force

# ==============================================================================
# 1. Environment & Runtime Paths
# ==============================================================================
$env:PATH = "C:\Program Files\AMD\ROCm\7.2\bin;C:\LLM\llama-kvstream\build\bin;$env:PATH"
$env:ROCR_VISIBLE_DEVICES = "0"
$env:GPU_MAX_HW_QUEUES = "2"
$env:DEBUG_HIP_FORCE_ASYNC_QUEUE = "1"
$env:DEBUG_HIP_FORCE_GRAPH_QUEUES = "1"

# Lean 256 MiB host streaming chunks
$env:LLAMA_KV_STREAM_RERESIDE = "1"
$env:LLAMA_KV_STREAM_POOL_CHUNK_MIB = "256"

# Medium reasoning effort for coding & architecture analysis
$env:LLAMA_ARG_CHAT_TEMPLATE_KWARGS = '{"reasoning_effort":"medium"}'

# ==============================================================================
# 2. File & Executable Paths
# ==============================================================================
$SERVER_BIN   = "C:\LLM\llama-kvstream\build\bin\llama-server.exe"
$MODEL_PATH   = "C:\LLM\models\Qwen3.8-27B-ASCII-Condensed-UD-IQ4_XS.gguf"
$TEMPLATE_DIR = "C:\LLM\models\chat_template.jinja"

# ==============================================================================
# 3. Path Pre-flight Validation
# ==============================================================================
if (-not (Test-Path $SERVER_BIN)) { Write-Error "Missing: $SERVER_BIN"; exit 1 }
if (-not (Test-Path $MODEL_PATH)) { Write-Error "Missing: $MODEL_PATH"; exit 1 }
if (-not (Test-Path $TEMPLATE_DIR)) { Write-Error "Missing: $TEMPLATE_DIR"; exit 1 }

# ==============================================================================
# 4. Final Memory-Safe & Quality-Tuned Server Arguments
# ==============================================================================
$serverArgs = @(
    "-m", $MODEL_PATH,
    "--alias", "qwen3.8-27b",
    "--host", "127.0.0.1",
    "--port", "8080",
    "-c", "32768",
    "-np", "1",
    "-dev", "ROCm0",
    "-fa", "on",
    "-fit", "off",
    "--load-mode", "none",

    # Cap hybrid DeltaNet checkpoints (saves ~2-3.5 GB host RAM vs default 32)
    "-ctxcp", "4",

    # Balanced KV Precision (8-bit Keys for syntax accuracy, 4-bit Values for bandwidth)
    "-ctk", "q8_0",
    "-ctv", "q4_0",
    "-ctkd", "q8_0",
    "-ctvd", "q4_0",

    # Equalized 800 MiB Resident Buffers (eliminates WDDM shared-RAM spill & graph reallocs)
    "--kv-stream",
    "--kv-resident-mib", "800",
    "--kv-resident-mib-decode", "800",

    # Pure Neural MTP Speculative Decoding
    "--spec-type", "draft-mtp",
    "--spec-draft-sampling", "probabilistic",
    "--no-context-shift",

    # Templating & Thinking Controls
    "--jinja",
    "--chat-template-file", $TEMPLATE_DIR,
    "--reasoning-format", "deepseek",
    "--no-reasoning-preserve",

    # Qwen 3.8 Coding Sampling Profile
    "--temp", "0.6",
    "--top-p", "0.95",
    "--top-k", "20",
    "--min-p", "0.0",

    # Ingestion Batching
    "-b", "2048",
    "-ub", "512"
)

# ==============================================================================
# 5. Launch Engine
# ==============================================================================
Write-Host "Starting Qwen 3.8 27B [32k Lean Profile] on ROCm0 (127.0.0.1:8080)..." -ForegroundColor Cyan
& $SERVER_BIN @serverArgs