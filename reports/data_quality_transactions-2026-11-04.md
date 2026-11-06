# Data quality report: transactions-2026-11-04.csv

Generated: 2026-11-06 19:49

## input

| Metric | Value |
|---|---|
| source_file | transactions-2026-11-04.csv |
| rows_read | 184851 |
| columns_read | 22 |
| unexpected_extra_columns | none |
| rows_clean | 184851 |

## missing_pct_raw

| Metric | Value |
|---|---|
| MASTER_PROJECT_EN | 99.6 |
| NEAREST_MALL_EN | 52.5 |
| NEAREST_METRO_EN | 51.5 |
| NEAREST_LANDMARK_EN | 38.8 |
| PARKING | 22.8 |
| ROOMS_EN | 14.9 |
| PROJECT_EN | 12.9 |
| PROP_SB_TYPE_EN | 1.6 |
| IS_FREE_HOLD_EN | 0.0 |
| IS_OFFPLAN_EN | 0.0 |
| INSTANCE_DATE | 0.0 |
| TRANSACTION_NUMBER | 0.0 |
| PROCEDURE_EN | 0.0 |
| GROUP_EN | 0.0 |
| ACTUAL_AREA | 0.0 |
| PROCEDURE_AREA | 0.0 |
| TRANS_VALUE | 0.0 |
| PROP_TYPE_EN | 0.0 |
| USAGE_EN | 0.0 |
| AREA_EN | 0.0 |
| TOTAL_SELLER | 0.0 |
| TOTAL_BUYER | 0.0 |

## corrected

| Metric | Value |
|---|---|
| text_cells_trimmed_total | 3083 |
| text_cells_trimmed_PROCEDURE_EN | 7 |
| text_cells_trimmed_PARKING | 2377 |
| text_cells_trimmed_NEAREST_METRO_EN | 1 |
| text_cells_trimmed_PROJECT_EN | 698 |
| area_rows_respelled | 117865 |
| unique_areas_before | 273 |
| unique_areas_after | 268 |
| missing_labelled_not_specified_property_subtype | 2876 |
| missing_labelled_not_specified_rooms | 27456 |
| missing_labelled_not_specified_parking | 42142 |
| missing_labelled_not_specified_nearest_metro | 95179 |
| missing_labelled_not_specified_nearest_mall | 97065 |
| missing_labelled_not_specified_nearest_landmark | 71801 |
| missing_labelled_not_specified_project_name | 23915 |

## flagged

| Metric | Value |
|---|---|
| rows_identical_in_all_columns (kept) | 463 |
| repeat_rows_of_same_transaction_number_Gifts | 1 |
| repeat_rows_of_same_transaction_number_Mortgage | 5325 |
| repeat_rows_of_same_transaction_number_Sales | 25 |
| sales_price_flag_ok | 116327 |
| sales_price_flag_not_assessed | 19618 |
| sales_price_flag_invalid_low | 466 |
| sales_price_flag_review_low | 148 |
| sales_price_flag_review_high | 40 |
| sales_price_flag_invalid_high | 3 |
| rows_in_partial_month | 2401 |
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
| sales_rows_total | 136602 |
| sales_kpi_rows (transactions and value) | 136108 |
| price_kpi_rows (price per sq ft) | 116304 |
