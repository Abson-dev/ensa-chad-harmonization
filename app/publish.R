# Publish the app to Posit Connect Cloud, behind the login. From the app/ folder:
#   Rscript publish.R             lists what would be sent; sends nothing
#   Rscript publish.R --publish   sends it (updates ensa-chad-food-security)
#
# Allow-list: only the files listed here leave this computer. It refuses to run without login
# accounts, and if a file looks like household data. With a Connect Cloud plan that allows it the
# app is also private; on a Free or Basic plan its URL is public and the login is what protects it.

args <- commandArgs(trailingOnly = TRUE)
if (!file.exists("app.R")) stop("Run this script from the app/ folder.", call. = FALSE)
APP_NAME <- "ensa-chad-food-security"

required <- c("app.R", ".Renviron", "accounts.sqlite", "data/manifest.json", "data/indicators_by_round.csv")
absent <- required[!file.exists(required)]
if (length(absent)) {
  stop("Missing: ", paste(absent, collapse = ", "), ". Run prepare_app_data.R and manage_accounts.R first.", call. = FALSE)
}
env <- readLines(".Renviron", warn = FALSE)
if (!any(grepl("^ENSA_ACCOUNTS_SECRET=.+", env))) stop("No ENSA_ACCOUNTS_SECRET in .Renviron.", call. = FALSE)
if (any(grepl("ENSA_LOCAL|ENSA_DEMO", env))) stop(".Renviron would disable the login or force a mode.", call. = FALSE)

files <- c(required[1:3], file.path("R", list.files("R", pattern = "\\.R$")),
           file.path("www", list.files("www", recursive = TRUE)), file.path("data", list.files("data", recursive = TRUE)))

forbidden <- grepl("accounts_passwords|\\.sav$|\\.dta$|^output/|ensa_[a-z]+\\.csv$|^demo_data/", files)
if (any(forbidden)) stop("Forbidden file in the upload: ", paste(files[forbidden], collapse = ", "), call. = FALSE)
csvs <- grep("\\.csv$", files, value = TRUE)
household <- csvs[vapply(csvs, function(f) any(c("hh_id", "uuid") %in% strsplit(readLines(f, n = 1, warn = FALSE), ",")[[1]]), TRUE)]
if (length(household)) stop("Household identifiers in: ", paste(household, collapse = ", "), call. = FALSE)

cat(sprintf("Application: %s\nFiles that would be sent (%d):\n", APP_NAME, length(files)))
cat(paste0("  ", files), sep = "\n")
if (!"--publish" %in% args) {
  cat("\nNothing sent. Add --publish to send.\n")
  quit(save = "no")
}

accounts <- rsconnect::accounts()
cloud <- accounts[grepl("posit.cloud", accounts$server, fixed = TRUE), , drop = FALSE]
if (!nrow(cloud)) {
  stop("No Posit Connect Cloud account on this computer. Link it once, in an interactive R session:\n",
       "  rsconnect::connectCloudUser()", call. = FALSE)
}
rsconnect::deployApp(
  appDir = ".", appFiles = files, appName = APP_NAME, appTitle = "ENSA Chad food security",
  account = cloud$name[1], server = cloud$server[1], forceUpdate = TRUE, launch.browser = FALSE, lint = FALSE
)
