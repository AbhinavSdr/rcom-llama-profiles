# ==============================================================================
# Flush KV Cache & Recurrent States for Active llama-server Slot
# ==============================================================================
param (
    [string]$ServerHost = "127.0.0.1",
    [int]$Port          = 8080,
    [int]$SlotId        = 0
)

$uri = "http://${ServerHost}:${Port}/slots/${SlotId}?action=erase"

try {
    $response = Invoke-RestMethod -Uri $uri -Method Post -ErrorAction Stop
    Write-Host "KV cache flushed for slot $SlotId ($uri)." -ForegroundColor Green
    if ($response) {
        $response | ConvertTo-Json -Compress | Write-Host -ForegroundColor DarkGray
    }
}
catch {
    $statusCode = $null
    if ($_.Exception.Response) {
        $statusCode = [int]$_.Exception.Response.StatusCode
    }

    if ($statusCode -eq 404 -or $statusCode -eq 501) {
        Write-Error "Slot management endpoint unavailable (HTTP $statusCode). Add '--slots' to your server arguments if disabled in your build."
    }
    else {
        Write-Error "Could not reach llama-server at $uri. Verify the server is running. ($($_.Exception.Message))"
    }
    exit 1
}