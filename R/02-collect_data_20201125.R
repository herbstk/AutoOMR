library(tidyverse)
library(readxl)

db_mappings <- read_xlsx("~/Desktop/Fragebögen/AutoOMR/Templates/db_mappings_noagegroup.xlsx")
meta <- str_split_fixed(db_mappings$answer_id, "_", 3)
db_mappings$q_type <- meta[,1]
db_mappings$q_id <- meta[,2]
db_mappings$q_nr <- meta[,3] %>% as.numeric()
db_mappings <- db_mappings %>%
  mutate(q_id = as.numeric(str_extract(q_id, "\\d+")))

COLS <- c("answer_id", "state", "fill_bgr", "bgr")
COLS_TYPES <- "cddd"

collect_scan_results <- function(path){
  processed_files <- list.files(path, pattern = "\\.tsv", recursive = TRUE, full.names = TRUE)
  processed_files <- processed_files[!str_detect(processed_files, "aggregated_results")]
  
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
    mutate(q_id = as.numeric(str_extract(q_id, "\\d+"))) %>%
    arrange(page, household_id, q_id, desc(q_option))
  scan_results <- db_mappings %>% 
    select(page, q_type, q_id, q_nr, map_db) %>%
    left_join(scan_results, ., by = c("page", "q_type", "q_id", "q_nr")) %>%
    select(household_id, page, answer_id, starts_with("q_"), map_db, state)
  return(scan_results)
}

## collect remaining files from yesterday (20201124)
scan_results <- lapply(
  c("/media/konrad/BD55-C3BA/Virus-Finder_Scans/20201124/Scans_processed/Batch1/",
    "/media/konrad/BD55-C3BA/Virus-Finder_Scans/20201124/Scans_processed/Batch2/"),
  function(.){
    collect_scan_results(.)
  }) %>% bind_rows() %>%
  arrange(page, household_id, q_id, desc(q_option))
# how many yesterday alltogether
scan_results %>% summarise(n_distinct(household_id))
curated_results_yesterday <- read_tsv("/media/konrad/BD55-C3BA/Virus-Finder_Scans/20201124-aggregated_results_curated.tsv") %>%
  mutate(household_id = sprintf( "%05d", household_id ) )
# how many yesterday
curated_results_yesterday %>% summarise(n_distinct(household_id))
scan_results <- scan_results %>% anti_join(., curated_results_yesterday, by = "household_id")
# how many remaining
scan_results %>% summarise(n_distinct(household_id))

## write two versions
scan_results %>% write_tsv("/media/konrad/BD55-C3BA/Virus-Finder_Scans/20201125/aggregated_results-20201124remaining.tsv")
scan_results %>% mutate(curated = "") %>% write_tsv("/media/konrad/BD55-C3BA/Virus-Finder_Scans/20201125/aggregated_results-20201124remaining_curated.tsv")
