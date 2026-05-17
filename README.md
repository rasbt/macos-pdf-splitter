&nbsp;
# PDF Splitter (macOS)

Native macOS app to split a PDF into per-page PDFs and export per-page images. It supports PNG and WEBP, with cropping, padding, DPI control, and optional scaling.

PNG rendering defaults to Poppler (`pdftocairo`/`pdftoppm`) for sharper output; you can disable it in the UI to use PDFKit instead. Install Poppler with `brew install poppler` if needed.

WEBP quality is adjustable, and WEBP export can fall back to `cwebp` if ImageIO does not support it.

Below is a screenshot of the interface.

![Example](docs/doc-1.png)

And the following screenshot shows a list of the generated files.

![Example](docs/doc-2.png)&nbsp;

Try it yourself using the [docs/all-figures.pdf](docs/all-figures.pdf) demo PDF.

&nbsp;

## Download and use app

Download and open [PDF.Splitter.dmg](https://github.com/rasbt/macos-pdf-splitter/releases/download/v1.0/PDF.Splitter.dmg), which contains the `PDF Splitter.app`.

&nbsp;
## Build and run

Alternatively, build the app locally yourself:

```bash
swift build
swift run
```

&nbsp;
## Build a release app bundle

To create the macOS app bundle and release zip, run:

```bash
./scripts/build_release_app.sh
```

The script accepts two optional arguments:

```bash
./scripts/build_release_app.sh <version> <build-number>
```

Defaults:
- `version`: `1.0`
- `build-number`: `1`

Outputs:
- `../non-GitHub/dist/PDF Splitter.app` for local builds
- `../non-GitHub/dist/PDFSplitterMac-macOS.zip` for local builds
