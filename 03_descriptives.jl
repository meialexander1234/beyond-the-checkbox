######################################################################
# FILE: 03_descriptives.jl
#
# Purpose: Generate descriptive statistics and summary tables
#          for the Beyond the Checkbox paper
#
# Output:  table1_descriptives.csv — Sample descriptives by ethnicity
#          table2_yearly_trends.csv — Trends over time
#          table3_multiple_detail.csv — Detailed look at Multiple group
#          figures data for plotting
#
# Author: Jessica Alexander
######################################################################

using DataFrames
using CSV
using Statistics

println("="^60)
println("SCRIPT 03: DESCRIPTIVE STATISTICS")
println("="^60)

## Set paths ##
const PROJECT_PATH = "C:/jessiepaper"
const OUTPUT_PATH = joinpath(PROJECT_PATH, "julia", "output")

## Load Data ##
println("\nLoading longitude data...")
longitude_data = CSV.read(joinpath(OUTPUT_PATH, "longitude_data.csv"), DataFrame)
longitude_gender = CSV.read(joinpath(OUTPUT_PATH, "longitude_gender.csv"), DataFrame)
longitude_jobcat = CSV.read(joinpath(OUTPUT_PATH, "longitude_jobcat.csv"), DataFrame)
firm_blau = CSV.read(joinpath(OUTPUT_PATH, "firm_blau.csv"), DataFrame)

println("Loaded:")
println("  longitude_data: $(nrow(longitude_data)) rows")
println("  longitude_gender: $(nrow(longitude_gender)) rows")
println("  longitude_jobcat: $(nrow(longitude_jobcat)) rows")
println("  firm_blau: $(nrow(firm_blau)) rows")

## Filter to years with sufficient data (2000+) ##
println("\nFiltering to years 2000-2024 for reliable estimates...")
longitude_data = filter(row -> row.year >= 2000 && row.year <= 2024, longitude_data)
longitude_gender = filter(row -> row.year >= 2000 && row.year <= 2024, longitude_gender)
longitude_jobcat = filter(row -> row.year >= 2000 && row.year <= 2024, longitude_jobcat)
firm_blau = filter(row -> row.year >= 2000 && row.year <= 2024, firm_blau)

println("After filtering:")
println("  longitude_data: $(nrow(longitude_data)) rows")
println("  Years: $(minimum(longitude_data.year)) to $(maximum(longitude_data.year))")

## ============================================================
## TABLE 1: SAMPLE DESCRIPTIVES BY ETHNICITY
## ============================================================
println("\n" * "="^60)
println("TABLE 1: SAMPLE DESCRIPTIVES BY ETHNICITY")
println("="^60)

table1 = combine(groupby(longitude_data, :ethnicity),
    :n_obs => sum => :total_n,
    :mean_seniority => (x -> round(mean(x), digits=2)) => :mean_seniority,
    :sd_seniority => (x -> round(mean(x), digits=2)) => :mean_sd_seniority,
    :mean_log_salary => (x -> round(mean(x), digits=3)) => :mean_log_salary,
    :mean_log_comp => (x -> round(mean(x), digits=3)) => :mean_log_comp,
    :mean_tenure => (x -> round(mean(x), digits=2)) => :mean_tenure,
    :pct_female => (x -> round(mean(x) * 100, digits=1)) => :pct_female,
    :mean_edu => (x -> round(mean(x), digits=2)) => :mean_edu
)

# Add percentage of total
total_n = sum(table1.total_n)
table1.pct_of_total = round.(100 .* table1.total_n ./ total_n, digits=2)

# Convert log salary to approximate dollar amount for interpretation
table1.approx_salary = round.(exp.(table1.mean_log_salary), digits=0)

# Sort by sample size
sort!(table1, :total_n, rev=true)

println("\n")
println(table1)

CSV.write(joinpath(OUTPUT_PATH, "table1_descriptives.csv"), table1)
println("\nSaved: table1_descriptives.csv")

