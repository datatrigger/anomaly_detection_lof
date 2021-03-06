# Packages
library(tidyverse) # ❤
library(doParallel) # To use all the available cores
library(Rlof) # Local Outlier Factor
library(solitude) # Isolation forest
library(gridExtra) # to export tables

# Generate data
set.seed(1)

disk <- tibble(
  x = rnorm(1000, 0.2, 0.01),
  y = rnorm(1000, 0.2, 0.01),
  category = 'Disk'
)

triangle <- tibble(
  x = runif(500, 0, 1),
  y = runif(500, 1-x, 1),
  category = 'Triangle'
)

outliers <- tribble(
  ~x, ~y, ~category,
  0.25, 0.25, 'Local outlier',
  0.1, 0.5, 'Global outlier'
)

df <- disk %>%
  bind_rows(
    triangle
  ) %>%
  bind_rows(
    outliers
  ) %>%
  mutate(
    id = row_number()
  ) %>%
  select(id, everything())

# Plot data
plot <- ggplot() +
  aes(x = x, y = y) +
  geom_point(data = df %>% filter(category %in% c('Disk', 'Triangle')), mapping = aes(color = category), size = 0.5, show.legend = FALSE) +
  geom_point(data = df %>% filter(category %>% str_detect('outlier')), color = 'red', size = 1.5) +
  scale_x_continuous(breaks = seq(0, 1, 0.1)) +
  scale_y_continuous(breaks = seq(0, 1, 0.1)) +
  scale_colour_manual(values = c("forestgreen", "darkblue")) +
  geom_label( mapping = aes(x = 0.13, y = 0.25, label = 'C[1]'), size = 5, parse = TRUE, color = 'forestgreen' ) +
  geom_label( mapping = aes(x = 0.2, y = 0.7, label = 'C[2]'), size = 5, parse = TRUE, color = 'darkblue' ) +
  geom_text( mapping = aes(x = 0.28, y = 0.25, label = 'O[l]'), color = 'red', size = 5, parse = TRUE ) +
  geom_text( mapping = aes(x = 0.07, y = 0.5, label = 'O[g]'), color = 'red', size = 5, parse = TRUE ) +
  theme_minimal() +
  theme(
    #panel.grid.major = element_blank(),
    panel.grid.minor = element_blank()
    )

print(plot)

# Local Outlier Factor
df_lof <- df
# let us use 4 cores
cluster <- makePSOCKcluster(4)
registerDoParallel(cluster)

for(i in seq(10,15)){
  df_lof <- df_lof %>%
    bind_cols(
      tibble( !!str_c('k = ', i) := Rlof::lof(data = df %>% select(x, y), k = i) )
    )
}

stopCluster(cluster)
  
# Computation of the maximal LOF of each observation
df_lof_agg <- df_lof %>%
  pivot_longer(
    cols = starts_with('k'),
    names_to = 'k',
    values_to = 'lof'
  ) %>%
  group_by(id) %>%
  summarise(
    lof_max = max(lof)
  )

# Results : LOF for each value of k and max(lof)
df_lof <- df_lof %>%
  inner_join(
    df_lof_agg,
    by = 'id'
  ) %>%
  arrange(desc(lof_max))

# LOF correctly identifies both outliers.

# Print the results
# df_print <- df_lof %>% slice(1:10)
# png("lof_table.png", height = 50*nrow(df_print), width = 200*ncol(df_print))
# df_print %>% grid.table()
# dev.off()

# df_lof %>% slice(1:10) %>% write_csv(path = 'df_lof.csv')

# Plot the results
plot_res <- ggplot(data = df_lof) +
  aes(x = x, y = y) +
  geom_point(size = 0.3) +
  geom_point(
    data = df_lof %>% slice(1:10),
    aes(size = 2*lof_max),
    pch = 21,
    fill = NA,
    color = "red",
    stroke = 0.5
  ) +
  scale_x_continuous(breaks = seq(0, 1, 0.1)) +
  scale_y_continuous(breaks = seq(0, 1, 0.1)) +
  theme_minimal() +
  theme(
    panel.grid.minor = element_blank()
  )

print(plot_res)

# Isolation forest

# Creation of an Isolation Forest with default parameters
isolation_forest<- isolationForest$new(
  sample_size = nrow(df),
  num_trees = 500,
  replace = FALSE,
  seed = 1,
  nproc = 4
)
# Fit to the data
isolation_forest$fit(df %>% select(x, y) %>% as.data.frame())
# Compute anomaly scores and append them to the original data
df_if <- df %>%
  mutate(
    if_anomaly_score = isolation_forest$predict(df %>% select(x, y) %>% as.data.frame()) %>% pull(anomaly_score)
  ) %>%
  arrange(desc(if_anomaly_score))

# Isolation fails to clearly distinguish the local outlier.

# Print the results
# df_print <- df_if %>% slice(1:10)
# png("if_table.png")
# df_print %>% grid.table()
# dev.off()