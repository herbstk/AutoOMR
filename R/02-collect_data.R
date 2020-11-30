library(tidyverse)
library(readxl)

db_mappings <- read_xlsx("~/AutoOMR/Templates/db_mappings_noagegroup.xlsx")
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
    mutate(q_id = as.numeric(str_extract(q_id, "\\d+")))
  scan_results <- db_mappings %>% 
    select(page, q_type, q_id, q_nr, map_db) %>%
    left_join(scan_results, ., by = c("page", "q_type", "q_id", "q_nr")) %>%
    select(household_id, page, answer_id, starts_with("q_"), map_db, state) %>%
    arrange(page, household_id, q_id, q_nr, q_option)
  return(scan_results)
}

aggregate_answers <- function(scan_results){
  # assume we ar only handling with-consent cases
  consent <- scan_results %>% 
    group_by(household_id) %>%
    summarise(map_db = "consent", q_id = 15, answer = "y")
  
  scan_results_out <- scan_results %>%
    filter(!is.na(map_db)) %>%
    mutate(q_option = recode(q_option, "yes" = "y", "no" = "n", "often" = "o")) %>%
    mutate( answer = case_when(state == 1 ~ q_option,
                               state == -1 ~ "?",
                               TRUE ~ "") ) %>%
    group_by(page, household_id, q_id, q_nr, map_db) %>%
    summarise(answer = str_c(answer, collapse = "")) %>%
    ungroup() %>%
    mutate(answer = recode(answer, "oy" = "o", "yo" = "o"),
           answer = if_else(answer == "", "n", answer)) %>%
    bind_rows(., consent)
    return(scan_results_out)
}

for(scans_dir in list.dirs("./Scans_processed", full.names = TRUE, recursive = FALSE)){
    print(str_c("Processing: ", scans_dir))
    result <- collect_scan_results(scans_dir)
    result <- aggregate_answers(result)
    # double check multiple answers
    result %>% filter(str_length(answer) > 1) %>% print
  
    result %>% write_tsv(file.path(scans_dir, "aggregated_results.tsv"))
    result %>% mutate(curated = "") %>% write_tsv(file.path(scans_dir, "aggregated_results_curated.tsv"))
    
    # copy scan files for curation
    curated_dir <- file.path(scans_dir, "Curated")
    if(!dir.exists(curated_dir)){
      dir.create(curated_dir)
      curated_dir_pg1 <- file.path(curated_dir, "page1")
      if(!dir.exists(curated_dir_pg1)) dir.create(curated_dir_pg1)
      scan_files_pg1 <- list.files(scans_dir, pattern = "1(_debug)?\\.png", recursive = TRUE, full.names = TRUE)
      print(file.copy(scan_files_pg1, curated_dir_pg1))
      curated_dir_pg2 <- file.path(curated_dir, "page2")
      if(!dir.exists(curated_dir_pg2)) dir.create(curated_dir_pg2)
      scan_files_pg2 <- list.files(scans_dir, pattern = "2(_debug)?\\.png", recursive = TRUE, full.names = TRUE)
      print(file.copy(scan_files_pg2, curated_dir_pg2))
    } else {
      print(str_c("Directory ", curated_dir, " already exists; please remove."))
    }
}
