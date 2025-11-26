"""
Neuropsychological Assessment Data Extractor
A Shiny for Python app that extracts, processes, and exports neuropsych test data.

Features:
- Upload multi-section assessment CSV files
- Auto-detect test domains (WAIS, WMS, D-KEFS, etc.)
- Merge with neuropsych lookup table for metadata
- Compute missing percentile and range values
- Export formatted CSV files by test
"""

from shiny import App, Inputs, Outputs, Session, reactive, render, ui
from shinywidgets import render_widget
import pandas as pd
import numpy as np
from scipy import stats
import io
import re
from pathlib import Path
import zipfile
from datetime import datetime


# =============================================================================
# Score Conversion Functions (Ported from pdf.R)
# =============================================================================

def compute_percentile_range(score: float, score_type: str) -> tuple[float, float, str]:
    """
    Compute z-score, percentile, and performance range from a standardized score.
    
    Parameters based on score_type:
    - z_score: mu=0, sd=1
    - scaled_score: mu=10, sd=3
    - t_score: mu=50, sd=10
    - standard_score: mu=100, sd=15
    """
    params = {
        "z_score": {"mu": 0, "sd": 1},
        "scaled_score": {"mu": 10, "sd": 3},
        "t_score": {"mu": 50, "sd": 10},
        "standard_score": {"mu": 100, "sd": 15},
    }
    
    if score_type not in params or pd.isna(score):
        return np.nan, np.nan, None
    
    mu = params[score_type]["mu"]
    sd = params[score_type]["sd"]
    
    # Calculate z-score
    z = (score - mu) / sd
    
    # Calculate percentile
    percentile = round(stats.norm.cdf(z) * 100, 1)
    
    # Classify range
    pct_rounded = int(round(percentile))
    if pct_rounded < 1:
        pct_rounded = int(np.ceil(percentile))
    elif pct_rounded > 99:
        pct_rounded = int(np.floor(percentile))
    
    if pct_rounded >= 98:
        range_label = "Exceptionally High"
    elif 91 <= pct_rounded <= 97:
        range_label = "Above Average"
    elif 75 <= pct_rounded <= 90:
        range_label = "High Average"
    elif 25 <= pct_rounded <= 74:
        range_label = "Average"
    elif 9 <= pct_rounded <= 24:
        range_label = "Low Average"
    elif 2 <= pct_rounded <= 8:
        range_label = "Below Average"
    else:
        range_label = "Exceptionally Low"
    
    return z, percentile, range_label


def classify_range_from_percentile(percentile: float) -> str:
    """Classify performance range from percentile value."""
    if pd.isna(percentile):
        return None
    
    pct = int(round(percentile))
    if pct >= 98:
        return "Exceptionally High"
    elif 91 <= pct <= 97:
        return "Above Average"
    elif 75 <= pct <= 90:
        return "High Average"
    elif 25 <= pct <= 74:
        return "Average"
    elif 9 <= pct <= 24:
        return "Low Average"
    elif 2 <= pct <= 8:
        return "Below Average"
    else:
        return "Exceptionally Low"


# =============================================================================
# CSV Parsing Functions
# =============================================================================

