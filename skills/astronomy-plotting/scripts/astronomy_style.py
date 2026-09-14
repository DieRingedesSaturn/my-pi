"""Reusable Matplotlib defaults and AAS compliance checks for astronomy figures.

The axis defaults intentionally follow the local astronomy plotting convention:
1.5 pt spines, inward ticks on all four sides, five linear minor intervals,
and 12 pt tick labels.

The audit helpers encode the mechanical limits from the AAS Journals Graphics
Guide (https://journals.aas.org/graphics-guide/) so that a figure can be checked
before submission instead of by eye.
"""

from __future__ import annotations

from pathlib import Path
from typing import Any

import matplotlib as mpl
from matplotlib import font_manager
from matplotlib.text import Text
from matplotlib.ticker import AutoMinorLocator

# --- AAS Journals Graphics Guide limits -------------------------------------

AAS_MIN_FONT_PT = 6.0        # "A minimum of 6 pt. font size is acceptable."
AAS_MIN_LINE_PT = 0.5        # "Lines in figures should be at minimum 0.5 points."
AAS_MIN_RASTER_DPI = 300     # "at minimum 300 DPI on the final PDF page"
AAS_MIN_RASTER_PX = 1000     # "at minimum 1000 pixels of horizontal resolution"


def mm_to_inches(value_mm: float) -> float:
    """Convert a physical figure dimension from millimetres to inches."""

    return value_mm / 25.4


def effective_font_pt(
    pt_authored: float,
    width_authored_mm: float,
    width_printed_mm: float,
) -> float:
    """Font size after the journal rescales a figure.

    AAS states that production may rearrange or resize figures, so the size in
    the submitted file is not the size on the printed page.
    """

    if width_authored_mm <= 0:
        raise ValueError("width_authored_mm must be positive")
    return pt_authored * (width_printed_mm / width_authored_mm)


def configure_publication_style(
    font_family: str = "Arial",
    *,
    allow_font_fallback: bool = False,
    raster_dpi: int = AAS_MIN_RASTER_DPI,
) -> Path:
    """Configure fonts and file output, returning the resolved font file.

    By default, a missing font is an error rather than an invisible fallback.
    Pass ``allow_font_fallback=True`` only when the fallback is an explicit,
    documented choice (for example, ``Liberation Sans``).
    """

    try:
        resolved_font = Path(
            font_manager.findfont(font_family, fallback_to_default=False)
        )
    except ValueError as exc:
        if not allow_font_fallback:
            raise RuntimeError(
                f"Requested font {font_family!r} is not installed. "
                "Install it or choose an explicit fallback."
            ) from exc
        resolved_font = Path(font_manager.findfont(font_family))

    mpl.rcParams.update(
        {
            "font.family": font_family,
            "font.sans-serif": [font_family],
            "axes.unicode_minus": False,
            "pdf.fonttype": 42,
            "ps.fonttype": 42,
            "svg.fonttype": "none",
            "savefig.dpi": raster_dpi,
            "figure.facecolor": "white",
            "savefig.facecolor": "white",
        }
    )
    return resolved_font


def set_axis_style(
    axes: Any,
    *,
    ymajorFormatter: Any | None = None,
    xmajorFormatter: Any | None = None,
    minor_intervals: int = 5,
    tick_labelsize: float = 12,
) -> Any:
    """Apply the standard astronomy axis style and return ``axes``.

    ``AutoMinorLocator`` is intended for linear axes. For log axes, replace
    the minor locators after calling this function with ``LogLocator``.
    """

    for spine_name in ("bottom", "left", "right", "top"):
        axes.spines[spine_name].set_linewidth(1.5)

    if ymajorFormatter is not None:
        axes.yaxis.set_major_formatter(ymajorFormatter)
    if xmajorFormatter is not None:
        axes.xaxis.set_major_formatter(xmajorFormatter)

    axes.yaxis.set_minor_locator(AutoMinorLocator(n=minor_intervals))
    axes.xaxis.set_minor_locator(AutoMinorLocator(n=minor_intervals))

    axes.tick_params(
        axis="both",
        direction="in",
        which="major",
        top=True,
        bottom=True,
        left=True,
        right=True,
        width=1.0,
        length=6,
    )
    axes.tick_params(
        axis="both",
        direction="in",
        which="minor",
        top=True,
        bottom=True,
        left=True,
        right=True,
        width=1.0,
        length=3,
    )

    for axis in (axes.xaxis, axes.yaxis):
        for tick in axis.get_major_ticks():
            tick.label1.set_fontsize(tick_labelsize)
        for tick in axis.get_minor_ticks():
            tick.label1.set_fontsize(tick_labelsize)

    return axes


def save_publication_figure(
    figure: Any,
    output_path: str | Path,
    *,
    dpi: int = AAS_MIN_RASTER_DPI,
    **savefig_kwargs: Any,
) -> Path:
    """Save a figure with publication-safe defaults and return its path."""

    output = Path(output_path)
    if output.suffix.lower() in {".pdf", ".eps", ".ps"}:
        savefig_kwargs.setdefault("metadata", {})
    else:
        savefig_kwargs.setdefault("dpi", dpi)
    figure.savefig(output, **savefig_kwargs)
    return output


