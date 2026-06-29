***REMOVED***!/usr/bin/env bash
***REMOVED*** ─────────────────────────────────────────────────────────────
***REMOVED*** ocr — Baidu Unlimited-OCR on Lambda GPU Cloud
***REMOVED*** ─────────────────────────────────────────────────────────────
***REMOVED*** Spins up a GPU instance, deploys the Unlimited-OCR model via
***REMOVED*** vLLM Docker, sends your file (image/pdf), returns text, then
***REMOVED*** optionally tears down.
***REMOVED***
***REMOVED*** Usage:
***REMOVED***   ./ocr.sh image.png                    ***REMOVED*** OCR a single image
***REMOVED***   ./ocr.sh document.pdf                 ***REMOVED*** OCR a PDF (all pages)
***REMOVED***   ./ocr.sh image.png --keep             ***REMOVED*** keep instance running after
***REMOVED***   ./ocr.sh --status                     ***REMOVED*** check if instance is alive
***REMOVED***   ./ocr.sh --kill                       ***REMOVED*** terminate the GPU instance
***REMOVED***
***REMOVED*** Supported formats: png, jpg, jpeg, webp, bmp, tiff, pdf
***REMOVED***
***REMOVED*** Requires:
***REMOVED***   - tofu (OpenTofu) in PATH
***REMOVED***   - LAMBDA_CLOUD_API_KEY env var set
***REMOVED***   - tofu/lambda.tf configured with your SSH key
***REMOVED***   - rsync + ssh for file transfer
***REMOVED*** ─────────────────────────────────────────────────────────────
set -euo pipefail
DIR="$(cd "$(dirname "$0")/.." && pwd)"
TOFU_DIR="$DIR/tofu"

***REMOVED*** ── Config ──────────────────────────────────────────────────
OCR_SSH_USER="${OCR_SSH_USER:-ubuntu}"
OCR_MODEL_PORT="${OCR_MODEL_PORT:-10000}"
OCR_IDLE_TIMEOUT="${OCR_IDLE_TIMEOUT:-300}"  ***REMOVED*** auto-terminate after 5min idle
VIRTUALENV_DIR="$DIR/.ocr-venv"