def parse_assessment_results(file_content: str) -> dict[str, pd.DataFrame]:
    """
    Parse a multi-section assessment CSV file and extract test domains.
    Returns dict of DataFrames keyed by test identifier.
    """
    lines = [l.strip() for l in file_content.strip().split('\n')]
    
    sections = []
    current = None
    
    for line in lines:
        # Check for section headers
        if 'WMS-IV' in line and ('Composite' in line or 'Subtest' in line):
            if current: sections.append(current)
            is_composite = 'Composite' in line
            current = {
                'test': 'wms4', 'test_name': 'WMS-IV',
                'type': 'composite' if is_composite else 'subtest',
                'data': []
            }
        elif 'WAIS-IV' in line and ('Composite' in line or 'Subtest' in line):
            if current: sections.append(current)
            is_composite = 'Composite' in line
            current = {
                'test': 'wais4', 'test_name': 'WAIS-IV',
                'type': 'composite' if is_composite else 'subtest',
                'data': []
            }
        elif 'WAIS-V' in line or 'WAIS-5' in line:
            if current: sections.append(current)
            is_composite = 'Composite' in line or 'Index' in line
            current = {
                'test': 'wais5', 'test_name': 'WAIS-5',
                'type': 'composite' if is_composite else 'subtest',
                'data': []
            }
        elif 'D-KEFS' in line:
            if current: sections.append(current)
            current = {
                'test': 'dkefs', 'test_name': 'D-KEFS',
                'type': 'subtest', 'data': []
            }
        elif 'WISC-V' in line or 'WISC-5' in line:
            if current: sections.append(current)
            is_composite = 'Composite' in line or 'Index' in line
            current = {
                'test': 'wisc5', 'test_name': 'WISC-5',
                'type': 'composite' if is_composite else 'subtest',
                'data': []
            }
        elif 'WIAT-4' in line or 'WIAT-IV' in line:
            if current: sections.append(current)
            is_composite = 'Composite' in line
            current = {
                'test': 'wiat4', 'test_name': 'WIAT-4',
                'type': 'composite' if is_composite else 'subtest',
                'data': []
            }
        elif 'CVLT' in line:
            if current: sections.append(current)
            current = {
                'test': 'cvlt3', 'test_name': 'CVLT-3',
                'type': 'subtest', 'data': []
            }
        elif 'ROCF' in line or 'Rey' in line:
            if current: sections.append(current)
            current = {
                'test': 'rocft', 'test_name': 'ROCFT',
                'type': 'subtest', 'data': []
            }
        elif current and line and not line.startswith(','):
            # Parse data row
            parts = [p.strip().strip('"') for p in line.split(',')]
            if parts[0] and 'No composite' not in parts[0] and 'Score' not in parts[0]:
                current['data'].append(parts)
    
    if current: sections.append(current)
    
    # Convert sections to DataFrames
    results = {}
    for sec in sections:
        if not sec['data']:
            continue
        
        test_id = sec['test']
        rows = []
        
        for parts in sec['data']:
            scale = parts[0] if len(parts) > 0 else ''
            
            if sec['type'] == 'composite':
                # Composite: Scale, Standard Score, Percentile, CI90, CI95
                score = parts[1] if len(parts) > 1 else ''
                percentile = parts[2] if len(parts) > 2 else ''
                ci_95 = parts[4] if len(parts) > 4 else ''
                raw_score = ''
                score_type = 'standard_score'
            else:
                # Subtest: Scale, Raw Score, Scaled Score, [Percentile]
                raw_score = parts[1] if len(parts) > 1 else ''
                score = parts[2] if len(parts) > 2 else ''
                percentile = parts[3] if len(parts) > 3 else ''
                ci_95 = ''
                score_type = 'scaled_score'
                
                # D-KEFS error rows might have percentile instead of scaled score
                if test_id == 'dkefs' and 'Error' in scale and not score:
                    score_type = 'percentile'
            
            rows.append({
                'test': test_id,
                'test_name': sec['test_name'],
                'scale': scale,
                'raw_score': pd.to_numeric(raw_score, errors='coerce'),
                'score': pd.to_numeric(score, errors='coerce'),
                'percentile': pd.to_numeric(percentile, errors='coerce'),
                'ci_95': ci_95 if ci_95 else np.nan,
                'score_type': score_type
            })
        
        df = pd.DataFrame(rows)
        
        # Combine into single DF per test
        if test_id in results:
            results[test_id] = pd.concat([results[test_id], df], ignore_index=True)
        else:
            results[test_id] = df
    
    return results


# =============================================================================
# Lookup Table Functions
# =============================================================================

def load_lookup_table(file_content: str = None) -> pd.DataFrame:
    """Load neuropsych lookup table from content or default."""
    if file_content:
        return pd.read_csv(io.StringIO(file_content))
    
    # Default lookup table path
    lookup_path = Path("/mnt/project/neuropsych_lookup_table.csv")
    if lookup_path.exists():
        return pd.read_csv(lookup_path)
    
    return pd.DataFrame()


