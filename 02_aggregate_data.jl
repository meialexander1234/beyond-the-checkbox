######################################################################
# FILE: 02_aggregate_data.jl
#
# Purpose: Aggregate person-job spells to ethnicity × year panel
#          (classic longitudinal format for growth curve analysis)
#
# Output:  longitude_data.csv — ethnicity × year panel
#          longitude_gender.csv — ethnicity × year × gender
#          longitude_jobcat.csv — ethnicity × year × job category
#          firm_blau.csv — firm × year diversity index
#
# Author: Jessica Alexander
######################################################################

using DataFrames
using CSV
using Dates
using Statistics

println("="^60)
println("SCRIPT 02: AGGREGATE TO LONGITUDE FORMAT")
println("="^60)

## Set paths ##
const PROJECT_PATH = "C:/jessiepaper"
const OUTPUT_PATH = joinpath(PROJECT_PATH, "julia", "output")

## Load Cleaned Data ##
println("\nLoading cleaned data...")
input_file = joinpath(OUTPUT_PATH, "individ_clean.csv")
@time individ = CSV.read(input_file, DataFrame)

println("Loaded $(nrow(individ)) person-job spells")
println("Unique individuals: $(length(unique(individ.user_id)))")

## Parse Dates ##
println("\nParsing dates...")
if eltype(individ.startdate) == String
    individ.startdate = Date.(individ.startdate)
    individ.enddate = Date.(individ.enddate)
end

individ.start_year = year.(individ.startdate)
individ.end_year = year.(individ.enddate)

println("Year range in data: $(minimum(individ.start_year)) to $(maximum(individ.end_year))")

## Create Analysis Variables ##
println("\nCreating analysis variables...")

# Female indicator (1 = female, 0 = male)
individ.female = (individ.sex_predicted .== "F") .* 1

# Education encoding (1-5 scale)
edu_map = Dict(
    "High School" => 1,
    "Associate" => 2,
    "Bachelor" => 3,
    "Master" => 4,
    "MBA" => 4,
    "Doctor" => 5
)
individ.edu_level = [get(edu_map, string(e), 0) for e in individ.highest_degree]

# Log outcomes
individ.log_salary = log.(max.(individ.salary, 1.0))
individ.log_comp = log.(max.(individ.total_compensation, 1.0))

## ============================================================
## STEP 1: EXPAND SPELLS TO PERSON-YEARS AND AGGREGATE
## ============================================================
println("\n" * "="^60)
println("STEP 1: CREATING ETHNICITY × YEAR PANEL")
println("="^60)

# Process in batches to manage memory
# For each spell, determine which calendar years the person was employed
# Then aggregate statistics by ethnicity × year

println("\nProcessing spells and aggregating by ethnicity × year...")

# Dictionary to accumulate stats: key = (ethnicity, year)
yearly_stats = Dict{Tuple{String, Int}, Dict{String, Vector{Float64}}}()

# Also track by ethnicity × year × gender
yearly_gender_stats = Dict{Tuple{String, Int, Int}, Dict{String, Vector{Float64}}}()

# And by ethnicity × year × jobcat
yearly_jobcat_stats = Dict{Tuple{String, Int, String}, Dict{String, Vector{Float64}}}()

# For firm Blau index: track ethnicity counts per firm × year
firm_year_eth = Dict{Tuple{Int32, Int}, Dict{String, Int}}()

batch_size = 500_000
n_rows = nrow(individ)
n_batches = ceil(Int, n_rows / batch_size)

