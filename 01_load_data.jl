######################################################################
# FILE: 01_load_data.jl
#
# Purpose: Load individ.RData, inspect structure, basic cleaning
#
# Author: Jessica Alexander
######################################################################

using RData
using DataFrames
using CSV
using Statistics

## Set paths ##
const PROJECT_PATH = "C:/jessiepaper"
const DATA_PATH = joinpath(PROJECT_PATH, "data")
const OUTPUT_PATH = joinpath(PROJECT_PATH, "julia", "output")

# Create output directory if it doesn't exist
mkpath(OUTPUT_PATH)

## Load Data ##
println("Loading individ.RData...")
println("This may take a few minutes for 1.3GB file...")

@time rdata = load(joinpath(DATA_PATH, "individ.RData"))

# Extract the dataframe (should be named "individ")
individ = rdata["individ"]

println("\n" * "="^60)
println("DATA LOADED SUCCESSFULLY")
println("="^60)

## Inspect Structure ##
println("\n--- Dimensions ---")
println("Rows: $(nrow(individ))")
println("Columns: $(ncol(individ))")

println("\n--- Column Names and Types ---")
for (name, col) in pairs(eachcol(individ))
    println("  $name: $(eltype(col))")
end

println("\n--- First 5 Rows ---")
println(first(individ, 5))

## Check Ethnicity Distribution ##
println("\n--- Ethnicity Distribution ---")
eth_counts = combine(groupby(individ, :ethnicity_predicted), nrow => :count)
eth_counts.percent = round.(100 .* eth_counts.count ./ sum(eth_counts.count), digits=2)
sort!(eth_counts, :count, rev=true)
println(eth_counts)

## Check for Missing Values ##
println("\n--- Missing Values by Column ---")
for name in names(individ)
    n_missing = sum(ismissing.(individ[!, name]))
    if n_missing > 0
        pct = round(100 * n_missing / nrow(individ), digits=2)
        println("  $name: $n_missing ($pct%)")
    end
end

## Basic Cleaning ##
println("\n" * "="^60)
println("CLEANING DATA")
println("="^60)

# Record original size
n_original = nrow(individ)
println("\nOriginal records: $n_original")

# Filter to US workers only
println("\nFiltering to US workers...")
individ_clean = filter(row -> 
    !ismissing(row.user_country) && row.user_country == "United States", 
    individ)
n_us = nrow(individ_clean)
println("After US filter: $n_us (dropped $(n_original - n_us))")

# Drop Native (too small for analysis)
println("\nDropping Native category (n too small)...")
individ_clean = filter(row -> 
    !ismissing(row.ethnicity_predicted) && row.ethnicity_predicted != "Native", 
    individ_clean)
n_no_native = nrow(individ_clean)
println("After dropping Native: $n_no_native (dropped $(n_us - n_no_native))")

# Drop rows with missing key variables
println("\nDropping rows with missing key variables...")
key_vars = [:user_id, :rcid, :seniority, :startdate, :enddate, :ethnicity_predicted]
for var in key_vars
    global individ_clean  # Fix scoping issue
    before = nrow(individ_clean)
    individ_clean = filter(row -> !ismissing(row[var]), individ_clean)
    after = nrow(individ_clean)
    if before != after
        println("  $var: dropped $(before - after) rows")
    end
end

n_final = nrow(individ_clean)
println("\nFinal clean records: $n_final")
println("Total dropped: $(n_original - n_final) ($(round(100*(n_original-n_final)/n_original, digits=1))%)")

## Final Ethnicity Distribution ##
println("\n--- Final Ethnicity Distribution ---")
eth_counts_final = combine(groupby(individ_clean, :ethnicity_predicted), nrow => :count)
eth_counts_final.percent = round.(100 .* eth_counts_final.count ./ sum(eth_counts_final.count), digits=2)
sort!(eth_counts_final, :count, rev=true)
println(eth_counts_final)

## Summary Statistics ##
println("\n--- Summary Statistics for Key Variables ---")
println("\nSeniority:")
println("  Mean: $(round(mean(individ_clean.seniority), digits=2))")
println("  Median: $(median(individ_clean.seniority))")
println("  Min: $(minimum(individ_clean.seniority)), Max: $(maximum(individ_clean.seniority))")

println("\nSalary:")
salary_clean = filter(!ismissing, individ_clean.salary)
println("  Mean: \$$(round(mean(salary_clean), digits=0))")
println("  Median: \$$(round(median(salary_clean), digits=0))")

println("\nTotal Compensation:")
comp_clean = filter(!ismissing, individ_clean.total_compensation)
println("  Mean: \$$(round(mean(comp_clean), digits=0))")
println("  Median: \$$(round(median(comp_clean), digits=0))")

## Save Cleaned Data ##
println("\n" * "="^60)
println("SAVING CLEANED DATA")
println("="^60)

# Save as CSV for portability
output_file = joinpath(OUTPUT_PATH, "individ_clean.csv")
println("\nSaving to: $output_file")
@time CSV.write(output_file, individ_clean)

println("\nScript 01 complete!")
println("Next: Run 02_create_panel.jl")
