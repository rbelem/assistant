#-----------------------------------------------------------------------------
#Lambda Cloud — GPU instance for Baidu Unlimited-OCR
#-----------------------------------------------------------------------------
#Launches an on-demand GPU instance to serve the Unlimited-OCR model
#(vLLM OpenAI-compatible endpoint). Managed as part of the same Tofu state
#so the OCR script can query instance status via tofus output.
#-----------------------------------------------------------------------------

terraform {
  required_providers {
    lambda = {
      source  = "github.com/albertocavalcante/lambda"
      version = "~> 0.1"
    }
  }
}

provider "lambda" {
  #Credentials from LAMBDA_CLOUD_API_KEY env var
}

#-----------------------------------------------------------------------------
#Data Sources
#-----------------------------------------------------------------------------

data "lambda_instance_types" "available" {}

#-----------------------------------------------------------------------------
#SSH Key — registered with Lambda, referenced when launching instances
#-----------------------------------------------------------------------------

resource "lambda_ssh_key" "default" {
  public_key = var.lambda_ssh_public_key
}

#-----------------------------------------------------------------------------
#GPU Instance — for OCR inference
#-----------------------------------------------------------------------------
#Launched on demand via `tofu apply -target=lambda_instance.ocr`.
#Destroy with `tofu destroy -target=lambda_instance.ocr` when done.
#The OCR script (scripts/ocr.sh) automates this lifecycle.
#-----------------------------------------------------------------------------

resource "lambda_instance" "ocr" {
  count = var.ocr_enabled ? 1 : 0

  name          = var.ocr_instance_name
  instance_type = var.ocr_instance_type
  region        = var.ocr_region
  ssh_key_names = [lambda_ssh_key.default.name]
  quantity      = 1
}

#-----------------------------------------------------------------------------
#Data Source — fetch running instance details (IP, status)
#-----------------------------------------------------------------------------

data "lambda_instance" "ocr_running" {
  count     = var.ocr_enabled ? 1 : 0
  id        = lambda_instance.ocr[0].id
  depends_on = [lambda_instance.ocr]
}
