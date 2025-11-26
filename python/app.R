# Neuropsychological Test Data Processor Shiny App

# This Shiny application allows users to upload a raw assessment results
# CSV file along with a neuropsychological lookup table.  It parses
# each neuropsychological test domain contained within the assessment
# file, merges the data with the lookup table to enrich the results
# with metadata, computes missing percentile ranks and descriptive
# performance ranges based on the type of score (e.g., standard scores
# or scaled scores) and finally exposes the processed data for
# download.  The resulting output follows the same column structure
# used in the example test files (e.g., wms4.csv, wais5.csv, dkefs.csv).

library(shiny)
library(dplyr)
library(readr)

# Compute the percentile given a numeric score and the score type.
# Uses normal distribution assumptions common to neuropsychological
# assessments. If the score or score type is missing or unsupported
# the function returns NA_real_.
compute_percentile <- function(score, score_type) {
    if (is.na(score) || score == "")
        return(NA_real_)
    score_num <- suppressWarnings(as.numeric(score))
    if (is.na(score_num))
        return(NA_real_)
    if (score_type == "standard_score") {
        return(pnorm((score_num - 100) / 15) * 100)
    }
    if (score_type == "scaled_score") {
        return(pnorm((score_num - 10) / 3) * 100)
    }
    if (score_type == "t_score") {
        return(pnorm((score_num - 50) / 10) * 100)
    }
    if (score_type == "z_score") {
        return(pnorm(score_num) * 100)
    }
    return(NA_real_)
}

# Given a percentile (0–100), return a descriptive range string.  The
# thresholds mirror common interpretations used in many cognitive and
# achievement batteries.  Missing or NA percentiles return NA.
compute_range <- function(percentile) {
    if (is.na(percentile))
        return(NA_character_)
    if (percentile >= 98)      return("Exceptionally High")
    if (percentile >= 91)      return("Above Average")
    if (percentile >= 75)      return("High Average")
    if (percentile >= 25)      return("Average")
    if (percentile >= 9)       return("Low Average")
    if (percentile >= 2)       return("Below Average")
    return("Exceptionally Low")
}