for batch in 1:n_batches
    start_idx = (batch - 1) * batch_size + 1
    end_idx = min(batch * batch_size, n_rows)
    
    print("  Batch $batch/$n_batches (rows $start_idx to $end_idx)... ")
    
    batch_data = individ[start_idx:end_idx, :]
    
    for row in eachrow(batch_data)
        start_yr = row.start_year
        end_yr = min(row.end_year, 2024)
        
        # If job ended Jan 1, don't count that year
        if month(row.enddate) == 1 && day(row.enddate) == 1
            end_yr = end_yr - 1
        end
        
        if end_yr < start_yr
            continue
        end
        
        ethnicity = row.ethnicity_predicted
        gender = row.female
        jobcat = row.jobcats
        rcid = row.rcid
        
        for yr in start_yr:end_yr
            # Tenure = years since start of this spell
            tenure = yr - start_yr
            
            # --- Ethnicity × Year ---
            key = (ethnicity, yr)
            if !haskey(yearly_stats, key)
                yearly_stats[key] = Dict(
                    "seniority" => Float64[],
                    "log_salary" => Float64[],
                    "log_comp" => Float64[],
                    "female" => Float64[],
                    "edu_level" => Float64[],
                    "tenure" => Float64[]
                )
            end
            push!(yearly_stats[key]["seniority"], Float64(row.seniority))
            push!(yearly_stats[key]["log_salary"], row.log_salary)
            push!(yearly_stats[key]["log_comp"], row.log_comp)
            push!(yearly_stats[key]["female"], Float64(gender))
            push!(yearly_stats[key]["edu_level"], Float64(row.edu_level))
            push!(yearly_stats[key]["tenure"], Float64(tenure))
            
            # --- Ethnicity × Year × Gender ---
            key_g = (ethnicity, yr, gender)
            if !haskey(yearly_gender_stats, key_g)
                yearly_gender_stats[key_g] = Dict(
                    "seniority" => Float64[],
                    "log_salary" => Float64[],
                    "log_comp" => Float64[],
                    "edu_level" => Float64[],
                    "tenure" => Float64[]
                )
            end
            push!(yearly_gender_stats[key_g]["seniority"], Float64(row.seniority))
            push!(yearly_gender_stats[key_g]["log_salary"], row.log_salary)
            push!(yearly_gender_stats[key_g]["log_comp"], row.log_comp)
            push!(yearly_gender_stats[key_g]["edu_level"], Float64(row.edu_level))
            push!(yearly_gender_stats[key_g]["tenure"], Float64(tenure))
            
            # --- Ethnicity × Year × Jobcat ---
            key_j = (ethnicity, yr, jobcat)
            if !haskey(yearly_jobcat_stats, key_j)
                yearly_jobcat_stats[key_j] = Dict(
                    "seniority" => Float64[],
                    "log_salary" => Float64[],
                    "log_comp" => Float64[],
                    "female" => Float64[],
                    "edu_level" => Float64[],
                    "tenure" => Float64[]
                )
            end
            push!(yearly_jobcat_stats[key_j]["seniority"], Float64(row.seniority))
            push!(yearly_jobcat_stats[key_j]["log_salary"], row.log_salary)
            push!(yearly_jobcat_stats[key_j]["log_comp"], row.log_comp)
            push!(yearly_jobcat_stats[key_j]["female"], Float64(gender))
            push!(yearly_jobcat_stats[key_j]["edu_level"], Float64(row.edu_level))
            push!(yearly_jobcat_stats[key_j]["tenure"], Float64(tenure))
            
            # --- Firm × Year × Ethnicity (for Blau index) ---
            key_f = (rcid, yr)
            if !haskey(firm_year_eth, key_f)
                firm_year_eth[key_f] = Dict{String, Int}()
            end
            firm_year_eth[key_f][ethnicity] = get(firm_year_eth[key_f], ethnicity, 0) + 1
        end
    end
    
    println("done")
end

## ============================================================
## STEP 2: CONVERT TO DATAFRAMES
## ============================================================
println("\n" * "="^60)
println("STEP 2: CONVERTING TO DATAFRAMES")
println("="^60)

# --- Ethnicity × Year ---
println("\nCreating longitude_data (ethnicity × year)...")
rows_main = []
for ((ethnicity, yr), stats) in yearly_stats
    n = length(stats["seniority"])
    push!(rows_main, (
        ethnicity = ethnicity,
        year = yr,
        mean_seniority = mean(stats["seniority"]),
        sd_seniority = n > 1 ? std(stats["seniority"]) : 0.0,
        mean_log_salary = mean(stats["log_salary"]),
        sd_log_salary = n > 1 ? std(stats["log_salary"]) : 0.0,
        mean_log_comp = mean(stats["log_comp"]),
        mean_tenure = mean(stats["tenure"]),
        sd_tenure = n > 1 ? std(stats["tenure"]) : 0.0,
        pct_female = mean(stats["female"]),
        mean_edu = mean(stats["edu_level"]),
        n_obs = n
    ))