***REMOVED*** ── Colors ──────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; NC='\033[0m'
info()  { echo -e "${BLUE}[INFO]${NC}  $*"; }
ok()    { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
err()   { echo -e "${RED}[ERR]${NC}   $*"; }

***REMOVED*** ── Helpers ─────────────────────────────────────────────────
tofu_output() {
  cd "$TOFU_DIR"
  tofu output -raw "$1" 2>/dev/null || echo ""
}

get_instance_ip() {
  tofu_output ocr_instance_ip
}

is_instance_running() {
  local ip; ip=$(get_instance_ip)
  [[ -n "$ip" ]] && ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no \
    "$OCR_SSH_USER@$ip" "echo alive" 2>/dev/null | grep -q alive
}

is_model_serving() {
  local ip; ip=$(get_instance_ip)
  [[ -n "$ip" ]] && curl -sf "http://$ip:$OCR_MODEL_PORT/v1/models" >/dev/null 2>&1
}

wait_for_model() {
  local ip="$1" max_attempts=120 attempt=0
  info "Waiting for model to be ready..."
  while ! curl -sf "http://$ip:$OCR_MODEL_PORT/v1/models" >/dev/null 2>&1; do
    attempt=$((attempt + 1))
    if [[ $attempt -ge $max_attempts ]]; then
      err "Model did not start within ${max_attempts}s. Check logs."
      return 1
    fi
    sleep 5
  done
  ok "Model ready."
}

***REMOVED*** ── Commands ────────────────────────────────────────────────

cmd_launch() {
  info "Launching GPU instance..."
  cd "$TOFU_DIR"
  tofu init -upgrade >/dev/null 2>&1 || true
  tofu apply -auto-approve -target=lambda_instance.ocr -var="ocr_enabled=true" 2>&1

  local ip; ip=$(tofu_output ocr_instance_ip 2>/dev/null || echo "")
  if [[ -z "$ip" ]]; then
    ***REMOVED*** Refresh outputs
    tofu apply -auto-approve -target=data.lambda_instance.ocr_running 2>/dev/null || true
    ip=$(tofu_output ocr_instance_ip 2>/dev/null || echo "")
  fi

  if [[ -z "$ip" ]]; then
    err "Could not get instance IP. Check Lambda Cloud console."
    return 1
  fi

  info "Instance IP: $ip"
  info "Waiting for SSH..."
  for i in $(seq 1 60); do
    if ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no \
         "$OCR_SSH_USER@$ip" "echo ready" 2>/dev/null | grep -q ready; then
      ok "SSH available."
      break
    fi
    sleep 5
  done

  info "Pulling and starting vLLM Unlimited-OCR Docker image..."
  ssh "$OCR_SSH_USER@$ip" \
    'docker pull vllm/vllm-openai:unlimited-ocr 2>&1 | tail -1'

  ssh "$OCR_SSH_USER@$ip" \
    "docker run -d --gpus all -p $OCR_MODEL_PORT:8000 \
      --name unlimited-ocr --restart unless-stopped \
      vllm/vllm-openai:unlimited-ocr \
      --model baidu/Unlimited-OCR \
      --served-model-name Unlimited-OCR" 2>&1

  echo "$ip"
}

cmd_deploy() {
  local ip="$1"
  info "Model already deployed, just ensuring it's running..."
  ssh "$OCR_SSH_USER@$ip" \
    "docker start unlimited-ocr 2>/dev/null || \
     docker run -d --gpus all -p $OCR_MODEL_PORT:8000 \
       --name unlimited-ocr --restart unless-stopped \
       vllm/vllm-openai:unlimited-ocr \
       --model baidu/Unlimited-OCR \
       --served-model-name Unlimited-OCR" >/dev/null 2>&1
}

cmd_ocr() {
  local file="$1"

  if [[ ! -f "$file" ]]; then
    err "File not found: $file"
    return 1
  fi

  ***REMOVED*** Detect file type
  local ext="${file***REMOVED******REMOVED****.}"
  ext=$(echo "$ext" | tr '[:upper:]' '[:lower:]')
  local mime=""
  case "$ext" in
    png|jpg|jpeg|webp|bmp|tiff|tif) mime="image/$ext" ;;
    pdf) mime="application/pdf" ;;
    *)
      err "Unsupported format: $ext (supported: png, jpg, jpeg, webp, bmp, tiff, pdf)"
      return 1
      ;;
  esac

  ***REMOVED*** Get or launch instance
  local ip
  ip=$(get_instance_ip)
  if [[ -z "$ip" ]] || ! is_instance_running; then
    info "No running instance. Launching..."
    ip=$(cmd_launch)
    wait_for_model "$ip"
  elif ! is_model_serving; then
    info "Instance running but model not serving. Deploying..."
    cmd_deploy "$ip"
    wait_for_model "$ip"
  else
    ok "Using existing instance at $ip"
  fi

  ***REMOVED*** Upload file
  local basename; basename=$(basename "$file")
  info "Uploading $basename..."
  rsync -avz -e "ssh -o StrictHostKeyChecking=no" "$file" "$OCR_SSH_USER@$ip:/tmp/$basename" >/dev/null 2>&1

  ***REMOVED*** Build the API request
  local prompt="Extract all text from this document. Return exactly what you see, preserving layout, paragraphs, and line breaks. Do not summarize, do not comment."
  local image_mode="base"
  [[ "$mime" == "application/pdf" ]] && image_mode="base"

  info "Sending to OCR model..."
  local payload
  payload=$(cat <<EOF
{
  "model": "Unlimited-OCR",
  "messages": [
    {
      "role": "user",
      "content": [
        {"type": "text", "text": $prompt | jq -Rs .},
        {"type": "image_url", "image_url": {"url": "file:///tmp/$basename"}}
      ]
    }
  ],
  "temperature": 0,
  "max_tokens": 8192,
  "images_config": {"image_mode": "$image_mode"}
}
EOF
)

  ***REMOVED*** For PDF, use the infer.py approach on the instance
  if [[ "$mime" == "application/pdf" ]]; then
    info "PDF detected — using batch PDF OCR on instance..."
    result=$(ssh "$OCR_SSH_USER@$ip" \
      "docker exec unlimited-ocr python infer.py \
        --pdf /tmp/$basename \
        --output_dir /tmp/ocr-output \
        --concurrency 4 \
        --image_mode base 2>/dev/null" 2>/dev/null || true)
    ***REMOVED*** Read the result
    result=$(ssh "$OCR_SSH_USER@$ip" "cat /tmp/ocr-output/$(basename $file .pdf).txt 2>/dev/null || cat /tmp/ocr-output/*.txt 2>/dev/null || echo 'No output generated'" 2>/dev/null)
  else
    ***REMOVED*** Single image — direct API call
    result=$(ssh "$OCR_SSH_USER@$ip" \
      "curl -s http://localhost:$OCR_MODEL_PORT/v1/chat/completions \
        -H 'Content-Type: application/json' \
        -d $(echo "$payload" | jq -c -sR . | sed 's/^"//;s/"$//') 2>/dev/null | \
        python3 -c 'import sys,json; print(json.load(sys.stdin)[\"choices\"][0][\"message\"][\"content\"])'" 2>/dev/null || echo "OCR failed")
  fi

  echo "$result"
}

