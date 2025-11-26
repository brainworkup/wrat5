# Extract Areas - General

# Patient name ----------------------------------------------------------

patient <- "Biggie"
#TODO WMS4

# WISC-V parameters ----------------------------------------------------

# WISC-5 subtests
test <- "wisc5"
test_name <- "WISC-V"
pages <- c(30)
# pages <- c(30, 30, 30, 30, 30, 31, 34, 37, 38)
extract_columns <- c(2, 4, 5, 6)
variables <- c("scale", "raw_score", "score", "percentile")
score_type <- "scaled_score"

# WISC-5 composites/indexes
test <- "wisc5"
test_name <- "WISC-V"
score_type <- "standard_score"
pages <- c(31, 34)
extract_columns <- c(1, 2, 3, 4, 5, 6)
variables <- c("scale", "abbrev", "raw_score", "score", "percentile", "ci_95")

# WISC-5 process scores
test <- "wisc5"
test_name <- "WISC-V"
pages <- c(37, 38)
extract_columns <- c(1, 2, 3, 4)
variables <- c("scale", "raw_score", "score", "percentile") # TODO:
score_type <- "scaled_score"

# WAIS-5 Parameters -------------------------------------------------------

# WAIS-5 subtests
# do this first
test <- "wais5"
test_name <- "WAIS-5"
pages <- c(7)
extract_columns <- c(2, 4, 5, 6)
variables <- c("scale", "raw_score", "score", "percentile")
score_type <- "scaled_score"

# WAIS-5 composites
# do this second
test <- "wais5"
test_name <- "WAIS-5"
pages <- c(9)
extract_columns <- c(1, 3, 4, 5, 6)
variables <- c("scale", "raw_score", "score", "percentile", "ci_95")
score_type <- "standard_score"

# WRAT-5 parameters -------------------------------------------------------

test <- "wrat5"
test_name <- "WRAT-5"
pages <- c(20)
extract_columns <- c(1, 2, 3, 4, 5)
score_type <- "standard_score"
variables <- c("scale", "raw_score", "score", "ci_95", "percentile")

# WMS-IV parameters -------------------------------------------------------

test <- "wms4"
test_name <- "WMS-IV"
pages <- c(12)
extract_columns <- c(1, 3, 4, 5)
variables <- c("scale", "raw_score", "score", "percentile")
score_type <- "scaled_score"

# File path -------------------------------------------------------------

file <- file.path(file.choose())
saveRDS(file, paste0(test, "_path.rds"))
file <- readRDS(paste0(test, "_path.rds"))

# Parameters -------------------------------------------------------------

params <- list(
  patient = patient,
  test = test,
  test_name = test_name,
  file = file,
  pages = pages,
  extract_columns = extract_columns,
  score_type = score_type,
  variables = variables
)

# Extract Areas function --------------------------------------------------

# Extracted areas
extracted_areas <- tabulapdf::extract_areas(
  file = file,
  pages = pages,
  method = "decide",
  output = "matrix",
  copy = TRUE
)

# Loop and Save ---------------------------------------------------------

# Loop over the list and write each matrix to a CSV file
for (i in seq_along(extracted_areas)) {
  write.csv(
    extracted_areas[[i]],
    file = paste0(test, "_", i, ".csv"),
    row.names = FALSE
  )
}

test <- "wais5_index"
# Save the entire list to an R data file
saveRDS(extracted_areas, file = paste0(test, "_extracted_areas.rds"))
# Load the list from the R data file (if necessary)
extracted_areas <- readRDS(paste0(test, "_extracted_areas.rds"))

# Check the extracted areas
str(extracted_areas)

# To convert a single test using extracted areas into a single data frame
df <- extracted_areas[[1]]
df2 <- extracted_areas[[2]]
df <- data.frame(df)
df2 <- data.frame(df2)
df <- rbind(df, df2)

# Remove asterick from the first column (wisc5)
df[, 2] <- gsub("\\*", "", df[, 2])

# Remove parentheses (wais5 subtests)
library(dplyr)
library(stringr)

df <- df %>% mutate(X2 = str_remove_all(X2, "\\(|\\)"))

# For WAIS-5 Indexes, WISC-V, WAIS-IV
# Merge Columns 1-2 and add parentheses
library(tidyverse)
df <- df |>
  dplyr::mutate(col2_paren = paste0("(", df[[2]], ")")) |>
  tidyr::unite("scale", 1, col2_paren, sep = " ", remove = TRUE)

# FUNCTIONS ---------------------------------------

# Function to extract columns by position---------------------------

library(dplyr)

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

# Step 2 (Optional): Convert 'raw score' 'score' and 'percentile' to numeric
df <- df |>
  mutate(
    raw_score = as.numeric(raw_score),
    score = as.numeric(score),
    percentile = as.numeric(percentile)
  )

# Step 3: Remove rows where 'score' or 'percentile' are missing
df <- df |> filter(!is.na(score) & !is.na(percentile))

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
  df$ci_95[i] <- paste0(
    ci_values["lower_ci_95"],
    " - ",
    ci_values["upper_ci_95"]
  )
}

df <- df |>
  dplyr::select(-c(true_score, ci_lo, ci_hi)) |>
  dplyr::relocate(ci_95, .after = score)

# Lookup Table Match ------------------------------------------------------

# Load the lookup table
lookup_table <- readr::read_csv("~/reports/neuropsych_lookup_table.csv")

# Merge the data with the lookup table
test <- "wais5"

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

# Write out final csv --------------------------------------------------

test <- "wais5_index"
readr::write_excel_csv(
  df,
  here::here("data", "csv", paste0(test, ".csv")),
  col_names = TRUE
)


# Write to "g2.csv" file --------------------------------------------------

has_headers <- function(file_path) {
  if (!file.exists(file_path)) {
    return(FALSE) # File doesn't exist, headers are needed
  }
  # Check if the file has at least one line (header)
  return(length(readLines(file_path, n = 1)) > 0)
}

csv_file <- df
g <- "g2"
file_path <- here::here("data", paste0(g, ".csv"))

readr::write_excel_csv(
  csv_file,
  file_path,
  append = TRUE,
  col_names = !has_headers(file_path),
  quote = "all"
)