## ============================================================
## TABLE 2: YEARLY TRENDS BY ETHNICITY
## ============================================================
println("\n" * "="^60)
println("TABLE 2: YEARLY TRENDS")
println("="^60)

# Select key years for display
key_years = [2000, 2005, 2010, 2015, 2020, 2024]

table2_data = filter(row -> row.year in key_years, longitude_data)
table2 = unstack(table2_data, :year, :ethnicity, :mean_seniority)
sort!(table2, :year)

println("\nMean Seniority by Year:")
println(table2)

CSV.write(joinpath(OUTPUT_PATH, "table2_seniority_trends.csv"), table2)

# Also create salary trends
table2_sal = unstack(table2_data, :year, :ethnicity, :mean_log_salary)
sort!(table2_sal, :year)

println("\nMean Log Salary by Year:")
println(table2_sal)

CSV.write(joinpath(OUTPUT_PATH, "table2_salary_trends.csv"), table2_sal)

## ============================================================
## TABLE 3: MULTIPLE GROUP DETAILED BREAKDOWN
## ============================================================
println("\n" * "="^60)
println("TABLE 3: MULTIPLE GROUP DETAILS")
println("="^60)

multiple_data = filter(row -> row.ethnicity == "Multiple", longitude_data)

println("\nMultiple group yearly statistics:")
println("  Years covered: $(minimum(multiple_data.year)) to $(maximum(multiple_data.year))")
println("  Total person-years: $(sum(multiple_data.n_obs))")
println("  Mean n per year: $(round(mean(multiple_data.n_obs), digits=0))")

# Show trend over time
println("\nMultiple group growth over time:")
multiple_summary = select(multiple_data, :year, :n_obs, :mean_seniority, :mean_log_salary)
println(multiple_summary)

CSV.write(joinpath(OUTPUT_PATH, "table3_multiple_detail.csv"), multiple_data)

## ============================================================
## H1 PREVIEW: MULTIPLE VS WHITE GAP
## ============================================================
println("\n" * "="^60)
println("H1 PREVIEW: MULTIPLE VS WHITE GAP")
println("="^60)

white_data = filter(row -> row.ethnicity == "White", longitude_data)

# Merge for comparison
comparison = innerjoin(
    select(white_data, :year, :mean_seniority => :white_seniority, :mean_log_salary => :white_salary),
    select(multiple_data, :year, :mean_seniority => :multiple_seniority, :mean_log_salary => :multiple_salary),
    on = :year
)

comparison.seniority_gap = comparison.white_seniority .- comparison.multiple_seniority
comparison.salary_gap = comparison.white_salary .- comparison.multiple_salary

println("\nSeniority Gap (White - Multiple) by Year:")
println("  Mean gap: $(round(mean(comparison.seniority_gap), digits=3))")
println("  Min gap: $(round(minimum(comparison.seniority_gap), digits=3))")
println("  Max gap: $(round(maximum(comparison.seniority_gap), digits=3))")

println("\nLog Salary Gap (White - Multiple) by Year:")
println("  Mean gap: $(round(mean(comparison.salary_gap), digits=4))")
println("  Gap in %: $(round((exp(mean(comparison.salary_gap)) - 1) * 100, digits=1))%")

CSV.write(joinpath(OUTPUT_PATH, "h1_preview_gaps.csv"), comparison)

## ============================================================
## H2 PREVIEW: NON-AVERAGING TEST
## ============================================================
println("\n" * "="^60)
println("H2 PREVIEW: NON-AVERAGING TEST")
println("="^60)

# ACS-derived weights for multiracial population composition
# (approximate — will refine with actual ACS data)
# Based on Census 2020: White-Black ~18%, White-Asian ~24%, White-Hispanic ~38%, Other ~20%
w_black = 0.18
w_asian = 0.24
w_hispanic = 0.38
w_white = 0.10  # Some multiracial people have two minority parents
w_other = 0.10  # Residual

