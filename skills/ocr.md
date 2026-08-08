***REMOVED*** OCR — Baidu Unlimited-OCR

Extract text from images and PDFs using the Baidu Unlimited-OCR model deployed on a Lambda GPU instance.

***REMOVED******REMOVED*** Invocation

Ask Zet: "ocr this image" or "extract text from this pdf" with an attachment.

***REMOVED******REMOVED*** Supported formats

png, jpg, jpeg, webp, bmp, tiff, tif, pdf

***REMOVED******REMOVED*** How it works

1. On first call, spins up a Lambda GPU instance (`gpu_1x_a10`)
2. Pulls and runs `vllm/vllm-openai:unlimited-ocr` with model `baidu/Unlimited-OCR`
3. Uploads the file, sends it to the OpenAI-compatible API
4. Returns the extracted text
5. Instance stays warm for 5 minutes of idle before auto-terminating (`--keep` to hold)

***REMOVED******REMOVED*** CLI

```bash
cd zet
./scripts/ocr.sh document.pdf
./scripts/ocr.sh image.png --keep
./scripts/ocr.sh --status
./scripts/ocr.sh --kill
```

***REMOVED******REMOVED*** Requirements

- `LAMBDA_CLOUD_API_KEY` env var set (get from https://cloud.lambda.ai/api-keys)
- SSH key registered with Lambda Cloud (via Tofu: `tofu/lambda.tf`)
- OpenTofu in PATH

***REMOVED******REMOVED*** Data flow

```
File → rsync → Lambda GPU Instance → vLLM (Unlimited-OCR) → extracted text → stdout
```

***REMOVED******REMOVED*** Cost

~$0.60-0.90/hr for `gpu_1x_a10` (24GB) or `gpu_1x_l40s` (48GB). A typical OCR run
takes 1-5 minutes on a single image, ~10-30 seconds per PDF page. Most OCR calls
cost under $0.10.