def _collect_font_sizes(figure: Any) -> list[tuple[float, str]]:
    """Return (pt, text) for every visible, non-empty Text artist."""

    found: list[tuple[float, str]] = []
    for artist in figure.findobj(match=lambda a: isinstance(a, Text)):
        if not artist.get_visible():
            continue
        label = (artist.get_text() or "").strip()
        if not label:
            continue
        try:
            found.append((float(artist.get_fontsize()), label))
        except (TypeError, ValueError):
            continue
    return found


def _collect_line_widths(figure: Any) -> list[tuple[float, str]]:
    """Return (pt, artist-class) for every visible stroked artist."""

    found: list[tuple[float, str]] = []
    for artist in figure.findobj():
        if not artist.get_visible():
            continue
        name = type(artist).__name__
        single = getattr(artist, "get_linewidth", None)
        if callable(single):
            try:
                value = single()
            except Exception:
                value = None
            if value:
                found.append((float(value), name))
        many = getattr(artist, "get_linewidths", None)
        if callable(many):
            try:
                values = many()
            except Exception:
                values = ()
            for value in values or ():
                if value:
                    found.append((float(value), name))
    return found


def _prepare_for_audit(figure: Any) -> None:
    """Populate lazily-created artists so the audit sees the whole figure.

    Matplotlib only materialises tick labels during a draw, so an undrawn
    figure reports far fewer Text artists than it will actually render.
    ``draw_without_rendering`` runs that pipeline without needing a canvas.
    """

    prepare = getattr(figure, "draw_without_rendering", None)
    if callable(prepare):
        try:
            prepare()
            return
        except Exception:
            pass
    canvas = getattr(figure, "canvas", None)
    if canvas is not None:
        try:
            canvas.draw()
        except Exception:
            pass


def audit_figure(
    figure: Any,
    *,
    width_authored_mm: float | None = None,
    width_printed_mm: float | None = None,
    min_font_pt: float = AAS_MIN_FONT_PT,
    min_line_pt: float = AAS_MIN_LINE_PT,
) -> dict[str, Any]:
    """Check a figure against the mechanical AAS graphics-guide limits.

    Verifies the two numeric limits that can be read off the artists: minimum
    font size and minimum line width. It cannot check colour accessibility,
    file format, page count, or scientific correctness.

    Pass ``width_authored_mm`` and ``width_printed_mm`` to also evaluate the
    font size that survives journal rescaling.
    """

    _prepare_for_audit(figure)

    fonts = _collect_font_sizes(figure)
    lines = _collect_line_widths(figure)

    smallest_font = min((pt for pt, _ in fonts), default=None)
    smallest_line = min((lw for lw, _ in lines), default=None)

    violations: list[str] = []
    if smallest_font is None:
        violations.append("no visible text found; font size could not be checked")
    elif smallest_font < min_font_pt:
        offenders = sorted({t for pt, t in fonts if pt < min_font_pt})
        violations.append(
            f"font {smallest_font:g} pt is below the {min_font_pt:g} pt minimum "
            f"(offending labels: {offenders[:5]})"
        )
    if smallest_line is None:
        violations.append("no stroked artists found; line width could not be checked")
    elif smallest_line < min_line_pt:
        offenders = sorted({n for lw, n in lines if lw < min_line_pt})
        violations.append(
            f"line width {smallest_line:g} pt is below the {min_line_pt:g} pt minimum "
            f"(offending artists: {offenders[:5]})"
        )

    scaled_font: float | None = None
    if width_authored_mm is not None and width_printed_mm is not None:
        if smallest_font is not None:
            scaled_font = effective_font_pt(
                smallest_font, width_authored_mm, width_printed_mm
            )
            if scaled_font < min_font_pt:
                violations.append(
                    f"after rescaling {width_authored_mm:g} mm -> {width_printed_mm:g} mm, "
                    f"the smallest font becomes {scaled_font:.2f} pt, below the "
                    f"{min_font_pt:g} pt minimum"
                )

    return {
        "min_font_pt": smallest_font,
        "min_line_pt": smallest_line,
        "scaled_min_font_pt": scaled_font,
        "n_text_artists": len(fonts),
        "n_stroked_artists": len(lines),
        "violations": violations,
        "ok": not violations,
    }


def report_audit(result: dict[str, Any]) -> str:
    """Render an ``audit_figure`` result as a short human-readable summary."""

    status = "PASS" if result["ok"] else "FAIL"
    lines = [
        f"AAS audit: {status}",
        f"  smallest font: {result['min_font_pt']} pt "
        f"across {result['n_text_artists']} text artists",
        f"  smallest line: {result['min_line_pt']} pt "
        f"across {result['n_stroked_artists']} stroked artists",
    ]
    if result["scaled_min_font_pt"] is not None:
        lines.append(f"  after journal rescaling: {result['scaled_min_font_pt']:.2f} pt")
    for problem in result["violations"]:
        lines.append(f"  - {problem}")
    return "\n".join(lines)
