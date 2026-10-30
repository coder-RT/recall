from fastapi import APIRouter, Depends

from .deps import container
from .models import Health

router = APIRouter(tags=["health"])


@router.get("/health", response_model=Health)
def get_health(c=Depends(container)) -> Health:
    return Health(status="ok", llm_provider=c.settings.llm_provider, storage=c.settings.storage)