cmd_status() {
  local ip; ip=$(get_instance_ip)
  if [[ -z "$ip" ]]; then
    warn "No OCR instance provisioned."
    return 0
  fi

  info "Instance IP: $ip"
  if is_instance_running; then
    ok "Instance: running"
    if is_model_serving; then
      ok "Model: serving"
    else
      warn "Model: not serving (deploy with: $0 --deploy)"
    fi
  else
    warn "Instance: stopped/terminated"
  fi
}

cmd_kill() {
  warn "This will terminate the GPU instance!"
  if [[ "${1:-}" != "--force" ]]; then
    echo -n "Type 'terminate' to confirm: "
    read -r confirm
    [[ "$confirm" != "terminate" ]] && { err "Aborted."; return 1; }
  fi

  cd "$TOFU_DIR"
  tofu destroy -auto-approve -target=lambda_instance.ocr 2>&1
  ok "Instance terminated."
}

cmd_deploy_only() {
  local ip; ip=$(get_instance_ip)
  [[ -z "$ip" ]] && { err "No instance running. Launch first."; return 1; }
  cmd_deploy "$ip"
  wait_for_model "$ip"
}

***REMOVED*** ── Main ─────────────────────────────────────────────────────
main() {
  cd "$DIR"

  ***REMOVED*** Check for required credentials
  if [[ -z "${LAMBDA_CLOUD_API_KEY:-}" ]]; then
    err "LAMBDA_CLOUD_API_KEY not set. Get one at https://cloud.lambda.ai/api-keys"
    exit 1
  fi

  case "${1:-}" in
    --status|-s)
      cmd_status
      ;;
    --kill|-k)
      cmd_kill "${2:-}"
      ;;
    --deploy|-d)
      cmd_deploy_only
      ;;
    --launch|-l)
      cmd_launch
      ;;
    help|--help|-h)
      head -30 "$0"
      ;;
    *)
      if [[ -f "${1:-}" ]]; then
        cmd_ocr "$1"
      else
        err "Usage: $0 <image.png|document.pdf> [--keep]"
        err "       $0 --status | --kill | --deploy | --launch"
        exit 1
      fi
      ;;
  esac
}

main "$@"
