# wrat5

Lightweight R project with a Shiny app and Quarto document.

## Overview

This repository contains a Shiny application (`app.R`) and a Quarto document (`wrat5.qmd`) built with R. The project uses `renv` for dependency management (see `renv/`).

## Features

- Interactive Shiny app (`app.R`).
- Quarto report (`wrat5.qmd`) and generated HTML (`wrat5.html`).
- Reproducible environment via `renv`.

## Requirements

- R >= 4.0 (this project was developed with R 4.5.x)
- Recommended: RStudio or Posit/VS Code (Positron)
- System libraries as required by packages (see `renv/library` and `requirements.txt`).

## Setup (local)

Option A — restore using renv (recommended):

```fish
# from project root
Rscript -e 'if (!requireNamespace("renv", quietly = TRUE)) install.packages("renv"); renv::restore()'
```

Option B — install from requirements.txt (if present):

```fish
# uses pip for any Python deps listed in requirements.txt (if applicable)
# only relevant if the project also relies on Python tooling
python3 -m pip install -r requirements.txt
```

## Run the Shiny app

From R/Posit (recommended):

- Open `app.R` and click "Run App" in the IDE.

From the shell (headless):

```fish
# run app.R with Rscript (useful for simple local runs)
Rscript -e "shiny::runApp('.', launch.browser = TRUE)"
```

If `app.R` defines `shiny::shinyApp()` or uses `shiny::runApp()` this will launch the app.

## Render the Quarto document

Quarto document is `wrat5.qmd`. To render locally (requires quarto installed):

```fish
quarto render wrat5.qmd
```

Or render from R with the quarto package:

```fish
Rscript -e "quarto::quarto_render('wrat5.qmd')"
```

## Deployment

Suggested deployment options:

- Posit Connect (recommended for enterprise/paid hosting)
- shinyapps.io (free/paid) for simple deployments
- Docker: add a Dockerfile with R, renv restore, and expose port for Shiny

## Project structure (key files)

- `app.R` — main Shiny application
- `wrat5.qmd` — Quarto document
- `wrat5.html` — generated HTML output
- `renv/` — local renv environment and library
- `requirements.txt` — optional Python requirements

## Development notes

- Use `renv::snapshot()` after changing dependencies.
- To update packages, use `renv::update()` or install normally and then snapshot.

## License

This project does not include a license file. Add a `LICENSE` (for example MIT) if you want to permit reuse.

## Contact

For questions or issues, open an issue in this repository or contact the maintainer.
