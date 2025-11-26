# Extract Subtest Tables
library(neuro2)

# do this first
# Patient name ----------------------------------------------------------

patient <- "Biggie"

# WAIS-5 Parameters Subtest --------------------------------------------

# WAIS-5 subtests
test <- "wais5_subtest"
test_name <- "WAIS-5"
pages <- c(19)
extract_columns <- c(2, 4, 5, 6)
variables <- c("scale", "raw_score", "score", "percentile")
score_type <- "scaled_score"

# File path -------------------------------------------------------------

file_path <- file.path(file.choose())
saveRDS(file_path, paste0(test, "_path.rds"))
file_path <- readRDS(paste0(test, "_path.rds"))

# Parameters -------------------------------------------------------------

params <- list(
  patient = patient,
  test = test,
  test_name = test_name,
  file = file_path,
  pages = pages,
  extract_columns = extract_columns,
  score_type = score_type,
  variables = variables
)

# Extract Areas function --------------------------------------------------

extracted_areas <- tabulapdf::extract_areas(
  file = file_path,
  pages = pages,
  method = "decide",
  output = "matrix",
  copy = TRUE
)

# Save the entire list to an R data file
saveRDS(extracted_areas, file = paste0(test, "_extracted_areas.rds"))

# Load the list from the R data file (if necessary)
extracted_areas <- readRDS(paste0(test, "_extracted_areas.rds"))

# Loop over the list and write each matrix to a CSV file
for (i in seq_along(extracted_areas)) {
  write.csv(
    extracted_areas[[i]],
    file = paste0(test, "_", i, ".csv"),
    row.names = FALSE
  )
}

# Check the extracted areas
str(extracted_areas)

# To convert a single test using extracted areas into a single data frame
df <- as.data.frame(extracted_areas[[1]])

# Remove parentheses (wais5, wais5 subtests)
df <- df |> dplyr::mutate(V2 = stringr::str_remove_all(V2, "\\(|\\)"))

# FUNCTIONS ---------------------------------------

# Function to extract columns by position---------------------------

extract_columns <- params$extract_columns

# Function to extract columns by position
extract_columns_by_position <- function(df, positions) {
  df[, positions]
}

# To save the filtered data.frame separately
filtered_df <- extract_columns_by_position(df, extract_columns)

# To overwrite the original data.frame
df <- extract_columns_by_position(df, extract_columns)

# Rename the variables
colnames(df) <- params$variables

# Step 1: Replace "-" with NA in the entire dataframe
df[df == "-"] <- NA

# Step 2: Convert 'raw score' 'score' and 'percentile' to numeric
df <- df |>
  dplyr::mutate(
    raw_score = as.numeric(raw_score),
    score = as.numeric(score),
    percentile = as.numeric(percentile)
  )

# Step 3: Remove rows where 'score' or 'percentile' are missing
df <- df |>
  dplyr::filter(!is.na(score) & !is.na(percentile)) |>
  dplyr::distinct()

# Function to calculate 95% CI if needed ----------------------------------

# Assuming df is your data.frame and calc_ci_95 is your function
for (i in seq_len(nrow(df))) {
  ci_values <- neuro2::calc_ci_95(
    ability_score = df$score[i],
    mean = 10, # change to 50, 0, 100, etc.
    standard_deviation = 3, # change to 10, 1, 15, etc.
    reliability = .90
  )
  df$true_score[i] <- ci_values["true_score"]
  df$ci_lo[i] <- ci_values["lower_ci_95"]
  df$ci_hi[i] <- ci_values["upper_ci_95"]
  df$ci_95[i] <- paste0(ci_values["lower_ci_95"], "-", ci_values["upper_ci_95"])
}

df <- df |>
  dplyr::select(-c(true_score, ci_lo, ci_hi)) |>
  dplyr::relocate(ci_95, .after = score)

# Lookup Table Match ------------------------------------------------------

# Merge the data with the lookup table
test <- "wais5"

# Load the lookup table
lookup_table <- readr::read_csv("~/Dropbox/neuropsych_lookup_table.csv")

df_merged <- dplyr::mutate(df, test = test) |>
  dplyr::left_join(lookup_table, by = c("test" = "test", "scale" = "scale")) |>
  dplyr::relocate(all_of(c("test", "test_name")), .before = "scale")

# add missing columns
df_mutated <- neuro2::gpluck_make_columns(
  df_merged,
  range = "",
  result = "",
  absort = NULL
)

# Test score ranges -------------------------------------------------------

df_mutated <- df_mutated |>
  dplyr::mutate(range = NULL) |>
  neuro2::gpluck_make_score_ranges(
    table = df_mutated,
    test_type = "npsych_test"
  ) |>
  dplyr::relocate(c(range), .after = percentile)

# Glue results for each scale ---------------------------------------------

df <- df_mutated |>
  dplyr::mutate(
    result = ifelse(
      percentile == 1,
      glue::glue(
        "{description} fell within the {range} and ranked at the {percentile}st percentile, indicating performance as good as or better than {percentile}% of same-age peers from the general population.\n"
      ),
      ifelse(
        percentile == 2,
        glue::glue(
          "{description} fell within the {range} and ranked at the {percentile}nd percentile, indicating performance as good as or better than {percentile}% of same-age peers from the general population.\n"
        ),
        ifelse(
          percentile == 3,
          glue::glue(
            "{description} fell within the {range} and ranked at the {percentile}rd percentile, indicating performance as good as or better than {percentile}% of same-age peers from the general population.\n"
          ),
          glue::glue(
            "{description} fell within the {range} and ranked at the {percentile}th percentile, indicating performance as good as or better than {percentile}% of same-age peers from the general population.\n"
          )
        )
      )
    )
  ) |>
  dplyr::select(-description) |>
  dplyr::relocate(absort, .after = result)

wais5_subtest <- df

w2 <- as.data.frame(wais5_subtest)

# Save csv ----------------------------------------------------------------

readr::write_excel_csv(w2, "data-raw/wais5_subtest.csv")
