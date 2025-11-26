# Neuropsychological Assessment Data Extractor

A Shiny for Python app that extracts, processes, and exports neuropsychological test data from multi-section CSV files.

## Features

- **Upload** multi-section assessment CSV files (WAIS, WMS, D-KEFS, etc.)
- **Auto-detect** test domains and section types (composites vs subtests)
- **Merge** with neuropsych lookup table for domain/subdomain metadata
- **Compute** missing percentiles and performance ranges
- **Export** formatted CSV files matching your neuro2 workflow

## Installation

```bash
pip install -r requirements.txt
```

## Running the App

```bash
shiny run neuropsych_extractor_app.py
```

Then open http://localhost:8000 in your browser.

## Score Type Conversions

Based on `gpluck_compute_percentile_range()` from pdf.R:

| Score Type     | Mean | SD |
|----------------|------|----|
| z_score        | 0    | 1  |
| scaled_score   | 10   | 3  |
| t_score        | 50   | 10 |
| standard_score | 100  | 15 |

## Performance Range Classification

| Percentile Range | Classification     |
|------------------|--------------------|
| ≥98              | Exceptionally High |
| 91-97            | Above Average      |
| 75-90            | High Average       |
| 25-74            | Average            |
| 9-24             | Low Average        |
| 2-8              | Below Average      |
| <2               | Exceptionally Low  |

## Supported Tests

- WAIS-IV / WAIS-5 (Wechsler Adult Intelligence Scale)
- WMS-IV (Wechsler Memory Scale)
- D-KEFS (Delis-Kaplan Executive Function System)
- WISC-5 (Wechsler Intelligence Scale for Children)
- WIAT-4 (Wechsler Individual Achievement Test)
- CVLT-3 (California Verbal Learning Test)
- ROCFT (Rey Complex Figure Test)

## Output Format

CSVs match your neuro2 package format:
- `test`, `test_name`, `scale`
- `raw_score`, `score`, `ci_95`, `percentile`, `range`
- `domain`, `subdomain`, `narrow`
- `pass`, `verbal`, `timed`
- `test_type`, `score_type`, `absort`, `description`, `result`

## Files

- `neuropsych_extractor_app.py` - Main Shiny app
- `requirements.txt` - Python dependencies
- `wais4.csv`, `wms4.csv`, `dkefs.csv` - Example outputs from AssessmentResults.csv