def merge_with_lookup(df: pd.DataFrame, lookup: pd.DataFrame) -> pd.DataFrame:
    """Merge test data with lookup table to add metadata columns."""
    if lookup.empty:
        # Add empty metadata columns
        meta_cols = ["domain", "subdomain", "narrow", "pass", "verbal", 
                     "timed", "test_type", "absort", "description"]
        for col in meta_cols:
            df[col] = np.nan
        return df
    
    # Create merge keys - try multiple matching strategies
    df = df.copy()
    
    # Strategy 1: Direct match on scale and test
    df["scale_clean"] = df["scale"].str.strip().str.lower()
    df["test_clean"] = df["test"].str.strip().str.lower()
    
    lookup_copy = lookup.copy()
    lookup_copy["scale_clean"] = lookup_copy["scale"].str.strip().str.lower()
    lookup_copy["test_clean"] = lookup_copy["test"].str.strip().str.lower()
    
    # Also create alternate scale names for matching
    # Handle cases like "Verbal Comprehension" vs "Verbal Comprehension (VCI)"
    lookup_copy["scale_base"] = lookup_copy["scale"].str.replace(r"\s*\([^)]*\)\s*", "", regex=True).str.strip().str.lower()
    df["scale_base"] = df["scale"].str.replace(r"\s*\([^)]*\)\s*", "", regex=True).str.strip().str.lower()
    
    # D-KEFS specific: Add "CWI " prefix for matching
    dkefs_mask = df["test"] == "dkefs"
    df.loc[dkefs_mask, "scale_cwi"] = "cwi " + df.loc[dkefs_mask, "scale_clean"]
    df.loc[~dkefs_mask, "scale_cwi"] = df.loc[~dkefs_mask, "scale_clean"]
    
    # Merge columns to add
    merge_cols = ["scale_clean", "test_clean", "domain", "subdomain", "narrow", 
                  "pass", "verbal", "timed", "test_type", "absort", "description"]
    # Also get score_type from lookup
    if "score_type" in lookup_copy.columns:
        merge_cols.append("score_type")
    
    lookup_subset = lookup_copy[[c for c in merge_cols if c in lookup_copy.columns]]
    
    # Try exact match first
    merged = df.merge(
        lookup_subset,
        on=["scale_clean", "test_clean"],
        how="left",
        suffixes=("", "_lookup")
    )
    
    # For unmatched rows, try base name match
    unmatched = merged["domain"].isna()
    if unmatched.any():
        lookup_base = lookup_copy.drop_duplicates(subset=["scale_base", "test_clean"])
        base_merge = df[unmatched].merge(
            lookup_base[["scale_base", "test_clean", "domain", "subdomain", "narrow", 
                        "pass", "verbal", "timed", "test_type", "absort", "description"]],
            on=["scale_base", "test_clean"],
            how="left",
            suffixes=("", "_base")
        )
        
        # Fill in from base match
        for col in ["domain", "subdomain", "narrow", "pass", "verbal", "timed", 
                   "test_type", "absort", "description"]:
            if col in base_merge.columns:
                merged.loc[unmatched, col] = base_merge[col].values
    
    # For D-KEFS, try CWI prefix match
    dkefs_unmatched = merged["domain"].isna() & (merged["test"] == "dkefs")
    if dkefs_unmatched.any():
        cwi_merge = df[dkefs_unmatched].merge(
            lookup_copy[lookup_copy["test_clean"] == "dkefs"][
                ["scale_clean", "domain", "subdomain", "narrow", 
                 "pass", "verbal", "timed", "test_type", "absort", "description"]
            ],
            left_on="scale_cwi",
            right_on="scale_clean",
            how="left",
            suffixes=("", "_cwi")
        )
        
        for col in ["domain", "subdomain", "narrow", "pass", "verbal", "timed", 
                   "test_type", "absort", "description"]:
            col_cwi = f"{col}_cwi" if f"{col}_cwi" in cwi_merge.columns else col
            if col_cwi in cwi_merge.columns:
                merged.loc[dkefs_unmatched, col] = cwi_merge[col_cwi].values
    
    # Use lookup score_type if available and current is missing/default
    if "score_type_lookup" in merged.columns:
        merged["score_type"] = merged["score_type_lookup"].fillna(merged["score_type"])
        merged = merged.drop(columns=["score_type_lookup"], errors="ignore")
    
    # Clean up temp columns
    cols_to_drop = ["scale_clean", "test_clean", "scale_base", "scale_cwi"]
    merged = merged.drop(columns=[c for c in cols_to_drop if c in merged.columns], errors="ignore")
    
    return merged


