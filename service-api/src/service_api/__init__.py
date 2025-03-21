import os

import uvicorn


def main() -> None:
    host = os.getenv("API_HOST", "0.0.0.0")
    port = int(os.getenv("API_PORT", 9090))
    uvicorn.run("service_api.app:app", host=host, port=port, reload=True)
