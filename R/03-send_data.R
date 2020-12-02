library(tidyverse)
library(readxl)

# process data and upload
COLS <- c("answer_id", "state", "fill_bgr", "bgr")
# COLS_TYPES <- "ddccddccdc"
COLS_TYPES <- c("numeric", "numeric", "numeric", "numeric", "text", "text", "text")

curated_results <- lapply(c("Scans_processed/Batch1/aggregated_results_curated.xlsx",
                            "Scans_processed/Batch2/aggregated_results_curated.xlsx"
                                 ),
                               function(.){
                                 ret <- read_xlsx(., col_types = COLS_TYPES, na = "NA")
                                 ret
                               }) %>% bind_rows() %>%
  arrange(page, household_id, q_id, q_nr) %>%
  mutate(answer = if_else(is.na(curated), answer, curated)) %>%
  select(-curated) %>%
  write_tsv("20201127-aggregated_results_curated.tsv")

## if no information is given make freetext answer fields undefined
curated_results_forDB <- curated_results %>%
  mutate(answer = if_else((q_id == 2 & q_nr == 17 & answer %in% c("n", "?", "other2")), "u", answer),
         answer = if_else((q_id == 5 & q_nr == 0 & answer %in% c("n", "?")), "u", answer))

# double check multiple answers
curated_results_forDB %>% filter(str_length(answer) > 1)

## Sveta's code:
library(httr)

# All these fields are Boolean and no string and hence need "True" / "False" rather than "y" / "n"
boolean_fields <- c( "flu_vaccination", "chronic_kidney_condition", "diabetes", "cancer_last_two_years",
                     "asthma", "other_lung_problems", "high_blood_pressure", "other_cardiovascular", "work_in_medical_field",
                     "work_with_kids", "no_further_research", "consent" )

# Take file from Konrad
# read_tsv("~/tmp/20201122_23-aggregated_results_curated.tsv" ) %>%
curated_results_forDB %>% filter(answer != "u") %>%
  # Remove question IDs, we don't need them  
  select( -page, -q_id, -q_nr ) %>%
  # Turn into wide table: one row per questionnaire, one column per field
  pivot_wider( names_from=map_db, values_from=answer ) %>%
  # Household IDs need leading zeroes  
  mutate_at( vars(household_id), ~ sprintf( "%05d", . ) ) %>%
  # Change encoding for boolean fields (see above)
  mutate_at( vars(boolean_fields), ~ c( n="False", y="True")[.] ) -> tbl

# Authentication for server
auth <- authenticate( "herbstk", "PASSWORD" )

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