# Main parser that walks through the uploaded assessment results file
# and constructs a tidy data frame for each scale/test encountered.
parse_assessment <- function(df_raw, lookup) {
    results <- list()
    current_section <- NULL
    # Coerce to character to avoid factors
    df_raw <- as.data.frame(lapply(df_raw, as.character), stringsAsFactors = FALSE)
    n_rows <- nrow(df_raw)
    row_idx <- 1
    while (row_idx <= n_rows) {
        row_vals <- df_raw[row_idx, ]
        val0 <- row_vals[[1]]
        # Skip empty rows
        if (is.na(val0) || val0 == "") {
            row_idx <- row_idx + 1
            next
        }
        # Detect section headers and set the active test/test_name
        if (val0 == "WMS-IV Adult Battery Subtest") {
            current_section <- list(test = "wms4", test_name = "WMS-IV")
            row_idx <- row_idx + 1
            next
        }
        if (val0 == "WAIS-IV Composite") {
            current_section <- list(test = "wais4", test_name = "WAIS-IV", composite = TRUE)
            row_idx <- row_idx + 1
            next
        }
        if (val0 == "WAIS-IV Subtest") {
            current_section <- list(test = "wais4", test_name = "WAIS-IV", composite = FALSE)
            row_idx <- row_idx + 1
            next
        }
        if (val0 == "D-KEFS Color-Word Interference Test") {
            current_section <- list(test = "dkefs", test_name = "D-KEFS")
            row_idx <- row_idx + 1
            next
        }
        if (val0 == "D-KEFS Verbal Fluency Test (Standard)") {
            current_section <- list(test = "dkefs", test_name = "D-KEFS")
            row_idx <- row_idx + 1
            next
        }
        # Ignore other header-like lines (contain keywords but not scores)
        if (grepl("Composite|Subtest|Test", val0, ignore.case = TRUE)) {
            row_idx <- row_idx + 1
            next
        }
        # If we haven't detected a section yet, skip until we do
        if (is.null(current_section)) {
            row_idx <- row_idx + 1
            next
        }
        # Extract common metadata
        test <- current_section$test
        test_name <- current_section$test_name
        composite_section <- !is.null(current_section$composite) && current_section$composite
        scale <- val0
        # Default placeholders
        raw_score <- NA_character_
        score     <- NA_character_
        percentile_raw <- NA_character_
        ci95 <- NA_character_
        score_type_default <- NA_character_
        # WAIS-IV composites: standard score is in column 2, percentile in column 3, CI in column 5
        if (test == "wais4" && composite_section && scale %in% c("Verbal Comprehension", "Perceptual Reasoning", "Working Memory", "Processing Speed", "Full Scale")) {
            score <- row_vals[[2]]
            percentile_raw <- row_vals[[3]]
            # The 5th column, if present, holds the 95% confidence interval
            if (ncol(df_raw) >= 5) {
                ci95 <- row_vals[[5]]
            }
            score_type_default <- "standard_score"
        } else {
            # All other subtests and tasks: raw score then scaled score then percentile
            raw_score <- row_vals[[2]]
            score <- row_vals[[3]]
            percentile_raw <- row_vals[[4]]
            if (ncol(df_raw) >= 5) {
                ci95 <- row_vals[[5]]
            }
            # Most subtests use scaled scores; tasks without a scaled score fall back to raw
            if (!is.na(score) && score != "") {
                score_type_default <- "scaled_score"
            } else {
                score_type_default <- "raw_score"
            }
        }
        # Determine the score type from the lookup when possible
        key <- lookup %>% filter(scale == !!scale, test == !!test, test_name == !!test_name)
        score_type <- if (nrow(key) > 0) key$score_type[1] else score_type_default
        # Convert the raw percentile to numeric
        percentile_val <- suppressWarnings(as.numeric(percentile_raw))
        if (is.na(percentile_val) && !is.na(score_type) && score_type %in% c("standard_score", "scaled_score", "t_score", "z_score")) {
            # Compute percentile from score if missing
            percentile_val <- compute_percentile(score, score_type)
        }
        # Compute descriptive range
        range_desc <- compute_range(percentile_val)
        # Store row
        results[[length(results) + 1]] <- data.frame(
            test = test,
            test_name = test_name,
            scale = scale,
            raw_score = ifelse(raw_score == "", NA_character_, raw_score),
            score = ifelse(score == "", NA_character_, score),
            percentile = ifelse(is.na(percentile_val), NA_real_, round(percentile_val, 2)),
            range = range_desc,
            ci_95 = ifelse(ci95 == "", NA_character_, ci95),
            score_type = score_type,
            stringsAsFactors = FALSE
        )
        row_idx <- row_idx + 1
    }
    if (length(results) == 0) {
        return(NULL)
    }
    result_df <- bind_rows(results)
    # Merge with lookup table to append metadata columns
    merged_df <- result_df %>%
        left_join(lookup, by = c("scale", "test", "test_name", "score_type")) %>%
        mutate(result = "") %>%
        select(
            test, test_name, scale, raw_score, score, percentile, range, ci_95,
            domain, subdomain, narrow, pass, verbal, timed, test_type, score_type,
            absort, description, result
        )
    return(merged_df)
}

ui <- fluidPage(
    titlePanel("Neuropsychological Test Data Processor"),
    sidebarLayout(
        sidebarPanel(
            fileInput("datafile", "Upload assessment results (CSV)", accept = ".csv"),
            fileInput("lookupfile", "Upload neuropsych lookup table (CSV)", accept = ".csv"),
            br(),
            downloadButton("downloadData", "Download processed data")
        ),
        mainPanel(
            h4("Preview of processed data"),
            tableOutput("preview")
        )
    )
)

server <- function(input, output, session) {
    # Reactive expression to read the lookup table
    lookup_table <- reactive({
        req(input$lookupfile)
        read_csv(input$lookupfile$datapath, show_col_types = FALSE)
    })
    # Reactive expression to process the uploaded data
    processed_data <- reactive({
        req(input$datafile, lookup_table())
        raw_df <- read_csv(input$datafile$datapath, col_names = FALSE, show_col_types = FALSE)
        lookup <- lookup_table()
        parse_assessment(raw_df, lookup)
    })
    # Preview table
    output$preview <- renderTable({
        df <- processed_data()
        if (is.null(df)) return(NULL)
        head(df, 10)
    })
    # Download handler
    output$downloadData <- downloadHandler(
        filename = function() {
            paste0("processed_neuropsych_data", Sys.Date(), ".csv")
        },
        content = function(file) {
            df <- processed_data()
            if (!is.null(df)) {
                write_csv(df, file)
            }
        }
    )
}

shinyApp(ui, server)
