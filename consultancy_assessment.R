### Loading libraries
library(tidyverse)
library(dplyr)
library(readxl)
library(janitor)
library(car)
library(ggplot2)
library(tidyr)
library(purrr)
library(stringr)

### Loading the data
data_1 <- read_excel("GLOBAL_DATA_2018-2022_final.xlsx") %>%
  clean_names()

## Excluding the last 7 irrelevant rows from the dataset because they are not part
## of the dataset I need

data_1 <- data_1 %>% filter(row_number() <= n()-7)

# Renaming the geographic_area column to make things more clear that we are
# only dealing with countries and not aggregated geographies
 data_1 <- data_1 %>%
   rename (country = geographic_area)
 
# Changing the character type of numeric variables
data_1$x2022 <- suppressWarnings(as.numeric(data_1$x2022))
data_1$x2021 <- suppressWarnings(as.numeric(data_1$x2021))
data_1$x2020 <- suppressWarnings(as.numeric(data_1$x2020))
data_1$x2019 <- suppressWarnings(as.numeric(data_1$x2019))
data_1$x2018 <- suppressWarnings(as.numeric(data_1$x2018))
 
### Loading the population demographics dataset
data_2 <- read_excel("DEMOGRAPHIC_INDICATORS_COMPACT_REV1.xlsx") %>%
  clean_names()

## Renaming the geographic_area column in population dataset to make things
## more clear that we are only dealing with countries and not aggregated
#geographies
data_2 <- data_2 %>%
  rename (country = region_subregion_country_or_area)

# Selecting only those columns that I need from data_2 
data_2_subset <- data_2 %>%
  select(country, type, year, births_thousands) %>%
  filter(year == "2022")

# Changing the character type of numeric variables
data_2_subset$births_thousands <- as.numeric(data_2_subset$births_thousands)

# Renaming the year column to avoid error in later parts of the analysis
data_2_subset <- data_2_subset %>%
  rename(projection_year =  year)

# Creating a new column for ascertain true births projections
data_2_subset <- data_2_subset %>% mutate(births = births_thousands * 1000)

### Loading the country status data
data_3 <- read_excel("On-track and off-track countries.xlsx") %>%
  clean_names()

## Deleting one unnecessary column from the dataset
data_3 <- subset(data_3, select = -iso3code)

# Renaming the official_name column in data_3 dataset to ensure consistency
# across column names
data_3 <- data_3 %>%
  rename (country = official_name)
# Creating a new column track_status
data_3 <- data_3 %>%
  mutate(track_status = if_else(
    status_u5mr %in% c("Achieved", "On Track"),
    "on-track",
    "off-track"
  ))

### Doing a left join to merge three datasets
data_merged <- data_1 %>%
  left_join(data_2_subset, by = "country") %>%
  left_join(data_3, by = "country")

### Pivoting the year columns into long format
data_long <- data_merged %>%
  pivot_longer(
    cols = starts_with("x20"),
    names_to = "year",
    names_prefix = "x",
    values_to = "value"
  ) %>%
  mutate(year = as.integer(year))  # to ensure year is numeric

### Filtering out NA or zero values and pick the most recent per country +
### indicator
data_final <- data_long %>%
  filter(!is.na(value), value != 0) %>%
  group_by(country, indicator) %>%
  slice_max(order_by = year, n = 1, with_ties = FALSE) %>%
  ungroup()

### Joining again with merged dataset
data_final <- data_final %>%
  left_join(
    data_merged %>% select(country) %>% distinct(),
    by = "country"
  )

### Computing population-weighted average for each indicator and track_status
weighted_avg <- data_final %>%
  group_by(track_status, indicator) %>%
  summarise(
    weighted_avg = sum(value * births, na.rm = TRUE) / sum(births, na.rm = TRUE),
    .groups = "drop"
  )

## Viewing the result
weighted_avg

### Visualization

## Wrapping indicator names for tidy axis labels
weighted_avg_wrapped <- weighted_avg %>%
  mutate(indicator_wrapped = str_wrap(indicator, width = 15))

## Creating the plot
ggplot(weighted_avg_wrapped, aes(x = indicator_wrapped,
                                 y = weighted_avg,
                                 fill = track_status)) +
  geom_col(position = "dodge", width = 0.6) +
  geom_text(
    aes(label = paste0(round(weighted_avg, 1), "%")),
    position = position_dodge(width = 0.6),
    vjust = -0.5,
    size = 4
  ) +
  scale_fill_manual(values = c("on-track" = "#1b9e77", "off-track" = "#d95f02")) +
  scale_y_continuous(
    limits = c(0, 100),
    breaks = seq(0, 100, by = 25)
  ) +
  labs(
    title = "Population-Weighted Coverage of Health Services",
    subtitle = "On-Track vs. Off-Track Countries (Most Recent Available Data)",
    x = "Health Indicator",
    y = "Coverage (%)",
    fill = "Track Status"
  ) +
  theme_minimal(base_size = 14)