end
longitude_data = DataFrame(rows_main)

# Round and sort
longitude_data.mean_seniority = round.(longitude_data.mean_seniority, digits=4)
longitude_data.sd_seniority = round.(longitude_data.sd_seniority, digits=4)
longitude_data.mean_log_salary = round.(longitude_data.mean_log_salary, digits=4)
longitude_data.sd_log_salary = round.(longitude_data.sd_log_salary, digits=4)
longitude_data.mean_log_comp = round.(longitude_data.mean_log_comp, digits=4)
longitude_data.mean_tenure = round.(longitude_data.mean_tenure, digits=2)
longitude_data.sd_tenure = round.(longitude_data.sd_tenure, digits=2)
longitude_data.pct_female = round.(longitude_data.pct_female, digits=4)
longitude_data.mean_edu = round.(longitude_data.mean_edu, digits=2)

sort!(longitude_data, [:ethnicity, :year])

println("  Created $(nrow(longitude_data)) rows")

# --- Ethnicity × Year × Gender ---
println("\nCreating longitude_gender (ethnicity × year × gender)...")
rows_gender = []
for ((ethnicity, yr, gender), stats) in yearly_gender_stats
    n = length(stats["seniority"])
    push!(rows_gender, (
        ethnicity = ethnicity,
        year = yr,
        female = gender,
        mean_seniority = round(mean(stats["seniority"]), digits=4),
        sd_seniority = round(n > 1 ? std(stats["seniority"]) : 0.0, digits=4),
        mean_log_salary = round(mean(stats["log_salary"]), digits=4),
        mean_log_comp = round(mean(stats["log_comp"]), digits=4),
        mean_tenure = round(mean(stats["tenure"]), digits=2),
        mean_edu = round(mean(stats["edu_level"]), digits=2),
        n_obs = n
    ))
end
longitude_gender = DataFrame(rows_gender)
sort!(longitude_gender, [:ethnicity, :year, :female])
println("  Created $(nrow(longitude_gender)) rows")

# --- Ethnicity × Year × Jobcat ---
println("\nCreating longitude_jobcat (ethnicity × year × jobcat)...")
rows_jobcat = []
for ((ethnicity, yr, jobcat), stats) in yearly_jobcat_stats
    n = length(stats["seniority"])
    push!(rows_jobcat, (
        ethnicity = ethnicity,
        year = yr,
        jobcat = jobcat,
        mean_seniority = round(mean(stats["seniority"]), digits=4),
        sd_seniority = round(n > 1 ? std(stats["seniority"]) : 0.0, digits=4),
        mean_log_salary = round(mean(stats["log_salary"]), digits=4),
        mean_log_comp = round(mean(stats["log_comp"]), digits=4),
        mean_tenure = round(mean(stats["tenure"]), digits=2),
        pct_female = round(mean(stats["female"]), digits=4),
        mean_edu = round(mean(stats["edu_level"]), digits=2),
        n_obs = n
    ))
end
longitude_jobcat = DataFrame(rows_jobcat)
sort!(longitude_jobcat, [:ethnicity, :year, :jobcat])
println("  Created $(nrow(longitude_jobcat)) rows")

# --- Firm × Year Blau Index ---
println("\nComputing firm-level Blau index...")
rows_firm = []
for ((rcid, yr), eth_counts) in firm_year_eth
    total = sum(values(eth_counts))
    if total < 10  # Skip very small firm-years
        continue
    end
    
    # Blau index = 1 - sum(p_i^2)
    proportions = [count / total for count in values(eth_counts)]
    blau = 1.0 - sum(p^2 for p in proportions)
    
    push!(rows_firm, (
        rcid = rcid,
        year = yr,
        blau_index = round(blau, digits=4),
        n_employees = total,
        n_ethnicities = length(eth_counts)
    ))
