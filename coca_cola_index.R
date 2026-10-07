# =============================================================================
# The Coca-Cola Index
# A purchasing power parity (PPP) currency valuation index, built on the
# methodology of The Economist's Big Mac Index.
#
# Author: Kareem Zurub
# Data pulled: 2026-10-06
#
# How to run: set the working directory to this folder, then Source the whole
# file (Cmd+Shift+S / Ctrl+Shift+S). Running it in pieces can skip steps.
#
# Inputs
#   data/numbeo_coke_prices.csv          Restaurant price of a 0.33L Coca-Cola
#                                        (or Pepsi) in USD, Numbeo, last 12 months
#   data/worldbank_gdp_per_capita.csv    GDP per capita, current USD, World Bank
#                                        (NY.GDP.PCAP.CD), most recent year
#   data/economist_bigmac_2026_07.csv    The Economist's Big Mac Index, July 2026
#
# Outputs (written to output/)
#   coca_cola_index_results.csv   Raw and GDP-adjusted valuation for every country
#   coca_cola_vs_bigmac.csv       Side-by-side comparison with the Big Mac Index
#   fig1_raw_index.png            Most over- and undervalued currencies, raw
#   fig2_adjusted_index.png       Most over- and undervalued currencies, adjusted
#   fig3_price_vs_gdp.png         The regression behind the adjusted index
#   fig4_coke_vs_bigmac.png       Coca-Cola Index vs Big Mac Index
# =============================================================================

# Stop early with a clear message if the working directory is wrong
needed <- c("data/numbeo_coke_prices.csv", "data/worldbank_gdp_per_capita.csv",
            "data/economist_bigmac_2026_07.csv")
if (!all(file.exists(needed))) {
  stop("Data files not found. Set the working directory to the coca-cola-index ",
       "folder (Session > Set Working Directory > To Source File Location).")
}

library(ggplot2)
library(ggrepel)

base_country <- "USA"   # every currency is valued against the US dollar

# -----------------------------------------------------------------------------
# 1. Load and merge
# -----------------------------------------------------------------------------
prices <- read.csv("data/numbeo_coke_prices.csv", stringsAsFactors = FALSE)
gdp    <- read.csv("data/worldbank_gdp_per_capita.csv",  stringsAsFactors = FALSE)

df <- merge(prices, gdp, by = "iso3", all.x = TRUE)

# -----------------------------------------------------------------------------
# 2. Exclusions
#    Countries with multiple or heavily managed exchange rates make the "market"
#    rate unreliable, so a valuation against it means little. The Economist drops
#    Venezuela for the same reason.
# -----------------------------------------------------------------------------
excluded <- c(
  CUB = "Dual official/informal exchange rates; GDP data only to 2020",
  VEN = "Parallel exchange rate market",
  IRN = "Multiple official exchange rates"
)
df <- df[!df$iso3 %in% names(excluded), ]

# -----------------------------------------------------------------------------
# 3. Raw index
#    Because prices are already in USD, the over/undervaluation is simply the
#    ratio of the local dollar price to the US price, minus one. This is
#    algebraically identical to (implied PPP rate - market rate) / market rate.
# -----------------------------------------------------------------------------
us_price <- df$price_usd[df$iso3 == base_country]

df$raw_index <- df$price_usd / us_price - 1

# Implied PPP rate, expressed in "US dollars' worth per local dollar spent".
# Kept for transparency; the valuation above is what gets reported.
df$price_ratio_to_us <- df$price_usd / us_price

# -----------------------------------------------------------------------------
# 4. GDP-adjusted index
#    Richer countries have higher wages and rents, so non-traded inputs (service,
#    labour, retail space) push prices up. PPP should only hold after controlling
#    for income (the Balassa-Samuelson effect).
#
#    Following The Economist: regress the dollar price on GDP per capita, then
#    compare each country's actual price with the price predicted for its income,
#    relative to the same comparison for the US.
# -----------------------------------------------------------------------------
reg_df <- df[!is.na(df$gdp_pc_usd), ]
model  <- lm(price_usd ~ gdp_pc_usd, data = reg_df)

cat("\n--- Regression: dollar price on GDP per capita ---\n")
print(summary(model))

reg_df$fitted_price <- predict(model, newdata = reg_df)
us_ratio <- with(reg_df[reg_df$iso3 == base_country, ], price_usd / fitted_price)

reg_df$adj_index <- (reg_df$price_usd / reg_df$fitted_price) / us_ratio - 1

df <- merge(df, reg_df[, c("iso3", "fitted_price", "adj_index")],
            by = "iso3", all.x = TRUE)

# -----------------------------------------------------------------------------
# 5. Save results
# -----------------------------------------------------------------------------
dir.create("output", showWarnings = FALSE)

