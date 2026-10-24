Unzip over the repo root.

  Dockerfile          usage comment now uses WEBSITE_/RAG_/MASTER_ env vars and real paths (build steps unchanged)
  .gitignore          reconstructed from the garbled upload; .env.leadwise -> .env.website; adds .env.* and logs/
                      (diff against your real file before overwriting)
  .dockerignore       also excludes .env*, data, schema, logs, tools
  tools/load_master.ps1, tools/load_rag.ps1
                      em dashes replaced with '-' (avoids PowerShell 5.1 encoding garbling); logic unchanged