end
firm_blau = DataFrame(rows_firm)
sort!(firm_blau, [:rcid, :year])
println("  Created $(nrow(firm_blau)) firm-year observations")

## ============================================================
## STEP 3: SUMMARY STATISTICS
## ============================================================
println("\n" * "="^60)
println("SUMMARY STATISTICS")
println("="^60)

println("\n--- Longitude Data (Ethnicity × Year) ---")
println("Rows: $(nrow(longitude_data))")
println("Years: $(minimum(longitude_data.year)) to $(maximum(longitude_data.year))")
println("Ethnicities: $(length(unique(longitude_data.ethnicity)))")

println("\nSample (first 15 rows):")
println(first(longitude_data, 15))

println("\n--- Total Observations by Ethnicity ---")
eth_totals = combine(groupby(longitude_data, :ethnicity), 
    :n_obs => sum => :total_obs,
    :mean_seniority => mean => :avg_seniority,
    :mean_log_salary => mean => :avg_log_salary
)
eth_totals.avg_seniority = round.(eth_totals.avg_seniority, digits=2)
eth_totals.avg_log_salary = round.(eth_totals.avg_log_salary, digits=3)
sort!(eth_totals, :total_obs, rev=true)
println(eth_totals)

println("\n--- Observations by Year (sample) ---")
year_totals = combine(groupby(longitude_data, :year), :n_obs => sum => :total_obs)
sort!(year_totals, :year)
println("First 5 years:")
println(first(year_totals, 5))
println("Last 5 years:")
println(last(year_totals, 5))

println("\n--- Firm Blau Index Distribution ---")
println("  Mean Blau: $(round(mean(firm_blau.blau_index), digits=3))")
println("  Median Blau: $(round(median(firm_blau.blau_index), digits=3))")
println("  Min: $(round(minimum(firm_blau.blau_index), digits=3))")
println("  Max: $(round(maximum(firm_blau.blau_index), digits=3))")

## ============================================================
## STEP 4: SAVE FILES
## ============================================================
println("\n" * "="^60)
println("SAVING FILES")
println("="^60)

# Main longitude data
f1 = joinpath(OUTPUT_PATH, "longitude_data.csv")
CSV.write(f1, longitude_data)
println("  Saved: longitude_data.csv ($(nrow(longitude_data)) rows)")

# Gender breakdown
f2 = joinpath(OUTPUT_PATH, "longitude_gender.csv")
CSV.write(f2, longitude_gender)
println("  Saved: longitude_gender.csv ($(nrow(longitude_gender)) rows)")

# Job category breakdown
f3 = joinpath(OUTPUT_PATH, "longitude_jobcat.csv")
CSV.write(f3, longitude_jobcat)
println("  Saved: longitude_jobcat.csv ($(nrow(longitude_jobcat)) rows)")

# Firm Blau index
f4 = joinpath(OUTPUT_PATH, "firm_blau.csv")
CSV.write(f4, firm_blau)
println("  Saved: firm_blau.csv ($(nrow(firm_blau)) rows)")

# Ethnicity summary (for Table 1)
f5 = joinpath(OUTPUT_PATH, "ethnicity_summary.csv")
CSV.write(f5, eth_totals)
println("  Saved: ethnicity_summary.csv")

## ============================================================
## DONE
## ============================================================
println("\n" * "="^60)
println("SCRIPT 02 COMPLETE")
println("="^60)
println("""
Files created:
  1. longitude_data.csv     - Main panel: ethnicity × year
  2. longitude_gender.csv   - Panel: ethnicity × year × gender (for H4)
  3. longitude_jobcat.csv   - Panel: ethnicity × year × jobcat (for H3)
  4. firm_blau.csv          - Firm diversity index by year (for H5)
  5. ethnicity_summary.csv  - Overall summary by ethnicity

Next: Run 03_descriptives.jl
""")
