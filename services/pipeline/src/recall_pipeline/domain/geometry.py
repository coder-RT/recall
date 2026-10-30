"""Frame conventions and alignment. Pure NumPy."""

from __future__ import annotations

import numpy as np

# ARKit's camera: +X right, +Y up, −Z forward. OpenCV (what MapAnything wants): +X right, +Y down, +Z forward.
_FLIP = np.diag([1.0, -1.0, -1.0, 1.0])


def column_major_to_matrix(values: list[float] | tuple[float, ...]) -> np.ndarray:
    """ARKit poses are written column-major (simd_float4x4 columns); return a normal row-major 4x4."""
    return np.asarray(values, dtype=np.float64).reshape(4, 4).T


def arkit_to_opencv(T_arkit: np.ndarray) -> np.ndarray:
    """Camera-to-world in ARKit's camera convention → camera-to-world in the OpenCV convention (same world frame)."""
    return T_arkit @ _FLIP


def umeyama(src: np.ndarray, dst: np.ndarray, with_scale: bool = True) -> tuple[float, np.ndarray, np.ndarray]:
    """Similarity transform (s, R, t) minimising ||dst − (s R src + t)||² (Umeyama 1991). src, dst: (N, 3)."""
    src, dst = np.asarray(src, float), np.asarray(dst, float)
    if src.shape != dst.shape or src.shape[0] < 3:
        raise ValueError("need at least 3 matching points")
    mu_s, mu_d = src.mean(0), dst.mean(0)
    xs, xd = src - mu_s, dst - mu_d
    cov = xd.T @ xs / len(src)
    U, D, Vt = np.linalg.svd(cov)
    S = np.eye(3)
    if np.linalg.det(U) * np.linalg.det(Vt) < 0:
        S[2, 2] = -1.0
    R = U @ S @ Vt
    var_s = (xs**2).sum() / len(src)
    s = float(np.trace(np.diag(D) @ S) / var_s) if with_scale else 1.0
    t = mu_d - s * R @ mu_s
    return s, R, t


def similarity_matrix(s: float, R: np.ndarray, t: np.ndarray) -> np.ndarray:
    M = np.eye(4)
    M[:3, :3] = s * R
    M[:3, 3] = t
    return M
