# ============================================================
# SCRIPT 3: Firm-Switching Reset Test
# ============================================================
# Save as: firm_switching.jl

using RData, DataFrames, Statistics, Dates, MixedModels, Distributions, CSV

println("="^60)
println("FIRM-SWITCHING RESET TEST")
println("="^60)

println("\nLoading data...")
individ = load("C:/jessiepaper/data/individ.RData")["individ"]
usa = DataFrame(individ)

# Filter to USA, White + Multiple, regional states
usa = filter(row -> row.country == "United States" && 
             row.ethnicity_predicted in ["White", "Multiple"], usa)
usa.year = year.(usa.startdate)
usa = filter(row -> row.year >= 2000 && row.year <= 2024, usa)

high_api_states = ["California", "Hawaii", "Washington"]
low_api_states = ["Georgia", "North Carolina", "Alabama", "Mississippi", 
                  "South Carolina", "Louisiana", "Maryland", "Texas", "Florida"]
usa = filter(row -> row.state in vcat(high_api_states, low_api_states), usa)

usa.high_api = ifelse.(in.(usa.state, Ref(high_api_states)), 1, 0)
usa.multiple = ifelse.(usa.ethnicity_predicted .== "Multiple", 1, 0)

println("Total observations: ", nrow(usa))
println("Unique firms (rcid): ", length(unique(skipmissing(usa.rcid))))

# === IDENTIFY FIRM SWITCHES ===
println("\n=== IDENTIFYING FIRM SWITCHES ===\n")

# Sort by person and year
sort!(usa, [:user_id, :year])

# Create lagged firm ID
usa.rcid_str = string.(coalesce.(usa.rcid, "missing"))

# Group by person and identify firm changes
function identify_firm_tenure(df)
    n = nrow(df)
    firm_tenure = zeros(Int, n)
    new_firm = zeros(Int, n)
    
    current_firm = df.rcid_str[1]
    tenure_at_firm = 1
    
    for i in 1:n
        if df.rcid_str[i] != current_firm
            current_firm = df.rcid_str[i]
            tenure_at_firm = 1
            new_firm[i] = 1
        end
        firm_tenure[i] = tenure_at_firm
        tenure_at_firm += 1
    end
    
    return (firm_tenure=firm_tenure, new_firm=new_firm)
end

# Apply to each person
person_groups = groupby(usa, :user_id)
firm_data = combine(person_groups, 
    [:rcid_str] => (x -> identify_firm_tenure(DataFrame(rcid_str=x))) => AsTable)

# This is tricky - let's do it differently
# Create firm tenure within each person-firm spell

usa_sorted = sort(usa, [:user_id, :year])

# Add row index
usa_sorted.row_idx = 1:nrow(usa_sorted)

# Create person-firm spells
usa_sorted.person_firm = string.(usa_sorted.user_id) .* "_" .* usa_sorted.rcid_str

# Calculate tenure at current firm
spell_start = combine(groupby(usa_sorted, [:user_id, :person_firm]), 
    :year => minimum => :spell_start_year,
    :row_idx => first => :first_row)
usa_sorted = leftjoin(usa_sorted, spell_start, on=[:user_id, :person_firm])
usa_sorted.firm_tenure = usa_sorted.year .- usa_sorted.spell_start_year

# Identify if this is year 1-2 at firm vs later
usa_sorted.early_at_firm = ifelse.(usa_sorted.firm_tenure .<= 1, 1, 0)

# Count firm switches per person
person_firms = combine(groupby(usa_sorted, :user_id), 
    :person_firm => (x -> length(unique(x))) => :n_firms)
usa_sorted = leftjoin(usa_sorted, person_firms, on=:user_id)

# Filter to people who switched firms at least once
switchers = filter(row -> row.n_firms >= 2, usa_sorted)

println("People who switched firms: ", length(unique(switchers.user_id)))
println("Observations from switchers: ", nrow(switchers))

# === DESCRIPTIVES ===
println("\n=== DESCRIPTIVES: EARLY VS LATER AT FIRM ===\n")

