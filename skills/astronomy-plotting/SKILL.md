---
name: astronomy-plotting
description: Create or edit publication-quality astronomical figures with Matplotlib using journal-aware typography, AAS/IOP submission limits, colour-accessibility checks, physical figure sizing, editable vector output, and a consistent inward-tick axis style. Use for spectra, light curves, imaging diagnostics, FITS-derived plots, and other astronomy figures; do not use for generic dashboards or decorative graphics.
---

# Astronomy Plotting

Create figures that are scientifically traceable, visually consistent, and ready for an astronomy-journal submission. Inspect the current plotting code, data products, units, and repository conventions before changing them. Preserve raw FITS and other original scientific data; plot derived or explicitly selected display arrays and keep the transformation reproducible.

This skill covers **static figures only**. Animations, interactive figures, and figure sets are out of scope; if one of those is the deliverable, consult the target journal's guide directly.

## Journal and typography rules

- If the user names a journal, check that journal's current official artwork guide and let its exact requirements override these defaults. Do not present Nature's rules as universal rules for every astronomy journal. For AAS journals (ApJ, AJ, ApJL, RNAAS, PSJ) see the AAS section below, which supersedes the Nature-oriented defaults.
- Default to a consistent sans-serif typeface, preferably Arial or Helvetica when the target journal accepts them. Verify the resolved font with `font_manager.findfont(..., fallback_to_default=False)`; do not silently call Liberation Sans or another substitute Arial.
- For Nature-like final artwork, use the final physical size when possible: approximately 89–90 mm for one column, 180–183 mm for two columns, and commonly 5–7 pt text at that final size. The requested local axis style uses 12 pt tick labels by default; if a journal's final-size rule conflicts, expose the size as a parameter and follow the target journal.
- Keep all text editable. Do not convert text to outlines or rasterize labels. For PDF/PS, use TrueType font embedding (`pdf.fonttype=42`, `ps.fonttype=42`); for SVG, keep text as text (`svg.fonttype='none'`) unless the destination explicitly requires paths.
- Use regular font weight for publication figures by default; do not use bold text unless the user or target journal explicitly requests it.
- Prefer vector PDF/EPS/SVG for line art and plots. Use RGB for colour figures unless the target journal specifies otherwise. Use at least 300–450 dpi for raster panels according to the target journal; Nature's current figure guide asks for 450 dpi for raster images.
- For logarithmic y axes, label the quantity with its unscaled physical unit and let the logarithmic tick labels communicate the order of magnitude. Do not add a \(10^{-n}\) scale factor to the ylabel or retain a separate Matplotlib offset multiplier; apply explicit unit scaling in the label only for linear axes when it improves readability.

## AAS journals (ApJ, AJ, ApJL, RNAAS, PSJ)

Source: the AAS Journals Graphics Guide (journals.aas.org/graphics-guide). The AAS guide
does not fix figure column widths — AASTeX scales figures by `\textwidth` fractions, and AAS
states that production "may rearrange or resize the figures". Derive every limit from the
**printed** size, not the authored size (see the scaling rule below).

Hard limits and requirements:

- **Minimum 6 pt font size.** This overrides the "5–7 pt" Nature default above. Never author
  text below 6 pt for an AAS submission.
- **Minimum 0.5 pt line width.**
- Prefer vector EPS or PDF. Raster (PNG/JPG/TIFF) only if it yields at least 300 dpi on the
  final PDF page — i.e. at least 1000 pixels of horizontal resolution.
- **One figure per file, single page.** Split multipage EPS/PDF yourself before submission.
- Do not put page numbers, figure numbers, or file information inside the figure file.
- In lettered multipart figures, place the letter **inside** the panel box. If it cannot go
  inside, use typeset tags rather than drawing it in the margin.
- Keep symbol size consistent with type size, and line weight consistent with type weight.
  Both are explicit AAS requirements, not stylistic preferences.
- Dotted and dashed lines must remain mutually distinguishable when the figure is reduced.
- An EPS file must contain a bounding box. PostScript produced by "print to file" on Windows
  or macOS is frequently non-compliant; prefer PDF, or Matplotlib's own EPS writer.
- Use common fonts (Times, Helvetica, Symbol). Greek letters and math symbols should come
  from a real symbol font rather than being faked with Latin lookalikes.

### Effective size after scaling

AAS may resize a figure, so font size at submission is not font size in print. For a figure
authored at width `w_auth` and printed at `w_print`:

```
pt_effective = pt_authored * (w_print / w_auth)
```

Example: 12 pt authored at 180 mm, printed at 89 mm gives **5.93 pt** — below the 6 pt floor
even though the source file looks compliant. Consequences:

- When authoring at double-column width, use **at least 13 pt** so that single-column print
  size retains about 6.4 pt.
- Or author at the final printed width and keep text at 6 pt or above directly.
- The local 12 pt tick-label convention is comfortable at full width but marginal if AAS
  shrinks a double-column figure to one column. Check this explicitly rather than assuming.

## Colour accessibility

AAS devotes a dedicated section to this and treats it as a submission-quality issue, not a
nicety. The underlying principle: **never let colour be the only distinguishing channel.**

