"""
ORBIT Function App entry point.

Hosts two functions in one deployment:
  - orbit_parser: Blob trigger on orbit-pptx-raw/{name}
  - orbit_api:    HTTP trigger fronting a FastAPI (ASGI) application
"""
from __future__ import annotations

import logging
import os

import azure.functions as func

from orbit_parser import handle_blob
from orbit_api import app as fastapi_app

app = func.AsgiFunctionApp(app=fastapi_app, http_auth_level=func.AuthLevel.ANONYMOUS)


@app.blob_trigger(
    arg_name="blob",
    path="orbit-pptx-raw/{name}",
    connection="AzureWebJobsStorage",
)
def orbit_parser(blob: func.InputStream) -> None:
    logging.info("orbit_parser triggered: name=%s size=%s", blob.name, blob.length)
    try:
        handle_blob(blob_name=blob.name, blob_bytes=blob.read())
    except Exception:
        logging.exception("orbit_parser failed for blob %s", blob.name)
        raise