desc = combine(groupby(switchers, [:early_at_firm, :high_api, :multiple]),
    :user_id => (x -> length(unique(x))) => :n_persons,
    :seniority => mean => :mean_sen,
    :firm_tenure => mean => :mean_firm_tenure
)
desc.mean_sen = round.(desc.mean_sen, digits=3)
desc.mean_firm_tenure = round.(desc.mean_firm_tenure, digits=2)
sort!(desc, [:early_at_firm, :high_api, :multiple])
println(desc)

# === PREPARE FOR MODELING ===

# Education
edu_map = Dict("High School" => 1, "Associate" => 2, "Bachelor" => 3, 
               "Master" => 4, "MBA" => 4, "PhD" => 5, "MD" => 5, "JD" => 5)
switchers.edu_num = [get(edu_map, d, 3) for d in switchers.highest_degree]

# Career tenure
person_start = combine(groupby(switchers, :user_id), :year => minimum => :career_start)
switchers = leftjoin(switchers, person_start, on=:user_id)
switchers.career_tenure = switchers.year .- switchers.career_start

# Filter to 2+ obs
person_obs = combine(groupby(switchers, :user_id), nrow => :n_obs)
switchers = leftjoin(switchers, person_obs, on=:user_id)
switchers = filter(row -> row.n_obs >= 2, switchers)
switchers.person_id = string.(switchers.user_id)

println("\nFinal sample for firm-switching analysis: ", nrow(switchers))

# === MODEL 1: BASE EFFECT ===
println("\n=== MODEL 1: BASE REGIONAL PENALTY (SWITCHERS ONLY) ===\n")

m1 = fit(MixedModel, 
    @formula(seniority ~ 1 + career_tenure * multiple * high_api + 
             edu_num + (1 | person_id)), 
    switchers, REML=true)
println(m1)

# === MODEL 2: EARLY VS LATER AT FIRM ===
println("\n=== MODEL 2: EARLY AT FIRM INTERACTION ===\n")

m2 = fit(MixedModel, 
    @formula(seniority ~ 1 + career_tenure * multiple * high_api + 
             early_at_firm * multiple * high_api +
             edu_num + (1 | person_id)), 
    switchers, REML=true)
println(m2)

# === EXTRACT RESULTS ===
println("\n" * "="^60)
println("FIRM-SWITCHING RESET TEST RESULTS")
println("="^60)

coefs = fixef(m2)
se = stderror(m2)
names_m2 = coefnames(m2)

println("\nEarly-at-firm coefficients:")
for (i, name) in enumerate(names_m2)
    if occursin("early_at_firm", name)
        t_val = coefs[i] / se[i]
        p_val = 2 * (1 - cdf(Normal(), abs(t_val)))
        sig = p_val < 0.001 ? "***" : (p_val < 0.01 ? "**" : (p_val < 0.05 ? "*" : (p_val < 0.10 ? "†" : "")))
        println("  ", rpad(name, 40), round(coefs[i], digits=5), "  (p=", round(p_val, digits=4), ") ", sig)
    end
end

idx_reset = findfirst(x -> occursin("early_at_firm") && occursin("multiple") && occursin("high_api"), names_m2)
if idx_reset !== nothing
    reset_effect = coefs[idx_reset]
    reset_se = se[idx_reset]
    reset_p = 2 * (1 - cdf(Normal(), abs(reset_effect / reset_se)))
    
    println("\n" * "="^60)
    println("HYPOTHESIS TEST")
    println("="^60)
    println("\nPrediction: Penalty LARGER in first 1-2 years at new firm (reset effect)")
    println("Test: early_at_firm × multiple × high_api < 0")
    println()
    println("Estimate: ", round(reset_effect, digits=4))
    println("p-value: ", round(reset_p, digits=4))
    println("Result: ", (reset_effect < 0 && reset_p < 0.05) ? "SUPPORTED ✓" : 
                        (reset_effect < 0 ? "Directionally supported (check p)" : "NOT SUPPORTED ✗"))
end

# === SAVE RESULTS ===
results = DataFrame(
    term = names_m2,
    estimate = round.(coefs, digits=6),
    std_error = round.(se, digits=6)
)
CSV.write("C:/jessiepaper/julia/output/firm_switching_coefficients.csv", results)
println("\nSaved: firm_switching_coefficients.csv")

println("\nDone!")