out <- df[order(df$raw_index, decreasing = TRUE),
          c("country", "iso3", "price_usd", "gdp_pc_usd", "year",
            "raw_index", "fitted_price", "adj_index")]
out$raw_index  <- round(out$raw_index * 100, 1)   # percent
out$adj_index  <- round(out$adj_index * 100, 1)   # percent
out$fitted_price <- round(out$fitted_price, 2)
names(out)[names(out) == "year"]      <- "gdp_year"
names(out)[names(out) == "raw_index"] <- "raw_valuation_pct"
names(out)[names(out) == "adj_index"] <- "adjusted_valuation_pct"

write.csv(out, "output/coca_cola_index_results.csv", row.names = FALSE)

# -----------------------------------------------------------------------------
# 6. Charts
# -----------------------------------------------------------------------------
col_over  <- "#2a78d6"   # overvalued vs USD
col_under <- "#e34948"   # undervalued vs USD
ink       <- "#2b2b29"
muted     <- "#6b6b66"

theme_index <- theme_minimal(base_size = 12) +
  theme(
    plot.background    = element_rect(fill = "#fcfcfb", colour = NA),
    panel.grid.major.y = element_blank(),
    panel.grid.minor   = element_blank(),
    panel.grid.major.x = element_line(colour = "#e6e5e1", linewidth = 0.4),
    axis.text          = element_text(colour = muted),
    axis.title         = element_text(colour = muted, size = 10),
    plot.title         = element_text(colour = ink, face = "bold", size = 15),
    plot.subtitle      = element_text(colour = muted, size = 10.5),
    plot.caption       = element_text(colour = muted, size = 8.5, hjust = 0),
    plot.title.position   = "plot",
    plot.caption.position = "plot",
    legend.position    = "top",
    legend.justification = "left",
    legend.title       = element_blank(),
    plot.margin        = margin(16, 20, 12, 16)
  )

caption_txt <- paste0(
  "Sources: Numbeo (restaurant price, 0.33L Coca-Cola or Pepsi, pulled 6 Oct 2026); ",
  "World Bank GDP per capita.\n",
  "Excludes Cuba, Venezuela and Iran (multiple exchange rates). Analysis: Kareem Zurub."
)

# Top and bottom N bar chart for a given valuation column
extremes_chart <- function(data, col, n, title, subtitle, file) {
  d <- data[!is.na(data[[col]]) & data$iso3 != base_country, ]
  d <- d[order(d[[col]]), ]
  d <- rbind(head(d, n), tail(d, n))
  d$val   <- d[[col]] * 100
  d$side  <- ifelse(d$val >= 0, "Overvalued vs US dollar", "Undervalued vs US dollar")
  d$country <- factor(d$country, levels = d$country)
  d$label <- sprintf("%+.0f%%", d$val)
  d$hjust <- ifelse(d$val >= 0, -0.15, 1.15)

  lim <- max(abs(d$val)) * 1.18

  p <- ggplot(d, aes(x = val, y = country, fill = side)) +
    geom_col(width = 0.72) +
    geom_vline(xintercept = 0, colour = ink, linewidth = 0.4) +
    geom_text(aes(label = label, hjust = hjust), size = 3.2, colour = ink) +
    scale_fill_manual(values = c("Overvalued vs US dollar"  = col_over,
                                 "Undervalued vs US dollar" = col_under)) +
    scale_x_continuous(limits = c(-lim, lim),
                       labels = function(x) paste0(x, "%")) +
    labs(title = title, subtitle = subtitle, x = NULL, y = NULL,
         caption = caption_txt) +
    theme_index

  ggsave(file, p, width = 8, height = 8.5, dpi = 200, bg = "#fcfcfb")
}

extremes_chart(
  df, "raw_index", 12,
  "The Coca-Cola Index: raw valuation",
  sprintf("Price of a Coke vs the US ($%.2f). Positive = currency looks overvalued.", us_price),
  "output/fig1_raw_index.png"
)

extremes_chart(
  df, "adj_index", 12,
  "The Coca-Cola Index: adjusted for GDP per capita",
  "Valuation after accounting for each country's income level.",
  "output/fig2_adjusted_index.png"
)

# Regression scatter
label_set <- c("USA", "CHN", "DEU", "JPN", "IND", "GBR", "FRA", "ITA", "CAN",
               "BRA", "RUS", "KOR", "MEX", "AUS", "IDN", "TUR", "SAU", "ZAF",
               "CHE", "SGP", "QAT", "IRL", "LUX", "JOR", "EGY")
reg_df$lab <- ifelse(reg_df$iso3 %in% label_set, reg_df$country, "")