println("Using ACS-derived weights:")
println("  Black component: $w_black")
println("  Asian component: $w_asian")
println("  Hispanic component: $w_hispanic")
println("  White component: $w_white")

# Get mean seniority by group
mean_by_group = combine(groupby(longitude_data, :ethnicity),
    :mean_seniority => mean => :avg_seniority,
    :mean_log_salary => mean => :avg_salary,
    :n_obs => sum => :total_n
)

white_sen = mean_by_group[mean_by_group.ethnicity .== "White", :avg_seniority][1]
black_sen = mean_by_group[mean_by_group.ethnicity .== "Black", :avg_seniority][1]
asian_sen = mean_by_group[mean_by_group.ethnicity .== "API", :avg_seniority][1]
hispanic_sen = mean_by_group[mean_by_group.ethnicity .== "Hispanic", :avg_seniority][1]
multiple_sen = mean_by_group[mean_by_group.ethnicity .== "Multiple", :avg_seniority][1]

# Weighted average prediction
weighted_avg = w_black * black_sen + w_asian * asian_sen + 
               w_hispanic * hispanic_sen + w_white * white_sen

println("\nSeniority Comparison:")
println("  White: $(round(white_sen, digits=3))")
println("  API: $(round(asian_sen, digits=3))")
println("  Black: $(round(black_sen, digits=3))")
println("  Hispanic: $(round(hispanic_sen, digits=3))")
println("  Multiple (observed): $(round(multiple_sen, digits=3))")
println("  Weighted average (predicted): $(round(weighted_avg, digits=3))")
println("  Deviation: $(round(multiple_sen - weighted_avg, digits=3))")

if multiple_sen < weighted_avg
    println("\n  → Multiple BELOW weighted average (supports H2)")
else
    println("\n  → Multiple ABOVE weighted average (does not support H2)")
end

## ============================================================
## H3 PREVIEW: OCCUPATION BREAKDOWN
## ============================================================
println("\n" * "="^60)
println("H3 PREVIEW: SENIORITY BY JOB CATEGORY")
println("="^60)

# Aggregate by ethnicity × jobcat
jobcat_summary = combine(groupby(longitude_jobcat, [:ethnicity, :jobcat]),
    :n_obs => sum => :total_n,
    :mean_seniority => mean => :avg_seniority
)

# Filter to Multiple and show job categories
multiple_jobs = filter(row -> row.ethnicity == "Multiple", jobcat_summary)
sort!(multiple_jobs, :total_n, rev=true)

println("\nMultiple group by job category:")
println(first(multiple_jobs, 10))

# Compare Multiple vs White by job category
white_jobs = filter(row -> row.ethnicity == "White", jobcat_summary)

job_comparison = innerjoin(
    select(white_jobs, :jobcat, :avg_seniority => :white_sen),
    select(multiple_jobs, :jobcat, :avg_seniority => :multiple_sen, :total_n),
    on = :jobcat
)
job_comparison.gap = job_comparison.white_sen .- job_comparison.multiple_sen
sort!(job_comparison, :gap, rev=true)

println("\nLargest gaps (White - Multiple) by job category:")
println(first(job_comparison, 10))

CSV.write(joinpath(OUTPUT_PATH, "h3_jobcat_gaps.csv"), job_comparison)

## ============================================================
## H4 PREVIEW: GENDER BREAKDOWN
## ============================================================
println("\n" * "="^60)
println("H4 PREVIEW: GENDER DIFFERENCES")
println("="^60)

gender_summary = combine(groupby(longitude_gender, [:ethnicity, :female]),
    :n_obs => sum => :total_n,
    :mean_seniority => mean => :avg_seniority,
    :mean_log_salary => mean => :avg_salary
)

gender_summary.gender = ifelse.(gender_summary.female .== 1, "Female", "Male")

println("\nSeniority by Ethnicity × Gender:")
gender_wide = unstack(gender_summary, :ethnicity, :gender, :avg_seniority)
println(gender_wide)