# =============================================================================
# Percentile/Range Computation
# =============================================================================

def fill_missing_percentile_range(df: pd.DataFrame) -> pd.DataFrame:
    """Fill missing percentile and range values based on scores."""
    df = df.copy()
    
    for idx, row in df.iterrows():
        score = row.get("score")
        score_type = row.get("score_type", "scaled_score")
        current_pct = row.get("percentile")
        current_range = row.get("range")
        
        # Skip if score is missing
        if pd.isna(score):
            continue
        
        # Compute if percentile is missing
        if pd.isna(current_pct):
            z, pct, range_label = compute_percentile_range(score, score_type)
            df.at[idx, "z"] = z
            df.at[idx, "percentile"] = pct
            if pd.isna(current_range):
                df.at[idx, "range"] = range_label
        elif pd.isna(current_range):
            # Have percentile but no range
            df.at[idx, "range"] = classify_range_from_percentile(current_pct)
    
    return df


def generate_result_text(row: pd.Series) -> str:
    """Generate result narrative text for a scale."""
    scale = row.get("scale", "")
    pct = row.get("percentile")
    range_label = row.get("range", "")
    description = row.get("description", "")
    
    if pd.isna(pct):
        return f"{scale} performance was {range_label}."
    
    pct_suffix = "th"
    pct_int = int(round(pct)) if not pd.isna(pct) else 0
    if pct_int % 10 == 1 and pct_int != 11:
        pct_suffix = "st"
    elif pct_int % 10 == 2 and pct_int != 12:
        pct_suffix = "nd"
    elif pct_int % 10 == 3 and pct_int != 13:
        pct_suffix = "rd"
    
    if description and not pd.isna(description):
        return (f"{description} fell within the {range_label} range and ranked at the "
                f"{pct_int}{pct_suffix} percentile, indicating performance as good as or "
                f"better than {pct_int}% of same-age peers from the general population.")
    
    return (f"{scale} performance fell within the {range_label} range and ranked at the "
            f"{pct_int}{pct_suffix} percentile.")


# =============================================================================
# Shiny UI
# =============================================================================

app_ui = ui.page_sidebar(
    ui.sidebar(
        ui.h4("📁 Data Input"),
        ui.input_file(
            "assessment_file", 
            "Upload Assessment CSV",
            accept=[".csv"],
            multiple=False
        ),
        ui.hr(),
        ui.input_file(
            "lookup_file",
            "Upload Lookup Table (Optional)",
            accept=[".csv"],
            multiple=False
        ),
        ui.p("Uses default lookup table if not provided", class_="text-muted small"),
        ui.hr(),
        ui.h4("⚙️ Options"),
        ui.input_checkbox("compute_missing", "Compute missing percentiles", value=True),
        ui.input_checkbox("generate_results", "Generate result text", value=True),
        ui.hr(),
        ui.download_button("download_all", "📥 Download All CSVs", class_="btn-primary w-100"),
        width=300
    ),
    ui.navset_card_tab(
        ui.nav_panel(
            "📊 Extracted Data",
            ui.output_ui("test_selector"),
            ui.output_data_frame("data_table")
        ),
        ui.nav_panel(
            "📋 Summary",
            ui.output_ui("summary_stats")
        ),
        ui.nav_panel(
            "🔍 Raw Preview",
            ui.output_text_verbatim("raw_preview")
        ),
    ),
    title="Neuropsych Assessment Data Extractor",
    fillable=True
)


# =============================================================================
# Shiny Server
# =============================================================================