p3 <- ggplot(reg_df, aes(x = gdp_pc_usd / 1000, y = price_usd)) +
  geom_smooth(method = "lm", formula = y ~ x, se = FALSE,
              colour = muted, linewidth = 0.6, linetype = "dashed") +
  geom_point(colour = col_over, size = 2.4, alpha = 0.85) +
  geom_text_repel(aes(label = lab), size = 3, colour = ink,
                  min.segment.length = 0.2, seed = 1, max.overlaps = 30) +
  labs(
    title = "Richer countries pay more for a Coke",
    subtitle = sprintf(
      "Each point is a country. Dashed line: fitted price for its income (R-squared = %.2f).",
      summary(model)$r.squared),
    x = "GDP per capita (US$ thousands)", y = "Price of a 0.33L Coke (US$)",
    caption = caption_txt
  ) +
  scale_y_continuous(labels = function(x) paste0("$", x)) +
  theme_index +
  theme(panel.grid.major.y = element_line(colour = "#e6e5e1", linewidth = 0.4))

ggsave("output/fig3_price_vs_gdp.png", p3, width = 9, height = 6, dpi = 200,
       bg = "#fcfcfb")

# -----------------------------------------------------------------------------
# 7. Cross-check: does the Coca-Cola Index agree with the Big Mac Index?
#    The Economist's July 2026 release, from its public GitHub repository
#    (github.com/TheEconomist/big-mac-data, CC BY 4.0). The Economist reports the
#    euro area as one entry, so individual euro countries do not overlap.
# -----------------------------------------------------------------------------
bm <- read.csv("data/economist_bigmac_2026_07.csv", stringsAsFactors = FALSE)
cmp <- merge(df[, c("country", "iso3", "raw_index", "adj_index")], bm, by = "iso3")
cmp <- cmp[cmp$iso3 != base_country, ]

cor_raw <- cor(cmp$raw_index, cmp$bigmac_raw)
cor_adj <- cor(cmp$adj_index, cmp$bigmac_adjusted, use = "complete.obs")
same_sign <- mean(sign(cmp$raw_index) == sign(cmp$bigmac_raw))

cat("\n--- Coke vs Big Mac (", nrow(cmp), " shared countries) ---\n", sep = "")
cat(sprintf("Correlation, raw index:      %.2f\n", cor_raw))
cat(sprintf("Correlation, adjusted index: %.2f\n", cor_adj))
cat(sprintf("Same direction (raw):        %.0f%%\n", same_sign * 100))

cmp_out <- cmp[order(cmp$raw_index), c("country", "iso3", "raw_index", "bigmac_raw",
                                       "adj_index", "bigmac_adjusted")]
cmp_out[, 3:6] <- round(cmp_out[, 3:6] * 100, 1)
names(cmp_out)[3:6] <- c("coke_raw_pct", "bigmac_raw_pct",
                         "coke_adjusted_pct", "bigmac_adjusted_pct")
write.csv(cmp_out, "output/coca_cola_vs_bigmac.csv", row.names = FALSE)

cmp_labels <- c("CHE", "NOR", "GBR", "JPN", "CHN", "IND", "EGY", "SAU", "ARG",
                "BRA", "TUR", "JOR", "KWT", "QAT", "TWN", "SGP", "AUS", "CAN")
cmp$lab <- ifelse(cmp$iso3 %in% cmp_labels, cmp$country, "")

p4 <- ggplot(cmp, aes(x = bigmac_raw * 100, y = raw_index * 100)) +
  geom_abline(slope = 1, intercept = 0, colour = muted, linewidth = 0.5,
              linetype = "dashed") +
  geom_hline(yintercept = 0, colour = "#d6d5d0", linewidth = 0.4) +
  geom_vline(xintercept = 0, colour = "#d6d5d0", linewidth = 0.4) +
  geom_point(colour = col_over, size = 2.4, alpha = 0.85) +
  geom_text_repel(aes(label = lab), size = 3, colour = ink,
                  min.segment.length = 0.2, seed = 1, max.overlaps = 30) +
  scale_x_continuous(labels = function(x) paste0(x, "%")) +
  scale_y_continuous(labels = function(x) paste0(x, "%")) +
  labs(
    title = sprintf("Coke and the Big Mac broadly agree (correlation %.2f)", cor_raw),
    subtitle = sprintf(
      "Raw valuation vs US dollar, %d shared countries. Dashed line: perfect agreement.",
      nrow(cmp)),
    x = "Big Mac Index, raw (The Economist, July 2026)",
    y = "Coca-Cola Index, raw",
    caption = paste0(caption_txt, "\nBig Mac data: The Economist (CC BY 4.0).")
  ) +
  theme_index +
  theme(panel.grid.major.y = element_line(colour = "#e6e5e1", linewidth = 0.4))

ggsave("output/fig4_coke_vs_bigmac.png", p4, width = 9, height = 6, dpi = 200,
       bg = "#fcfcfb")

cat("\nDone. Results in output/\n")
