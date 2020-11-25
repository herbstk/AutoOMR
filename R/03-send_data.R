
## Sveta's code:
library(httr)

# All these fields are Boolean and no string and hence need "True" / "False" rather than "y" / "n"
boolean_fields <- c( "flu_vaccination", "chronic_kidney_condition", "diabetes", "cancer_last_two_years",
                     "asthma", "other_lung_problems", "high_blood_pressure", "other_cardiovascular", "work_in_medical_field",
                     "work_with_kids", "no_further_research", "consent" )

# Take file from Konrad
# read_tsv("~/tmp/20201122_23-aggregated_results_curated.tsv" ) %>%
curated_results_out %>% filter(answer != "u") %>%
  # Remove question IDs, we don't need them  
  select( -q_id ) %>%
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
  # Send POST request using function from httr package
  POST( "https://virusfinder.de/de/add_questionnaire", 
        auth, body=body ) -> result
  # Print result. To do: inspect results to see whether we always 
  # get status 201 (created)
  print( str_c( body$household_id, "  ", http_status(result)$message ) )
  
} 

