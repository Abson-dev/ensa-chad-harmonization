# Publish the app to Posit Connect Cloud as PRIVATE content.
#
# Run in an interactive R session (RStudio, Positron, or R in a terminal) from the app/ folder:
#   source("deploy_posit.R")
#
# First time: a browser window opens to log in to Posit Connect Cloud and link the account.
# Re-run after every data update (prepare_app_data.R) to update the same app.
#
# The app shows regional estimates (aggregates only, no household data): it is deployed with
# visibility "private". Private content needs an Enhanced, Advanced or Enterprise Connect Cloud
# plan: on Free / Basic plans every app is public, so check the plan before running this.

if (!requireNamespace("rsconnect", quietly = TRUE)) {
  install.packages("rsconnect", repos = "https://cloud.r-project.org")
}

app_dir <- normalizePath(".", winslash = "/")
if (!file.exists(file.path(app_dir, "app.R"))) {
  stop("Run this script from the app/ folder (the one containing app.R).")
}
if (!file.exists(file.path(app_dir, "data", "manifest.json"))) {
  stop("app/data is missing: run Rscript prepare_app_data.R first.")
}

# Link the Posit Connect Cloud account once (opens the browser)
is_cloud <- function(acc) grepl("posit.cloud", acc$server, fixed = TRUE)
acc <- rsconnect::accounts()
if (is.null(acc) || !any(is_cloud(acc))) {
  rsconnect::connectCloudUser()
  acc <- rsconnect::accounts()
}
acc <- acc[is_cloud(acc), , drop = FALSE]
if (nrow(acc) > 1) {
  message("Several Connect Cloud accounts: using ", acc$name[1], " (edit deploy_posit.R to choose)")
}

# Only what the app needs: no tests, no data-preparation or launcher scripts
files <- c("app.R",
           file.path("R", list.files(file.path(app_dir, "R"))),
           file.path("www", list.files(file.path(app_dir, "www"), recursive = TRUE)),
           file.path("data", list.files(file.path(app_dir, "data"), recursive = TRUE)))

rsconnect::deployApp(
  appDir = app_dir,
  appFiles = files,
  appName = "ensa-chad-explorer",
  appTitle = "ENSA Chad harmonisation explorer",
  appVisibility = "private",
  account = acc$name[1],
  server = acc$server[1],
  launch.browser = TRUE
)

message("\nDeployed as private content. To give access, open the app in Connect Cloud > Share:\n",
        "  - Advanced / Enterprise plan: add John by email (he logs in);\n",
        "  - Enhanced plan: turn on Private link sharing and send him the link.")
