# Figure-collect Extension For Quarto

Collect figures from a Quarto document.

This first version:

- copies figure image files to a configured folder
- names copied figures from simple document-order cross-reference labels
- supports custom float prefixes declared in `crossref.custom`
- inserts figure-caption-only text into per-kind placeholder divs

## Installing

```bash
quarto add jorittmo/figure-collect
```

This will install the extension under the `_extensions` subdirectory.
If you're using version control, you will want to check in this directory.

## Using

Use the filter at Quarto's `post-quarto` stage so Quarto's cross-reference
float objects are available to the filter:

```yaml
filters:
  - at: post-quarto
    path: figure-collect
```

Add placeholders where collected captions should appear. Regular `fig` captions
use the base class, and custom kinds append `-<key>`:

```markdown
::: {.figure-caption-section}
:::

::: {.figure-caption-section-suppfig}
:::
```

Optional configuration:

```yaml
figure-collect:
  figure-dir: figures_copy
  figure-caption-section: figure-caption-section
  copy-figures: true
  keep-figures: true
  clean-figure-dir: false
  figure-kinds: [fig, suppfig]
  source-data-dir: figure_sources
  copy-source-data: true
```

Custom float prefixes are read from `crossref.custom`. For example, an item with
`key: suppfig`, `reference-prefix: Figure S`, and
`space-before-numbering: false` will copy `#suppfig-*` figures as
`Figure S1.png`, `Figure S2.png`, etc.

Different figure kinds are copied into different folders. Regular `fig` figures
use `figure-dir` directly. Custom kinds append `-<key>`, so with
`figure-dir: figures_copy`, `suppfig` figures are copied to
`figures_copy-suppfig`.

Set `clean-figure-dir: true` to remove existing files in each active figure
folder before the first figure is copied there during a render. The filter only
removes files directly inside those folders, and leaves subdirectories alone.

Use `figure-kinds` to limit which figure kinds are collected. For example,
`figure-kinds: [suppfig]` copies and collects only supplementary figures.

Set `source-data-dir` and `copy-source-data: true` to copy matching source-data
files alongside copied figures. Matching is based on the original figure stem:
for `age_path.pdf`, files named `age_path.csv` and `age_path_*.csv` in
`source-data-dir` will be copied and renamed as `Figure 1.csv`,
`Figure 1_suffix.csv`, etc. Custom kinds use their own suffixed figure folders
the same way as the figure files themselves.

Current limitation: exact engine-specific numbering beyond simple document-order
labels will need post-render processing.

## Example

Here is the source code for a minimal example: [example.qmd](example.qmd).
