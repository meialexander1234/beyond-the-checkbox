# ============================================================
# SCRIPT 4: Dose-Response Test (BISG Ambiguity Strength)
# ============================================================
# Save as: dose_response.jl

using RData, DataFrames, Statistics, Dates, MixedModels, Distributions, CSV

println("="^60)
println("DOSE-RESPONSE TEST: BISG AMBIGUITY STRENGTH")
println("="^60)

println("\nLoading data...")
individ = load("C:/jessiepaper/data/individ.RData")["individ"]
usa = DataFrame(individ)

# Check what columns are available
println("\nAvailable columns:")
println(names(usa))

# Look for BISG probability columns
bisg_cols = filter(x -> occursin("prob", lowercase(x)) || occursin("bisg", lowercase(x)) || 
                        occursin("score", lowercase(x)) || occursin("confidence", lowercase(x)), names(usa))
println("\nPotential BISG columns: ", bisg_cols)

# Filter to USA, regional states
usa = filter(row -> row.country == "United States", usa)
usa.year = year.(usa.startdate)
usa = filter(row -> row.year >= 2000 && row.year <= 2024, usa)

high_api_states = ["California", "Hawaii", "Washington"]
low_api_states = ["Georgia", "North Carolina", "Alabama", "Mississippi", 
                  "South Carolina", "Louisiana", "Maryland", "Texas", "Florida"]
usa = filter(row -> row.state in vcat(high_api_states, low_api_states), usa)

usa.high_api = ifelse.(in.(usa.state, Ref(high_api_states)), 1, 0)

# Focus on Multiple only for dose-response
usa_multiple = filter(row -> row.ethnicity_predicted == "Multiple", usa)

println("\nMultiple observations: ", nrow(usa_multiple))

# === CHECK FOR BISG PROBABILITY DATA ===
println("\n=== CHECKING FOR BISG PROBABILITY DATA ===\n")

# If no probability columns, we need to create a proxy
# One option: use the "numconnections" or other features as proxy for visibility/ambiguity

# Check if there are any numeric columns that might relate to classification confidence
numeric_cols = names(usa_multiple)[eltype.(eachcol(usa_multiple)) .<: Union{Number, Missing}]
println("Numeric columns available: ", numeric_cols)

# === ALTERNATIVE: CREATE AMBIGUITY PROXY ===
println("\n=== CREATING AMBIGUITY PROXY ===\n")

# Since we don't have raw BISG probabilities, we can use:
# 1. Name-based proxy: common vs uncommon surnames
# 2. Geographic proxy: diversity of location
# 3. Network proxy: numconnections as visibility measure

# For now, let's check if the data supports any of these
if "numconnections" in names(usa_multiple)
    println("Network connections available")
    println("  Mean connections: ", round(mean(skipmissing(usa_multiple.numconnections)), digits=1))
    println("  SD connections: ", round(std(skipmissing(usa_multiple.numconnections)), digits=1))
    
    # More connections = more visible = categorization matters more
    usa_multiple.high_visibility = ifelse.(coalesce.(usa_multiple.numconnections, 0) .> 
                                           median(skipmissing(usa_multiple.numconnections)), 1, 0)
end

# === IF NO BISG PROBABILITIES, REPORT LIMITATION ===
println("\n" * "="^60)
println("DOSE-RESPONSE TEST STATUS")
println("="^60)

println("\nThe dose-response test requires raw BISG probability scores")
println("(e.g., probability of White, probability of Black, etc.)")
println("to compute a continuous measure of classification ambiguity.")
println()
println("Available data does NOT include raw BISG probabilities.")
println()
println("Alternative approaches:")
println("1. Request BISG probabilities from data provider")
println("2. Re-run BISG algorithm on names to generate probabilities")
println("3. Use proxy measures (e.g., surname frequency, geographic diversity)")
println()
println("STATUS: CANNOT BE COMPLETED WITH CURRENT DATA")

# === EXPLORATORY: Regional variation among Multiple ===
println("\n=== EXPLORATORY: VARIATION AMONG MULTIPLE BY STATE ===\n")

state_variation = combine(groupby(usa_multiple, :state),
    :seniority => mean => :mean_sen,
    :seniority => std => :sd_sen,
    nrow => :n
)
state_variation = filter(row -> row.n >= 50, state_variation)
state_variation.mean_sen = round.(state_variation.mean_sen, digits=3)
state_variation.sd_sen = round.(state_variation.sd_sen, digits=3)
sort!(state_variation, :mean_sen)
println(state_variation)

println("\nInterpretation:")
println("  If BISG probabilities were available, we would test whether")
println("  workers with MORE ambiguous classifications (bimodal probability")
println("  distributions) show LARGER penalties than those with clear")
println("  classifications.")

# === SAVE STATUS ===
status = DataFrame(
    test = ["Dose-Response Test"],
    status = ["Cannot be completed - raw BISG probabilities not available"],
    alternative = ["Request BISG probabilities from data provider or re-run BISG algorithm"]
)
CSV.write("C:/jessiepaper/julia/output/dose_response_status.csv", status)
println("\nSaved: dose_response_status.csv")

println("\nDone!")