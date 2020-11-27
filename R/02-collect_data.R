library(tidyverse)
library(readxl)

db_mappings <- read_xlsx("~/Desktop/Fragebögen/AutoOMR/Templates/db_mappings_noagegroup.xltx")
meta <- str_split_fixed(db_mappings$answer_id, "_", 3)
db_mappings$q_type <- meta[,1]
db_mappings$q_id <- meta[,2]
db_mappings$q_nr <- meta[,3] %>% as.numeric()
db_mappings <- db_mappings %>%
  mutate(q_id = as.numeric(str_extract(q_id, "\\d+")))

COLS <- c("answer_id", "state", "fill_bgr", "bgr")
COLS_TYPES <- "cddd"

setwd("/media/konrad/BD55-C3BA/Virus-Finder_Scans/20201124/")

processed_dir <- "./Scans_processed/Batch1"

processed_files <- list.files(processed_dir, pattern = "\\.tsv", recursive = TRUE, full.names = TRUE)
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
  arrange(household_id, page, q_id, q_option)
scan_results <- db_mappings %>% 
  select(page, q_type, q_id, q_nr, map_db) %>%
  left_join(scan_results, ., by = c("page", "q_type", "q_id", "q_nr")) %>%
  select(filename, household_id, page, answer_id, starts_with("q_"), map_db, state, fill_bgr, bgr)
## wrte two versions
scan_results %>% write_tsv(file.path(processed_dir, "aggregated_results.tsv"))
scan_results %>% mutate(curated = "") %>% write_tsv(file.path(processed_dir, "aggregated_results_curated.tsv"))

# scan_results %>%
#   mutate(fill = fill_bgr + bgr) %>%
#   pivot_longer(c(fill_bgr, bgr)) %>%
#   ggplot(.) +
#   geom_freqpoly(aes( x = value, color = name ), binwidth = .05)

## Agegroups
### 1 = children
### 2 = adolescent
### 3 = adult
## (Symptom-)Choices
### n = "no"
### y = "yes"
### o = "often"
### u = "unrecognized"
### t = "text"
### v = "numeric value"

scan_results_curated <- lapply(c("/media/konrad/BD55-C3BA/Virus-Finder_Scans/20201124/Scans_processed/Batch1/aggregated_results_curated-20201124.xlsx",
                                  "/media/konrad/BD55-C3BA/Virus-Finder_Scans/20201124/Scans_processed/Batch2/aggregated_results_curated-20201124.xlsx"),
                                    function(.){
                                      ret <- read_xlsx(.)
                                      ret
                                    }) %>% bind_rows() %>%
  ## hack to fix wrong template assignment
    mutate(q_nr = as.numeric(ifelse(q_id == "q7", q_option, q_nr)),
           q_option = ifelse(q_id == "q7", "y", q_option),
           q_option = if_else(q_id == "q6" & q_nr == 5, "5", q_option))
curated_results <- scan_results_curated %>%
  mutate(curated = if_else(is.na(curated), as.character(state), curated)) %>%
#   left_join(., db_mappings, by = c("page", "q_type", "q_id", "q_nr")) %>%
  select(household_id, map_db, q_type, q_id, q_nr, q_option, curated)

consent <- scan_results_curated %>%
  group_by(household_id) %>%
  summarise( pages = length(unique(page)) ) %>%
  ungroup() %>%
  mutate(map_db = "consent", q_id = "15",
         answer = as.character(pages == 3),
         answer = recode(answer, "TRUE" = "y", "FALSE" = "n")) %>%
  select(-pages)

curated_results_out <- curated_results %>%
  filter(!is.na(map_db)) %>%
  mutate(q_option = recode(q_option, "yes" = "y", "no" = "n", "often" = "o")) %>%
  mutate( answer = case_when(curated == 1 ~ q_option,
                             curated == -1 ~ "u",
                             TRUE ~ "") ) %>%
  group_by(household_id, q_id, map_db) %>%
  summarise(answer = str_c(answer, collapse = "")) %>%
  ungroup() %>%
  mutate(#answer = recode(answer, "yo" = "o"),
         answer = if_else(q_id == "q14", if_else(answer == 1, "y", "n"), answer),
         answer = if_else(answer == "", "n", answer)) %>%
  bind_rows(., consent) %>%
  write_tsv("/media/konrad/BD55-C3BA/Virus-Finder_Scans/20201124-aggregated_results_curated.tsv")

         