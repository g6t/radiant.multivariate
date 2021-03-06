ff_method <- c("Principal components" = "PCA", "Maximum Likelihood" = "maxlik")
ff_rotation <- c("None" = "none", "Varimax" = "varimax", "Quartimax" = "quartimax",
                 "Equamax" = "equamax", "Promax" = "promax",
                 "Oblimin" = "oblimin", "Simplimax" = "simplimax")

## list of function arguments
ff_args <- as.list(formals(full_factor))

## list of function inputs selected by user
ff_inputs <- reactive({
  ff_args$data_filter <- if (input$show_filter) input$data_filter else ""
  ff_args$dataset <- input$dataset
  ## loop needed because reactive values don't allow single bracket indexing
  for (i in r_drop(names(ff_args)))
    ff_args[[i]] <- input[[paste0("ff_",i)]]
  ff_args
})

###############################
# Factor analysis
###############################
output$ui_ff_vars <- renderUI({

  isNum <- "numeric" == .getclass() | "integer" == .getclass()
  vars <- varnames()[isNum]
  selectInput(inputId = "ff_vars", label = "Variables:", choices = vars,
    selected = state_multiple("ff_vars", vars, input$pf_vars),
    multiple = TRUE, size = min(10, length(vars)), selectize = FALSE)
})

output$ui_full_factor <- renderUI({
  req(input$dataset)
  tagList(
    wellPanel(
      actionButton("ff_run", "Estimate", width = "100%")
    ),
    wellPanel(
      uiOutput("ui_ff_vars"),
      selectInput("ff_method", label = "Method:", choices = ff_method,
        selected = state_single("ff_method", ff_method, "PCA")),
      tags$table(
        tags$td(numericInput("ff_nr_fact", label = "Nr. of factors:", min = 1, value = state_init('ff_nr_fact',1))),
        tags$td(numericInput("ff_cutoff", label = "Cutt-off", min = 0, max = 1, value = state_init('ff_cutoff',0), step = .05, width = "117px"))
      ),
      conditionalPanel(condition = "input.tabs_full_factor == 'Summary'",
        checkboxInput("ff_fsort", "Sort", value = state_init("ff_fsort",FALSE))
      ),
      selectInput("ff_rotation", label = "rotation:", ff_rotation,
        selected = state_single("ff_rotation", ff_rotation, "varimax")),
      conditionalPanel(condition = "input.ff_vars != null",
        tags$table(
          tags$td(textInput("ff_store_name", "Store scores:", state_init("ff_store_name","factor"))),
          tags$td(actionButton("ff_store", "Store"), style="padding-top:30px;")
        )
      )
    ),
    help_and_report(modal_title = "Factor",
                    fun_name = "full_factor",
                    help_file = inclMD(file.path(getOption("radiant.path.multivariate"),"app/tools/help/full_factor.md")))
  )
})

ff_plot <- reactive({
  nrFact <- min(input$ff_nr_fact, length(input$ff_vars))
  nrPlots <- (nrFact * (nrFact - 1)) / 2

  plot_height <- plot_width <- 350
  if (nrPlots > 2)
    plot_height <- 350 * ceiling(nrPlots/2)

  if (nrPlots > 1)
    plot_width <- 700

  list(plot_width = plot_width, plot_height = plot_height)
})

ff_plot_width <- function()
  ff_plot() %>% { if (is.list(.)) .$plot_width else 650 }

ff_plot_height <- function()
  ff_plot() %>% { if (is.list(.)) .$plot_height else 400 }

output$full_factor <- renderUI({

    register_print_output("summary_full_factor", ".summary_full_factor")
    register_plot_output("plot_full_factor", ".plot_full_factor",
                          width_fun = "ff_plot_width",
                          height_fun = "ff_plot_height")

    ff_output_panels <- tabsetPanel(
      id = "tabs_full_factor",
      tabPanel("Summary",
        downloadLink("dl_ff_loadings", "", class = "fa fa-download alignright"), br(),
        verbatimTextOutput("summary_full_factor")),
      tabPanel("Plot",
        plot_downloader("full_factor", height = ff_plot_height),
        plotOutput("plot_full_factor", height = "100%"))
    )

    stat_tab_panel(menu = "Multivariate > Factor",
                   tool = "Factor",
                   tool_ui = "ui_full_factor",
                   output_panels = ff_output_panels)
})

.ff_available <- reactive({
  if (not_available(input$ff_vars))
    return("This analysis requires multiple variables of type numeric or integer.\nIf these variables are not available please select another dataset.\n\n" %>% suggest_data("toothpaste"))
  if (length(input$ff_vars) < 2) return("Please select two or more variables")
  if (not_pressed(input$ff_run)) return("** Press the Estimate button to generate factor analysis results **")

  "available"
})

.full_factor <- eventReactive(input$ff_run, {
  withProgress(message = 'Estimating factor solution', value = 1,
    do.call(full_factor, ff_inputs())
  )
})

.summary_full_factor <- reactive({
  if (.ff_available() != "available") return(.ff_available())
  if (is_not(input$ff_nr_fact)) return("Number of factors should be >= 1.")
  summary(.full_factor(), cutoff = input$ff_cutoff, fsort = input$ff_fsort)
})

.plot_full_factor <- reactive({
  if (.ff_available() != "available") return(.ff_available())
  if (is_not(input$ff_nr_fact) || input$ff_nr_fact < 2) return("Plot requires 2 or more factors.\nChange the number of factors and re-estimate")
  plot(.full_factor(), shiny = TRUE)
})

observeEvent(input$full_factor_report, {
  outputs <- c("summary","plot")
  inp_out <- list(list(cutoff = input$ff_cutoff, fsort = input$ff_fsort, dec = 2), list(custom = FALSE))
  xcmd = paste0("# store(result, name = \"", input$ff_store_name, "\")\n# clean_loadings(result$floadings, cutoff = ", input$ff_cutoff, ", fsort = ", input$ff_fsort, ", dec = 8) %>% write.csv(file = \"~/loadings.csv\")")
  update_report(inp_main = clean_args(ff_inputs(), ff_args),
                fun_name = "full_factor",
                inp_out = inp_out,
                fig.width = ff_plot_width(),
                fig.height = ff_plot_height(),
                xcmd = xcmd)
})

## save factor loadings when download button is pressed
output$dl_ff_loadings <- downloadHandler(
  filename = function() { "loadings.csv" },
  content = function(file) {
    if (pressed(input$ff_run)) {
      .full_factor() %>%
        { if (is.list(.)) .$floadings else return() } %>%
        clean_loadings(input$ff_cutoff, input$ff_fsort) %>%
        write.csv(file = file)
    } else {
      cat("No output available. Press the Estimate button to generate the factor analysis results", file = file)
    }
  }
)

## store factor scores
observeEvent(input$ff_store, {
  if (pressed(input$ff_run)) {
    .full_factor() %>% { if (!is.character(.)) store(., name = input$ff_store_name) }
  }
})
