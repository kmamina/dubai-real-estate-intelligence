# KPI definitions and business-question map (v1)

Source: `core.fact_transactions` through the `rpt` views. Data covers 2026-01-01 to 2026-11-04 only.
Items marked **ASSUMPTION** are my judgement, not facts from the data owner.

## Populations
| Name | Rule | Rows in this file |
|---|---|---|
| Eligible sales transaction | Group = Sales, first row of the transaction number, price per sq ft not flagged invalid (`is_sales_kpi_row`) | 136,108 |
| Price-KPI row | Eligible sale, category Apartment or Villa, price flag `ok` (`is_price_kpi_row`) | 116,304 |

Mortgages and gifts are never included in sales value or price KPIs.

## KPIs
| KPI | Definition | View |
|---|---|---|
| Sales transactions | Count of eligible sales transactions | `rpt.v_kpi_overview` |
| Total sales value (AED) | Sum of `TRANS_VALUE` over eligible sales. Includes land, buildings and commercial units, so it is not "residential value". | `rpt.v_kpi_overview` |
| Average transaction value | Mean of `TRANS_VALUE`. Skewed by very large deals, so the **median** is reported next to it. | `rpt.v_kpi_overview` |
| Price per sq ft (weighted) | Sum of value / sum of sq ft over price-KPI rows, with sq ft = sqm x 10.7639. Size-weighted, so a large flat counts more than a studio. | most `rpt` views |
| Price per sq ft (median) | Median of per-row price per sq ft over price-KPI rows | `rpt.v_kpi_overview` |
| Reliable area price | An area's price per sq ft is shown only with at least 30 price-KPI rows. **ASSUMPTION** (threshold) | `rpt.v_area_summary` |
| % vs market | (area price per sq ft / market price per sq ft - 1) x 100 | `rpt.v_area_summary` |
| Month-on-month change | Change in transactions vs previous month; empty for the partial month | `rpt.v_monthly_trend` |

## Business questions
| # | Question | Where to look |
|---|---|---|
| 1 | Highest transaction values by community | `v_area_summary` (`total_value_aed`, `rank_by_value`) |
| 2 | Highest average price per sq ft | `v_area_summary` (`price_per_sqft`, `rank_by_price_per_sqft`) |
| 3 | Highest transaction volumes | `v_area_summary` (`sales_transactions`, `rank_by_volume`) |
| 4 | Apartment vs villa | `v_property_summary` (filter category) |
| 5 | Off-plan vs ready | `v_stage_summary` |
| 6 | Most transacted property types | `v_property_summary` (`pct_of_transactions`) |
| 7 | Month-by-month activity | `v_monthly_trend` |
| 8 | Notable price differences between areas | `v_area_summary` (`pct_vs_market_price_per_sqft`) |
| 9 | Unusual values | `v_outliers_review` |

## Known limitations
- One partial year: no year-on-year growth and no seasonality claims. November 2026 is a partial month (4 days).
- `ACTUAL_AREA` is treated as square metres (**ASSUMPTION**, plausible price range supports it; confirm with the DLD data dictionary).
- Off-plan / ready comes from the DLD field `IS_OFFPLAN_EN`. Off-plan and ready sales sit in different areas, so their price gap is not a like-for-like comparison.
- Rental yield cannot be calculated from sales data.
- Price thresholds (100 / 300 / 10,000 / 50,000 AED per sq ft) are my judgement and are set in `src/config.py`.
