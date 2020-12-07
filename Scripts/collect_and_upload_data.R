#!/usr/bin/env Rscript
library(tidyverse)
library(readxl)
library(httr)

scans_dir = commandArgs(trailingOnly=TRUE)[[1]]

## test if there is at least one argument: if not, return an error
if(!dir.exists(scans_dir))
  stop(str_c("Directory not found: ", scans_dir))

# All these fields are Boolean and no string and hence need "True" / "False" rather than "y" / "n"
boolean_fields <- c( "flu_vaccination", "chronic_kidney_condition", "diabetes", "cancer_last_two_years",
                     "asthma", "other_lung_problems", "high_blood_pressure", "other_cardiovascular", "work_in_medical_field",
                     "work_with_kids", "no_further_research", "consent" )

# Authentication for server
auth <- authenticate( "herbstk", "tomate7654" )

db_mappings <- read_xlsx("~/AutoOMR/Templates/db_mappings_noagegroup.xlsx")
meta <- str_split_fixed(db_mappings$answer_id, "_", 3)
db_mappings$q_type <- meta[,1]
db_mappings$q_id <- meta[,2]
db_mappings$q_nr <- meta[,3] %>% as.numeric()
db_mappings <- db_mappings %>%
  mutate(q_id = as.numeric(str_extract(q_id, "\\d+")))

COLS <- c("answer_id", "state", "fill", "bgr")
COLS_TYPES <- "cddd"

collect_scan_results <- function(path){
  processed_files <- list.files(path, pattern = "\\.tsv", recursive = TRUE, full.names = TRUE)
  processed_files <- processed_files[!str_detect(processed_files, "results.tsv")]
  
  scan_results <- lapply(processed_files, function(.){
    ret <- read_tsv(., col_names = COLS, col_types = COLS_TYPES)
    meta <- str_match(., "/([0-9]+)-([1-3])\\.tsv$")
    ret$filename <- .
    ret$household_id <- meta[1,2]
    ret$page <- as.numeric(meta[1,3])
    answer_ids <- str_split_fixed(ret$answer_id, "_", 4)
    ret$q_type <- answer_ids[,1]
    ret$q_id <- answer_ids[,2]
    ret$q_nr <- as.numeric(answer_ids[,3])
    ret$q_option <- answer_ids[,4]
    ret
  }) %>%
    bind_rows() %>%
    mutate(q_id = as.numeric(str_extract(q_id, "\\d+")))
  scan_results <- db_mappings %>% 
    select(page, q_type, q_id, q_nr, map_db) %>%
    left_join(scan_results, ., by = c("page", "q_type", "q_id", "q_nr")) %>%
    arrange(page, household_id, q_id, q_nr, q_option)
  return(scan_results)
}

# helper function to return the smallest digit of a concatenated string of digits
min_digit <- function(x) {
  x <- sapply(str_split(x, ""), function(y){
    if(length(y) > 0 & all(str_detect(y, "\\d"))){
      return(as.character(min(as.numeric(y))))
    } else {
      return(NA_character_)
    }
  })
  return(x)
}
  
aggregate_answers <- function(scan_results){
  # assume we ar only handling with-consent cases
  consent <- scan_results %>% 
    group_by(household_id) %>%
    summarise(map_db = "consent", page = 3, q_id = 15, q_nr = 0, answer = "y" )
  
  ## logic for handling new template version
  scan_results <- scan_results %>%
    group_by(household_id) %>%
    mutate(q_option = if_else(
      state[answer_id == "CB_templateversion_0"] <= 0 & q_id == 2 & q_option == "yes", "", q_option), # for old template version, change answers accordingly
      q_option = if_else(
        state[answer_id == "CB_templateversion_0"] <= 0 & q_id == 2 & q_option == "no", "yes", q_option)) %>% 
    ungroup() %>%
    filter(!(q_id == 2 & q_option == ""))
  
  scan_results_out <- scan_results %>%
    filter(!is.na(map_db)) %>%
    mutate(q_option = recode(q_option, "yes" = "y", "no" = "n", "often" = "o")) %>%
    mutate( answer = case_when(state == 1 ~ q_option,
                               state == -1 ~ "?",
                               TRUE ~ "") ) %>%
    group_by(page, household_id, q_id, q_nr, map_db) %>%
    summarise(answer = str_c(answer, collapse = "")) %>%
    ungroup() %>%
    mutate(answer = recode(answer, "oy" = "o", "yo" = "o", "no" = "o", "on" = "o"),
           answer = case_when((q_id %in% c(2, 7, 14) & answer == "") ~ "n",
                              q_id == 13 & answer != "" ~ min_digit(answer),  # questions asked for the highest degree (lowest rank)
                              answer %in% c("", "yn", "ny") | str_detect(answer, "\\?") ~ "u",                            # ambiguous answers are undefined
                              TRUE ~ answer),
           answer = if_else((q_id == 2 & q_nr == 17 & answer %in% c("n", "?", "other2")), "u", answer),
           answer = if_else((q_id == 5 & q_nr == 0 & answer %in% c("n", "?", "other2")), "u", answer),
           answer = if_else((q_id == 6 & q_nr == 0 & str_detect(answer, "other")), "u", answer)) %>%
    bind_rows(., consent)
  return(scan_results_out)
}

prepare_upload <- function(result){
  ## Sveta's code:
  tbl <- result %>% filter(answer != "u") %>%
    # Remove question IDs, we don't need them  
    select( -page, -q_id, -q_nr ) %>%
    # Turn into wide table: one row per questionnaire, one column per field
    pivot_wider( names_from=map_db, values_from=answer ) %>%
    # Household IDs need leading zeroes  
    # mutate_at( vars(household_id), ~ sprintf( "%05d", . ) ) %>%
    filter(!is.na(household_id)) %>%
    # Change encoding for boolean fields (see above)
    mutate( across(any_of(boolean_fields), ~ c( n="False", y="True")[.] ))
  return(tbl)
}

upload_results <- function(tbl){
  tbl$needs_validation <- "True"
  # Go through all rows, send a POST request for each
  for( i in 1:nrow(tbl) ) {
    # Turn row into list of fields, for POST request body
    lapply( as.list( tbl[i,] ), unname ) -> body
    for(key in names(body))
      if(is.na(body[[key]])) body[key] <- NULL
      # Send POST request using function from httr package
      POST( "https://virusfinder.de/de/add_questionnaire",
            auth, body=body ) -> result
      # Print result. To do: inspect results to see whether we always
      # get status 201 (created)
      print( str_c( i, ":", body$household_id, http_status(result)$message, content(result, as = "text"), sep = "  "  ) )
  }
}

print(str_c("Processing: ", scans_dir))
result <- collect_scan_results(scans_dir)
## filter out all household_ids missing a page
result <- result %>%
  group_by(household_id) %>%
  mutate(has_all_pages = setequal(page, 1:3))
print("---The following household_ids contain missing pages---")
result %>% filter(!has_all_pages) %>% count(household_id) %>% print
result <- result %>% filter(has_all_pages)
result %>% write_tsv(file.path(scans_dir, "gathered_results.tsv"))
result <- aggregate_answers(result)
## double check multiple answers
result %>% filter(str_length(answer) > 1) %>% print
result %>% write_tsv(file.path(scans_dir, "aggregated_results.tsv"))
tbl <- prepare_upload(result)
upload_results(tbl)
