# Neuropsych PDF Table Extractors

Standalone Quarto documents with Shiny interactivity for extracting score tables from neuropsychological test PDFs.

## Files

| File | Purpose |
|------|---------|
| `index.qmd` | Multi-test template supporting 10+ batteries |
| `wrat5.qmd` | WRAT-5 specific extractor |
| `conners4.qmd` | Conners-4 (Self/Parent/Teacher) extractor |

## Requirements

```r
# Required
install.packages(c("shiny", "tidyverse", "tabulapdf", "DT"))

# tabulapdf requires Java - install via:
# macOS: brew install java
# Ubuntu: sudo apt install default-jdk

# Optional (for score range classification)
# devtools::install_github("brainworkup/neuro2")
```

## Usage

```bash
# Run locally
quarto preview wrat5.qmd

# Or render static HTML (won't have interactivity)
quarto render wrat5.qmd
```

## Creating a New Test Extractor

1. Copy `wrat5.qmd` as template
2. Modify the setup chunk:
   - Change default `test_code`, `test_name`
   - Update scale lists for your test
   - Adjust score type (standard_score, scaled_score, t_score)
3. Adjust column mapping UI for your test's output format
4. Update lookup table joins if needed

### Score Types

| Type | Mean | SD | Tests |
|------|------|-----|-------|
| `standard_score` | 100 | 15 | WIAT, WRAT, WJ |
| `scaled_score` | 10 | 3 | WAIS/WISC subtests, D-KEFS |
| `t_score` | 50 | 10 | Conners, BASC, PAI |

## Workflow Integration

Output CSV files match the neuro2 package format with columns:
- `test`, `test_name`, `scale`, `raw_score`, `score`
- `ci_95`, `percentile`, `range`
- `domain`, `subdomain`, `narrow`
- `test_type`, `score_type`

These can be directly appended to your `neurocog.csv` or `neurobehav.csv` data files.

## Troubleshooting

**"Java not found"**: Install Java and ensure `JAVA_HOME` is set
```bash
# Check Java
java -version
R -e 'rJava::.jcall("java/lang/System", "S", "getProperty", "java.home")'
```

**Tables not detected**: Try changing extraction method (stream vs lattice) or specifying different pages

**Wrong columns mapped**: Use the raw preview to identify correct column positions
