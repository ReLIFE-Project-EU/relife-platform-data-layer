from importlib.metadata import version

from fastapi import FastAPI

from service_api.routes import admin, auth, health, reports, storage

try:
    __version__ = version("service-api")
except ImportError:
    __version__ = "development"


app = FastAPI(
    title="Service API",
    description="An example of a ReLIFE service as an HTTP API",
    version=__version__,
)

app.include_router(health.router)
app.include_router(auth.router)
app.include_router(reports.router)
app.include_router(admin.router)
app.include_router(storage.router)