# Gender gap within Multiple
multiple_male = filter(row -> row.ethnicity == "Multiple" && row.female == 0, gender_summary)
multiple_female = filter(row -> row.ethnicity == "Multiple" && row.female == 1, gender_summary)

if nrow(multiple_male) > 0 && nrow(multiple_female) > 0
    male_sen = multiple_male.avg_seniority[1]
    female_sen = multiple_female.avg_seniority[1]
    println("\nMultiple group gender gap:")
    println("  Male: $(round(male_sen, digits=3))")
    println("  Female: $(round(female_sen, digits=3))")
    println("  Gap (M-F): $(round(male_sen - female_sen, digits=3))")
end

CSV.write(joinpath(OUTPUT_PATH, "h4_gender_summary.csv"), gender_summary)

## ============================================================
## H5 PREVIEW: FIRM DIVERSITY
## ============================================================
println("\n" * "="^60)
println("H5 PREVIEW: FIRM DIVERSITY DISTRIBUTION")
println("="^60)

println("\nFirm Blau Index Distribution:")
println("  N firm-years: $(nrow(firm_blau))")
println("  Mean: $(round(mean(firm_blau.blau_index), digits=3))")
println("  Median: $(round(median(firm_blau.blau_index), digits=3))")
println("  SD: $(round(std(firm_blau.blau_index), digits=3))")
println("  Min: $(round(minimum(firm_blau.blau_index), digits=3))")
println("  Max: $(round(maximum(firm_blau.blau_index), digits=3))")

# Quartiles
q25 = quantile(firm_blau.blau_index, 0.25)
q50 = quantile(firm_blau.blau_index, 0.50)
q75 = quantile(firm_blau.blau_index, 0.75)
println("\n  25th percentile: $(round(q25, digits=3))")
println("  50th percentile: $(round(q50, digits=3))")
println("  75th percentile: $(round(q75, digits=3))")

## ============================================================
## SAVE FIGURE DATA
## ============================================================
println("\n" * "="^60)
println("SAVING FIGURE DATA")
println("="^60)

# Figure 1: Seniority trends over time by ethnicity
fig1_data = select(longitude_data, :ethnicity, :year, :mean_seniority, :n_obs)
CSV.write(joinpath(OUTPUT_PATH, "fig1_seniority_trends.csv"), fig1_data)
println("  Saved: fig1_seniority_trends.csv")

# Figure 2: Multiple vs White gap over time
CSV.write(joinpath(OUTPUT_PATH, "fig2_gap_trends.csv"), comparison)
println("  Saved: fig2_gap_trends.csv")

# Figure 3: Job category comparison
CSV.write(joinpath(OUTPUT_PATH, "fig3_jobcat_comparison.csv"), job_comparison)
println("  Saved: fig3_jobcat_comparison.csv")

## ============================================================
## SUMMARY
## ============================================================
println("\n" * "="^60)
println("SCRIPT 03 COMPLETE")
println("="^60)

println("""
Key Findings:

H1 (Multiple vs White):
  - Seniority gap: $(round(mean(comparison.seniority_gap), digits=2)) levels
  - Salary gap: $(round((exp(mean(comparison.salary_gap)) - 1) * 100, digits=1))%

H2 (Non-averaging):
  - Multiple observed: $(round(multiple_sen, digits=2))
  - Weighted average: $(round(weighted_avg, digits=2))
  - Deviation: $(round(multiple_sen - weighted_avg, digits=2))

Files saved:
  - table1_descriptives.csv
  - table2_seniority_trends.csv
  - table2_salary_trends.csv
  - table3_multiple_detail.csv
  - h1_preview_gaps.csv
  - h3_jobcat_gaps.csv
  - h4_gender_summary.csv
  - fig1_seniority_trends.csv
  - fig2_gap_trends.csv
  - fig3_jobcat_comparison.csv

Next: Run 04_hypothesis_tests.jl
""")