def server(input: Inputs, output: Outputs, session: Session):
    
    # Reactive: Load lookup table
    @reactive.Calc
    def lookup_table():
        lookup_file = input.lookup_file()
        if lookup_file:
            content = lookup_file[0]["datapath"]
            with open(content, 'r', encoding='utf-8-sig') as f:
                return load_lookup_table(f.read())
        return load_lookup_table()
    
    # Reactive: Parse uploaded assessment file
    @reactive.Calc
    def parsed_data():
        file_info = input.assessment_file()
        if not file_info:
            return {}
        
        file_path = file_info[0]["datapath"]
        with open(file_path, 'r', encoding='utf-8-sig') as f:
            content = f.read()
        
        return parse_assessment_results(content)
    
    # Reactive: Process all test data
    @reactive.Calc
    def processed_data():
        raw_data = parsed_data()
        if not raw_data:
            return {}
        
        lookup = lookup_table()
        results = {}
        
        for test_id, df in raw_data.items():
            # Merge with lookup
            merged_df = merge_with_lookup(df, lookup)
            
            # Compute missing percentiles/ranges
            if input.compute_missing():
                merged_df = fill_missing_percentile_range(merged_df)
            
            # Generate result text
            if input.generate_results():
                merged_df["result"] = merged_df.apply(generate_result_text, axis=1)
            
            results[test_id] = merged_df
        
        return results
    
    # UI: Test selector
    @output
    @render.ui
    def test_selector():
        data = processed_data()
        if not data:
            return ui.p("Upload an assessment file to begin", class_="text-muted")
        
        choices = list(data.keys())
        return ui.input_select(
            "selected_test",
            "Select Test:",
            choices=choices,
            selected=choices[0] if choices else None
        )
    
    # Output: Data table
    @output
    @render.data_frame
    def data_table():
        data = processed_data()
        if not data:
            return pd.DataFrame()
        
        selected = input.selected_test()
        if not selected or selected not in data:
            return pd.DataFrame()
        
        df = data[selected]
        
        # Order columns for display
        display_cols = [
            "test", "test_name", "scale", "raw_score", "score", "ci_95",
            "percentile", "range", "domain", "subdomain", "narrow",
            "pass", "verbal", "timed", "test_type", "score_type", "result"
        ]
        existing_cols = [c for c in display_cols if c in df.columns]
        df = df[existing_cols]
        
        return render.DataTable(df, filters=True, height="500px")
    
    # Output: Summary statistics
    @output
    @render.ui
    def summary_stats():
        data = processed_data()
        if not data:
            return ui.p("No data loaded")
        
        cards = []
        for test_id, df in data.items():
            n_scales = len(df)
            n_with_pct = df["percentile"].notna().sum()
            domains = df["domain"].dropna().unique()
            
            card = ui.card(
                ui.card_header(f"📝 {test_id.upper()}"),
                ui.p(f"Scales: {n_scales}"),
                ui.p(f"With percentile: {n_with_pct}"),
                ui.p(f"Domains: {', '.join(domains) if len(domains) > 0 else 'N/A'}"),
            )
            cards.append(card)
        
        return ui.layout_column_wrap(*cards, width="250px")
    
    # Output: Raw file preview
    @output
    @render.text
    def raw_preview():
        file_info = input.assessment_file()
        if not file_info:
            return "No file uploaded"
        
        with open(file_info[0]["datapath"], 'r', encoding='utf-8-sig') as f:
            return f.read()[:5000]
    
    # Download: All CSVs as ZIP
    @render.download(filename=lambda: f"neuropsych_data_{datetime.now().strftime('%Y%m%d_%H%M%S')}.zip")
    def download_all():
        data = processed_data()
        if not data:
            return
        
        # Create ZIP file in memory
        zip_buffer = io.BytesIO()
        with zipfile.ZipFile(zip_buffer, 'w', zipfile.ZIP_DEFLATED) as zf:
            for test_id, df in data.items():
                # Order columns
                col_order = [
                    "test", "test_name", "scale", "raw_score", "score", "ci_95",
                    "percentile", "range", "domain", "subdomain", "narrow",
                    "pass", "verbal", "timed", "test_type", "score_type", 
                    "absort", "description", "result"
                ]
                existing = [c for c in col_order if c in df.columns]
                df_out = df[existing]
                
                # Convert to CSV
                csv_buffer = io.StringIO()
                df_out.to_csv(csv_buffer, index=False)
                
                # Add to ZIP
                zf.writestr(f"{test_id}.csv", csv_buffer.getvalue())
        
        zip_buffer.seek(0)
        yield zip_buffer.getvalue()


# =============================================================================
# Create App
# =============================================================================

app = App(app_ui, server)
