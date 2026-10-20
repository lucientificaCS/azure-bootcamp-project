import os
from flask import Flask, jsonify
app = Flask(__name__)

@app.get("/")
def home():
    return jsonify(
        project="Retail Andes - Bootcamp Azure",
        message="App en container desplegada con Azure Container Apps",
    )


@app.get("/health")
def health():
    return jsonify(status="ok")

@app.get("/secret-check")
def secret_check():
    """Lee un "secret" de Key Vault usando Managed Identity, nunca devuelve el valor del secreto, solo confirma que se puede leer."""
    url = os.getenv("KEY_VAULT_URL")
    if not url:
        return jsonify(keyvault="not configured")
    try:
        from azure.identity import DefaultAzureCredential
        from azure.keyvault.secrets import SecretClient
        client = SecretClient(vault_url=url, credential=DefaultAzureCredential())
        secret = client.get_secret("demo-secret")
        return jsonify(keyvault="ok", secret_loaded=bool(secret.value))
    except Exception as e:
        return jsonify(keyvault="error", detail=type(e).__name__), 500
