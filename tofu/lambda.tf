***REMOVED***-----------------------------------------------------------------------------
***REMOVED***Lambda Cloud — GPU instance for Baidu Unlimited-OCR
***REMOVED***-----------------------------------------------------------------------------
***REMOVED***Launches an on-demand GPU instance to serve the Unlimited-OCR model
***REMOVED***(vLLM OpenAI-compatible endpoint). Managed as part of the same Tofu state
***REMOVED***so the OCR script can query instance status via tofus output.
***REMOVED***-----------------------------------------------------------------------------

terraform {
  }
}

provider "lambda" {
  ***REMOVED***Credentials from LAMBDA_CLOUD_API_KEY env var
}

***REMOVED***-----------------------------------------------------------------------------
***REMOVED***Data Sources
***REMOVED***-----------------------------------------------------------------------------

data "lambda_instance_types" "available" {}

***REMOVED***-----------------------------------------------------------------------------
***REMOVED***SSH Key — registered with Lambda, referenced when launching instances
***REMOVED***-----------------------------------------------------------------------------

resource "lambda_ssh_key" "default" {
  public_key = var.lambda_ssh_public_key
}

***REMOVED***-----------------------------------------------------------------------------
***REMOVED***GPU Instance — for OCR inference
***REMOVED***-----------------------------------------------------------------------------
***REMOVED***Launched on demand via `tofu apply -target=lambda_instance.ocr`.
***REMOVED***Destroy with `tofu destroy -target=lambda_instance.ocr` when done.
***REMOVED***The OCR script (scripts/ocr.sh) automates this lifecycle.
***REMOVED***-----------------------------------------------------------------------------

resource "lambda_instance" "ocr" {
  count = var.ocr_enabled ? 1 : 0

  name          = var.ocr_instance_name
  instance_type = var.ocr_instance_type
  region        = var.ocr_region
  ssh_key_names = [lambda_ssh_key.default.name]
  quantity      = 1
}

***REMOVED***-----------------------------------------------------------------------------
***REMOVED***Data Source — fetch running instance details (IP, status)
***REMOVED***-----------------------------------------------------------------------------

data "lambda_instance" "ocr_running" {
  count     = var.ocr_enabled ? 1 : 0
  id        = lambda_instance.ocr[0].id
  depends_on = [lambda_instance.ocr]
}
