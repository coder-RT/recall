"""The hexagon's rules that import-linter can't see: the HTTP routers only map (they call use cases, never a
repository, the database, or an image library), and only use cases write the memory (CLAUDE.md: one writer)."""

import ast
from pathlib import Path

SRC = Path(__file__).resolve().parents[2] / "src" / "recall_api"
ROUTERS = sorted((SRC / "adapters" / "inbound" / "http").glob("*.py"))

# container attributes that are storage or outbound adapters, not use cases
NOT_FOR_ROUTERS = {"engine", "blobs", "homes", "scans", "objects", "owner_settings", "audit_log", "answer_log", "llm",
                   "transcriber", "worker_status"}  # fmt: skip
# Allowed on purpose: httpx (ask.py maps an unreachable model's HTTPError to a 503) and numpy (guidance.py decodes
# the uploaded 16-bit depth bytes into an array: parsing the request, no maths on it).
ROUTER_IMPORTS_BANNED = ("PIL", "sqlalchemy", "recall_api.adapters.outbound", "recall_api.domain.ports")
REPOSITORIES = {"homes", "scans", "objects", "owner_settings"}
WRITES = {"save", "delete", "put"}
# infra/demo.py seeds the recorded sample's home and scan before ingest_scan runs (make demo only; ADR in decisions.md)
WRITERS_OUTSIDE_APPLICATION = {"infra/demo.py"}


def _tree(path: Path) -> ast.AST:
    return ast.parse(path.read_text(), str(path))


def _imports(tree: ast.AST) -> list[str]:
    names = []
    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            names += [a.name for a in node.names]
        elif isinstance(node, ast.ImportFrom) and node.module:
            names.append(node.module)
    return names


def test_there_are_routers_to_check():
    assert len(ROUTERS) > 5


def test_routers_never_reach_storage_or_adapters():
    found = []
    for path in ROUTERS:
        for node in ast.walk(_tree(path)):
            is_c = isinstance(node, ast.Attribute) and isinstance(node.value, ast.Name) and node.value.id == "c"
            if is_c and node.attr in NOT_FOR_ROUTERS:
                found.append(f"{path.name}:{node.lineno} c.{node.attr}")
    assert found == [], "routers must call a use case instead: " + ", ".join(found)


def test_routers_import_no_image_database_or_outbound_code():
    found = [
        f"{path.name}: {name}"
        for path in ROUTERS
        for name in _imports(_tree(path))
        if name.startswith(ROUTER_IMPORTS_BANNED)
    ]
    assert found == []


def test_only_use_cases_write_the_memory():
    found = []
    for path in SRC.rglob("*.py"):
        rel = path.relative_to(SRC).as_posix()
        if rel.startswith(("application/", "adapters/outbound/persistence/")) or rel in WRITERS_OUTSIDE_APPLICATION:
            continue
        for node in ast.walk(_tree(path)):
            if not (isinstance(node, ast.Call) and isinstance(node.func, ast.Attribute) and node.func.attr in WRITES):
                continue
            target = node.func.value
            if isinstance(target, ast.Attribute) and target.attr in REPOSITORIES:
                found.append(f"{rel}:{node.lineno} .{target.attr}.{node.func.attr}()")
    assert found == [], "write through a use case in application/: " + ", ".join(found)
