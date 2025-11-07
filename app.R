library(shiny)
library(shinydashboard)
library(tidyverse)
library(tabulapdf)
library(neuro2)
library(hablar)
library(here)
library(DT)

# After successful install you can snapshot: renv::snapshot()
# UPLOAD MODULE - UI
upload_module_ui <- function(id) {
  ns <- NS(id)
  fluidRow(column(
    6,
    fileInput(ns("file"), "Upload PDF File", accept = c(".pdf")),
    selectInput(
      ns("test"),
      "Test",
      choices = c("wrat5", "wrat4"),
      selected = "wrat5"
    ),
    selectInput(
      ns("test_name"),
      "Test Name",
      choices = c("WRAT-5", "WRAT-4"),
      selected = "WRAT-5"
    ),
    numericInput(ns("pages"), "Pages to Scan/Extract", value = 10)
  ))
}

# UPLOAD MODULE - SERVER
upload_module_server <- function(id) {
  moduleServer(id, function(input, output, session) {
    return(reactive({
      req(input$file)
      list(
        file = input$file$datapath,
        test = input$test,
        test_name = input$test_name,
        pages = input$pages
      )
    }))
  })
}

# TABLE CONFIG MODULE - UI
table_config_module_ui <- function(id) {
  ns <- NS(id)
  fluidRow(column(
    6,
    selectInput(
      ns("table"),
      "Select Tables",
      selected = c(
        "Math Computation",
        "Spelling",
        "Word Reading",
        "Sentence Comprehension",
        "Reading Composite"
      ),
      choices = c(
        "Math Computation",
        "Spelling",
        "Word Reading",
        "Sentence Comprehension",
        "Reading Composite"
      ),
      multiple = TRUE
    ),
    selectInput(
      ns("colnames"),
      "Select Columns",
      selected = c(
        "scale",
        "raw_score",
        "score",
        "ci_95",
        "percentile",
        "category",
        "grade_equiv",
        "gsv"
      ),
      choices = c(
        "scale",
        "raw_score",
        "score",
        "ci_95",
        "percentile",
        "category",
        "grade_equiv",
        "nce",
        "gsv"
      ),
      multiple = TRUE
    ),
    selectInput(
      ns("keep"),
      "Variables to Keep",
      selected = c("scale", "raw_score", "score", "percentile", "ci_95"),
      choices = c("scale", "raw_score", "score", "percentile", "ci_95"),
      multiple = TRUE
    )
  ))
}

# TABLE CONFIG MODULE - SERVER
table_config_module_server <- function(id) {
  moduleServer(id, function(input, output, session) {
    return(reactive({
      req(input$table)
      list(table = input$table, colnames = input$colnames, keep = input$keep)
    }))
  })
}

# CORRECTED UI
ui <- dashboardPage(
  skin = "blue",
  header = dashboardHeader(title = "WRAT-5 Table Processor"),
  sidebar = dashboardSidebar(sidebarMenu(
    menuItem("Upload & Configure", tabName = "upload", icon = icon("upload")),
    menuItem("Results", tabName = "results", icon = icon("table"))
  )),
  body = dashboardBody(tabItems(
    tabItem(
      tabName = "upload",
      upload_module_ui("upload1"),
      table_config_module_ui("config1")
    ),
    tabItem(
      tabName = "results",
      verbatimTextOutput("status"),
      DTOutput("processed_data"),
      downloadButton("download_csv", "Download CSV")
    )
  ))
)

# CORRECTED SERVER
server <- function(input, output, session) {
  # Initialize modules properly
  upload_data <- upload_module_server("upload1")
  config_data <- table_config_module_server("config1")

  # Process data with proper error handling
  processed_data <- reactive({
    req(upload_data(), config_data())

    # Extract tables
    plucked_tables <- tabulapdf::extract_tables(
      file = upload_data()$file,
      pages = upload_data()$pages,
      method = "stream",
      output = "matrix"
    )
    # # Extract tables
    # plucked_tables <- tabulapdf::extract_areas(
    #   file = upload_data()$file,
    #   pages = upload_data()$pages,
    #   method = "stream",
    #   output = "matrix",
    #   widget = "native" #"shiny"
    # )

    # Process first table
    df <- as.data.frame(plucked_tables[[1]])

    # Handle column naming safely
    if (length(config_data()$colnames) == ncol(df)) {
      colnames(df) <- config_data()$colnames
    }

    # Convert numeric columns
    to_double <- c("raw_score", "score", "percentile")
    to_double <- to_double[to_double %in% colnames(df)]
    if (length(to_double) > 0) {
      df[to_double] <- lapply(df[to_double], function(x) {
        as.numeric(as.character(x))
      })
    }

    # Keep selected columns
    keep_cols <- config_data()$keep[config_data()$keep %in% colnames(df)]
    if (length(keep_cols) > 0) {
      df <- dplyr::select(df, all_of(keep_cols))
    }

    # Add metadata and process with neuro2
    if ("scale" %in% colnames(df)) {
      df <- df |>
        neuro2::gpluck_make_columns(
          test = upload_data()$test,
          test_name = upload_data()$test_name,
          range = NA_character_,
          domain = "Academic Skills",
          subdomain = NA_character_,
          narrow = NA_character_,
          pass = NA_character_,
          verbal = NA_character_,
          timed = NA_character_,
          test_type = "npsych_test",
          score_type = "standard_score",
          absort = NA_character_,
          description = NA_character_,
          result = NA_character_
        ) |>
        neuro2::gpluck_make_score_ranges(test_type = "npsych_test")
    }

    return(df)
  })

  # Outputs
  output$status <- renderText({
    paste("Processed", nrow(processed_data()), "records")
  })

  output$processed_data <- renderDT({
    req(processed_data())
    datatable(
      processed_data(),
      options = list(pageLength = 5, autoWidth = TRUE)
    )
  })

  output$download_csv <- downloadHandler(
    filename = function() paste0("WRAT5_results_", Sys.Date(), ".csv"),
    content = function(file) {
      write.csv(processed_data(), file, row.names = FALSE)
    }
  )
}

shinyApp(ui, server)
