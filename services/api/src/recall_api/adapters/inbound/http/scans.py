"""Scan upload and pipeline results: mapping only, the logic is in application/upload_scan.py."""

from __future__ import annotations

from typing import Annotated

from fastapi import APIRouter, Depends, Header, HTTPException, Request

from recall_api.application.ingest_scan import IngestError
from recall_api.application.upload_scan import UploadError
from recall_api.domain.memory import Scan as ScanEntity

from .deps import container, require_device_key
from .models import Manifest, Part, PartReceipt, Scan, ScanChange, ScanCreate, ScanResult, UploadPlan

router = APIRouter(tags=["scans"], dependencies=[Depends(require_device_key)])


def _scan(s: ScanEntity) -> Scan:
    return Scan(
        scan_id=s.id,
        home_id=s.home_id,
        room=s.room,
        status=s.status.value,
        detail=s.detail,
        frame_count=s.frame_count,
        object_count=s.object_count,
        aligned_to=s.aligned_to,
        fresh=s.fresh,
        changes=[
            ScanChange.model_validate(
                {
                    "kind": c.kind,
                    "object_id": c.object_id,
                    "label": c.label,
                    "name": c.name,
                    "color": c.color,
                    "from": c.from_place,
                    "to": c.to_place,
                }
            )
            for c in s.changes
        ],
    )


def _err(e: UploadError) -> HTTPException:
    return HTTPException(e.status, {"error": e.code, "detail": str(e)})


@router.post("/scans", response_model=UploadPlan)
def create_scan(body: ScanCreate, c=Depends(container)) -> UploadPlan:
    try:
        plan = c.upload_scan.create(
            str(body.scan_id), body.home_id, body.room, body.archive.size, body.archive.sha256, body.archive.part_size
        )
    except UploadError as e:
        raise _err(e) from e
    s = plan.scan
    return UploadPlan(
        scan_id=s.id,
        part_size=s.part_size,
        parts=[
            Part(number=n, url=f"/scans/{s.id}/parts/{n}", received=n in plan.received)
            for n in range(1, s.part_count + 1)
        ],
        manifest_url=f"/scans/{s.id}/manifest",
        complete_url=f"/scans/{s.id}/complete",
    )


@router.get("/scans/{scan_id}", response_model=Scan)
def get_scan(scan_id: str, c=Depends(container)) -> Scan:
    s = c.scans.get(scan_id)
    if s is None:
        raise HTTPException(404, {"error": "not_found", "detail": "No such scan."})
    return _scan(s)


@router.put("/scans/{scan_id}/parts/{part_number}", response_model=PartReceipt)
async def put_part(
    scan_id: str, part_number: int, request: Request, x_content_sha256: Annotated[str, Header()], c=Depends(container)
) -> PartReceipt:
    data = await request.body()
    try:
        size = c.upload_scan.put_part(scan_id, part_number, data, x_content_sha256)
    except UploadError as e:
        raise _err(e) from e
    return PartReceipt(number=part_number, size=size, sha256=x_content_sha256)


@router.put("/scans/{scan_id}/manifest", response_model=Scan)
def put_manifest(scan_id: str, body: Manifest, c=Depends(container)) -> Scan:
    try:
        return _scan(c.upload_scan.put_manifest(scan_id, body.model_dump(mode="json")))
    except UploadError as e:
        raise _err(e) from e


@router.post("/scans/{scan_id}/complete", response_model=Scan)
def complete(scan_id: str, c=Depends(container)) -> Scan:
    try:
        return _scan(c.upload_scan.complete(scan_id))
    except UploadError as e:
        raise _err(e) from e


@router.post("/scans/{scan_id}/results", response_model=Scan)
def post_results(scan_id: str, body: ScanResult, c=Depends(container)) -> Scan:
    try:
        return _scan(c.ingest_scan(scan_id, body.model_dump(mode="json")))
    except IngestError as e:
        raise HTTPException(e.status, {"error": e.code, "detail": str(e)}) from e
