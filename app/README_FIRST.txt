ENSA CHAD 2018-2025 - HARMONISATION EXPLORER (R SHINY)
==========================================================================================

This application shows how the 14 rounds of Chad's national food security assessment
(ENSA, Oct 2018 - Oct 2025, 197,947 households) were harmonised into comparable datasets:

  - Overview     : key figures, households per round, the three questionnaire generations;
  - Process      : interactive pipeline diagram (click a step), domains, harmonisation rules;
  - Crosswalk    : the crosswalk workbook made interactive - coverage of 83 concepts in 14
                   rounds, source variable per round, profile of each concept (click a row
                   or a cell), downloads of the workbook and details;
  - Rounds       : fieldwork calendar, sampling weights, date checks;
  - Validation   : recomputed indicators vs the original analysts' scores;
  - Indicators   : FCS groups and rCSI Cadre Harmonise phases by round and region
                   (preliminary harmonised estimates, not official ENSA results);
  - Data issues  : the 20 issues found and how each is handled;
  - About        : method, reproducibility, provenance.

The application contains NO household-level data: only variable metadata, quality checks
and aggregate indicators (region x round cells under 30 households are suppressed).


1. INSTALLATION (once per computer)
------------------------------------------------------------------------------------------
  a) Install R (version 4.3 or newer): https://cran.r-project.org/bin/windows/base/
     Default options. RStudio is not needed.
  b) On the first launch, missing R packages install automatically: a few minutes,
     internet connection needed once (Windows proxy settings are supported).


2. USE
------------------------------------------------------------------------------------------
  a) Unzip the folder you received (do not run it from inside the zip file).
  b) Double-click run_app.bat. The application opens in your web browser.
     Keep the black window open while using the app; close it to stop.

  From RStudio: open app.R and click "Run App".

  Tip: put the folder in a short path without accents or apostrophes,
  for example C:\ENSA\app.

  Every chart can be saved as an image (camera icon at its top right) and every card can
  be enlarged to full screen (icon at its bottom right).


3. TROUBLESHOOTING
------------------------------------------------------------------------------------------
  "R was not found"                 Install R (step 1a), then run run_app.bat again.
  "FAILED to install the packages"  Check the internet connection or proxy, then retry.
                                    As a last resort, in R:
                                    options(download.file.method = "wininet")
                                    install.packages(c("shiny","bslib","bsicons","plotly",
                                      "reactable","visNetwork","shinyWidgets","readxl",
                                      "readr","dplyr","tidyr","jsonlite"))
  "The data folder ... is missing"  The folder was sent without its "data" sub-folder;
                                    ask the sender for the complete folder.
  The browser does not open         Copy the address shown in the black window
                                    (http://127.0.0.1:....) into your browser.
  The window closes immediately     Open a Command Prompt in the folder (type cmd in the
                                    address bar of the folder window, then Enter) and type
                                    run_app.bat to read the message.
