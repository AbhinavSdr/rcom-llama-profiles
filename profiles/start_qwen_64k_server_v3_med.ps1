# ==============================================================================
# 0. Instance Cleanup (Prevents Port 8080 & VRAM Collisions)
# ==============================================================================
Get-Process -Name "llama-server" -ErrorAction SilentlyContinue | Stop-Process -Force

# ==============================================================================
# 1. Environment & Runtime Paths
# ==============================================================================
$env:PATH = "C:\Program Files\AMD\ROCm\7.2\bin;C:\LLM\llama.cpp\build\bin;$env:PATH"
$env:ROCR_VISIBLE_DEVICES = "0"
$env:GPU_MAX_HW_QUEUES = "2"
$env:DEBUG_HIP_FORCE_ASYNC_QUEUE = "1"
$env:DEBUG_HIP_FORCE_GRAPH_QUEUES = "1"

# 256 MiB host streaming chunks keep system RAM lean
$env:LLAMA_KV_STREAM_RERESIDE = "1"
$env:LLAMA_KV_STREAM_POOL_CHUNK_MIB = "256"

# Medium reasoning effort for coding, debugging & architecture analysis
$env:LLAMA_ARG_CHAT_TEMPLATE_KWARGS = '{"reasoning_effort":"medium"}'

# ==============================================================================
# 2. File & Executable Paths
# ==============================================================================
$SERVER_BIN   = "C:\LLM\llama.cpp\build\bin\llama-server.exe"
$MODEL_PATH   = "C:\LLM\models\Qwen3.8-27B-ASCII-Condensed-UD-IQ4_XS.gguf"
$TEMPLATE_DIR = "C:\LLM\models\chat_template.jinja"

# ==============================================================================
# 3. Path Pre-flight Validation
# ==============================================================================
if (-not (Test-Path $SERVER_BIN)) { Write-Error "Missing: $SERVER_BIN"; exit 1 }
if (-not (Test-Path $MODEL_PATH)) { Write-Error "Missing: $MODEL_PATH"; exit 1 }
if (-not (Test-Path $TEMPLATE_DIR)) { Write-Error "Missing: $TEMPLATE_DIR"; exit 1 }

# ==============================================================================
# 4. Quality-Preserving 64k Context + Medium Reasoning Arguments
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
    "--load-mode", "none",

    # Cap hybrid DeltaNet checkpoints (prevents 32 default checkpoints from bloating RAM)
    "-ctxcp", "4",

    # Asymmetric KV Cache:
    # 8-bit Keys (q8_0) preserve exact syntax, variable & brace attention across 64k
    # 4-bit Values (q4_0) halve PCIe 3.0 transfer size without degrading code accuracy
    "-ctk", "q8_0",
    "-ctv", "q4_0",
    "-ctkd", "q8_0",
    "-ctvd", "q4_0",

    # Stay under the 15.2 GB Windows WDDM VRAM ceiling (~34k tokens in GDDR6 VRAM)
    "--kv-stream",
    "--kv-resident-mib", "850",
    "--kv-resident-mib-decode", "850",

    # Lossless Confidence-Gated MTP + N-Gram Speculative Decoding
    "--spec-type", "draft-mtp,ngram-mod",
    "--spec-draft-p-min", "0.60",
    "--spec-ngram-mod-n-max", "16",
    "--spec-ngram-mod-n-min", "12",
    "--spec-ngram-mod-n-match", "24",
    "--spec-draft-sampling", "probabilistic",
    "--no-context-shift",

    # Templating & Thinking (preserves reasoning blocks across turns for debugging continuity)
    "--jinja",
    "--chat-template-file", $TEMPLATE_DIR,
    "--reasoning-format", "deepseek",

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
Write-Host "Starting Qwen 3.8 27B [64k Full-Precision Keys | Medium Reasoning] on ROCm0 (127.0.0.1:8080)..." -ForegroundColor Green
& $SERVER_BIN @serverArgs