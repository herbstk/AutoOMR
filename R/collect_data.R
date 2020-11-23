library(tidyverse)

COLS <- c("answer_id", "state", "fill_bgr", "bgr")
COLS_TYPES <- "cddd"

processed_dir <- "./Scans_processed/20201122/processed"

processed_files <- list.files(processed_dir, pattern = "\\.tsv", recursive = TRUE, full.names = TRUE)

scan_results <- lapply(processed_files, function(.){
  ret <- read_tsv(., col_names = COLS, col_types = COLS_TYPES)
  meta <- str_match(., "/([0-9]+)-([1-3])\\.tsv$")
  ret$filename <- .
  ret$household_id <- meta[1,2]
  ret$page <- meta[1,3]
  answer_ids <- str_split_fixed(ret$answer_id, "_", 4)
  ret$q_type <- answer_ids[,1]
  ret$q_id <- answer_ids[,2]
  ret$q_nr <- answer_ids[,3]
  ret$q_option <- answer_ids[,4]
  ret
}) %>%
  bind_rows() %>%
  select(filename, household_id, page, starts_with("q_"), state, fill_bgr, bgr) %>%
  write_tsv(file.path(processed_dir, "../aggregated_results.tsv"))

scan_results %>%
  mutate(fill = fill_bgr + bgr) %>%
  pivot_longer(c(fill_bgr, bgr)) %>%
  ggplot(.) +
  geom_freqpoly(aes( x = value, color = name ), binwidth = .05)