- Pair every colour encoding with a second channel: line style (solid/dashed/dash-dot),
  marker shape, hatching, or line weight.
- Use a perceptually uniform, colour-blind-safe colormap: `viridis`, `cividis`, `magma`,
  `inferno`, `plasma`, or cube-helix (Green 2011). Avoid `jet` and other rainbow maps.
- Coloured lines should additionally differ in linestyle; coloured symbols in shape;
  coloured histograms in hatching or line weight. AAS lists each of these explicitly.
- For overlapping symbols, prefer unsaturated or translucent colours — but note that
  transparency requires **PDF rather than EPS**. This is an explicit AAS caveat, and it means
  the accessibility choice can force the output format.
- Verify with a CVD simulator such as Color Oracle, then convert the figure to greyscale and
  re-inspect. A figure that only parses in colour is not accessible, and many readers will
  encounter the article in greyscale.

## Required default axis style

Use `scripts/astronomy_style.py` or an equivalent project-local helper. Its `set_axis_style()` implements the user's required convention:

- all four spines: linewidth 1.5;
- linear-axis minor ticks: `AutoMinorLocator(n=5)`;
- major ticks inward on all four sides, width 1.0, length 6;
- minor ticks inward on all four sides, width 1.0, length 3;
- major and minor tick labels: 12 pt by default;
- optional x/y major formatters are applied only when supplied.
- Check the lower-left corner for crowding between the first x-axis tick label and the last y-axis tick label; increase tick-label padding or margins when necessary.

Apply this after creating each axes, including every panel in a multi-panel figure. For logarithmic axes, do not use `AutoMinorLocator`; use an appropriate `LogLocator` and preserve the same tick direction/linewidth convention.

Every line this style produces (1.5 pt spines, 1.0 pt ticks) is already above the AAS 0.5 pt
floor. The floor matters for the *data* lines and annotations you add afterwards.

## Reproducible workflow

1. Determine the target journal, final column width, panel arrangement, units, uncertainty representation, and whether the plot is a diagnostic or a final display item.
2. Configure the font and output rcParams before creating text. Fail clearly or report the fallback if the requested font is unavailable.
3. Set figure dimensions in millimetres converted to inches. Use `bbox_inches='tight'` for final artwork with a small explicit `pad_inches` to remove unnecessary edge whitespace, then inspect the resulting page dimensions and clipping.
4. Apply `set_axis_style()` to every axes, then add labels, units, legends, annotations, and panel labels consistently. Do not use colour alone to encode a scientifically important distinction.
5. Save a vector master and, only when needed, a raster derivative. Keep the data-to-figure script and the exact input/product paths with the result.
6. Validate the output: inspect the rendered figure, check that labels and units are not clipped, verify the font path and PDF font type with tools such as `pdffonts`/`pdfinfo`, and separately report plotting validation versus scientific validation.

If Matplotlib or fontconfig reports an unwritable configuration/cache path, do not run the plotting program as root. Inspect `MATPLOTLIBRC`, `MPLCONFIGDIR`, `XDG_CONFIG_HOME`, and the ownership of the user config directory; for an isolated run, point `MPLCONFIGDIR` at a writable project or temporary directory. A successful plot with a redirected cache is only a runtime/environment result, not evidence that the underlying scientific reduction is correct.

Read and reuse [`scripts/astronomy_style.py`](scripts/astronomy_style.py) for the standard implementation. Copy it into a project-local utilities module when the generated figure must be reproducible outside this skill installation.

## Pre-submission checklist

Run this before calling a figure submission-ready. `audit_figure()` in
`scripts/astronomy_style.py` checks items 1 and 2 mechanically; the rest need inspection.

```python
from astronomy_style import audit_figure, report_audit

# Pass both widths when the journal may rescale the figure.
result = audit_figure(
    fig,
    width_authored_mm=180,   # width the figure is drawn at
    width_printed_mm=89,     # single-column print width, if it may be reduced
)
print(report_audit(result))
if not result["ok"]:
    raise SystemExit("figure violates AAS graphics-guide limits")
```

`audit_figure` calls `draw_without_rendering()` first, because Matplotlib only
materialises tick labels during a draw — without that, an audit of a fresh figure
silently misses every tick label.

1. **Font** — every text element is at least 6 pt *after* any journal scaling; the font
   resolved to a real file rather than a silent substitute.
2. **Lines** — the thinnest line is at least 0.5 pt; dashed and dotted styles remain
   distinguishable when the figure is reduced.
3. **Colour** — the figure still carries its meaning in greyscale; no channel relies on colour
   alone; the colormap is perceptually uniform.
4. **Files** — vector PDF/EPS for line art; raster panels at least 300 dpi with at least
   1000 px horizontal; one page per file; no page or figure numbers inside the file.
5. **Text** — labels and units are complete and unclipped; units agree with the body text;
   logarithmic axes are labelled without an offset multiplier.
6. **Traceability** — the script, its inputs, and the product paths are recorded; raw FITS
   and other original data are untouched.
7. **Reporting** — plotting validation and scientific validation are reported separately. A
   figure that renders correctly is not evidence that the underlying reduction is correct.
