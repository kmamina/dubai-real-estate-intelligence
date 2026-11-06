# Data quality report: test-overlap.csv

Generated: 2026-11-06 19:53

## input

| Metric | Value |
|---|---|
| source_file | test-overlap.csv |
| rows_read | 1000 |
| columns_read | 22 |
| unexpected_extra_columns | none |
| rows_clean | 1000 |

## missing_pct_raw

| Metric | Value |
|---|---|
| MASTER_PROJECT_EN | 99.7 |
| NEAREST_MALL_EN | 53.0 |
| NEAREST_METRO_EN | 51.8 |
| NEAREST_LANDMARK_EN | 38.2 |
| PARKING | 18.4 |
| ROOMS_EN | 4.5 |
| PROCEDURE_AREA | 0.1 |
| IS_OFFPLAN_EN | 0.0 |
| IS_FREE_HOLD_EN | 0.0 |
| GROUP_EN | 0.0 |
| INSTANCE_DATE | 0.0 |
| TRANSACTION_NUMBER | 0.0 |
| PROCEDURE_EN | 0.0 |
| USAGE_EN | 0.0 |
| ACTUAL_AREA | 0.0 |
| TRANS_VALUE | 0.0 |
| PROP_TYPE_EN | 0.0 |
| PROP_SB_TYPE_EN | 0.0 |
| AREA_EN | 0.0 |
| TOTAL_BUYER | 0.0 |
| TOTAL_SELLER | 0.0 |
| PROJECT_EN | 0.0 |

## corrected

| Metric | Value |
|---|---|
| text_cells_trimmed_total | 10 |
| text_cells_trimmed_PARKING | 10 |
| area_rows_respelled | 623 |
| unique_areas_before | 71 |
| unique_areas_after | 69 |
| missing_labelled_not_specified_rooms | 45 |
| missing_labelled_not_specified_parking | 184 |
| missing_labelled_not_specified_nearest_metro | 518 |
| missing_labelled_not_specified_nearest_mall | 530 |
| missing_labelled_not_specified_nearest_landmark | 382 |

## flagged

| Metric | Value |
|---|---|
| rows_identical_in_all_columns (kept) | 104 |
| repeat_rows_of_same_transaction_number_Mortgage | 214 |
| sales_price_flag_ok | 722 |
| sales_price_flag_not_assessed | 43 |
| sales_price_flag_review_high | 2 |
| sales_price_flag_review_low | 1 |
| rows_in_partial_month | 25 |
| partial_month | 2026-11 |

## type_conversion_failures

| Metric | Value |
|---|---|
| TRANS_VALUE | 0 |
| PROCEDURE_AREA | 0 |
| ACTUAL_AREA | 0 |
| TOTAL_BUYER | 0 |
| TOTAL_SELLER | 0 |
| INSTANCE_DATE | 0 |

## unexpected_category_values

| Metric | Value |
|---|---|
| IS_OFFPLAN_EN | 0 |
| IS_FREE_HOLD_EN | 0 |
| USAGE_EN | 0 |
| PROP_TYPE_EN | 0 |
| GROUP_EN | 0 |

## rejected

| Metric | Value |
|---|---|
| rows_rejected_total | 0 |
| rule_missing_transaction_number | 0 |
| rule_invalid_date | 0 |
| rule_unexpected_group | 0 |
| rule_sales_invalid_value | 0 |
| rule_sales_invalid_area | 0 |

## kpi_populations

| Metric | Value |
|---|---|
| sales_rows_total | 768 |
| sales_kpi_rows (transactions and value) | 768 |
| price_kpi_rows (price per sq ft) | 722 |
