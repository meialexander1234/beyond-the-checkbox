# ============================================================
# SCRIPT 2: COVID Natural Experiment
# ============================================================
# Save as: covid_experiment.jl

using RData, DataFrames, Statistics, Dates, MixedModels, Distributions, CSV

println("="^60)
println("COVID NATURAL EXPERIMENT")
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

# COVID period indicator
usa.covid_period = ifelse.(usa.year .>= 2020, 1, 0)

# Create panel variables
person_start = combine(groupby(usa, :user_id), :year => minimum => :career_start)
usa = leftjoin(usa, person_start, on=:user_id)
usa.tenure = usa.year .- usa.career_start
usa = filter(row -> row.tenure >= 0 && row.tenure <= 20, usa)

edu_map = Dict("High School" => 1, "Associate" => 2, "Bachelor" => 3, 
               "Master" => 4, "MBA" => 4, "PhD" => 5, "MD" => 5, "JD" => 5)
usa.edu_num = [get(edu_map, d, 3) for d in usa.highest_degree]

person_obs = combine(groupby(usa, :user_id), nrow => :n_obs)
usa = leftjoin(usa, person_obs, on=:user_id)
usa_long = filter(row -> row.n_obs >= 2, usa)
usa_long.person_id = string.(usa_long.user_id)

println("Total observations: ", nrow(usa_long))
println("Pre-COVID (2000-2019): ", sum(usa_long.covid_period .== 0))
println("COVID era (2020-2024): ", sum(usa_long.covid_period .== 1))

# === DESCRIPTIVES BY PERIOD ===
println("\n=== DESCRIPTIVES BY PERIOD ===\n")

desc = combine(groupby(usa_long, [:covid_period, :high_api, :multiple]),
    :user_id => (x -> length(unique(x))) => :n_persons,
    :seniority => mean => :mean_sen
)
desc.mean_sen = round.(desc.mean_sen, digits=3)
sort!(desc, [:covid_period, :high_api, :multiple])
println(desc)

# === MODEL 1: BASE (replication) ===
println("\n=== MODEL 1: BASE DiD ===\n")

m1 = fit(MixedModel, 
    @formula(seniority ~ 1 + tenure * multiple * high_api + 
             edu_num + (1 | person_id)), 
    usa_long, REML=true)
println(m1)

# === MODEL 2: ADD COVID PERIOD ===
println("\n=== MODEL 2: ADD COVID PERIOD ===\n")

m2 = fit(MixedModel, 
    @formula(seniority ~ 1 + tenure * multiple * high_api + 
             covid_period + edu_num + (1 | person_id)), 
    usa_long, REML=true)
println(m2)

# === MODEL 3: COVID × REGIONAL PENALTY INTERACTION ===
println("\n=== MODEL 3: COVID × MULTIPLE × HIGH_API ===\n")

m3 = fit(MixedModel, 
    @formula(seniority ~ 1 + tenure * multiple * high_api * covid_period + 
             edu_num + (1 | person_id)), 
    usa_long, REML=true)
println(m3)

# === EXTRACT COVID RESULTS ===
println("\n" * "="^60)
println("COVID NATURAL EXPERIMENT RESULTS")
println("="^60)

coefs = fixef(m3)
se = stderror(m3)
names_m3 = coefnames(m3)

println("\nCOVID-related coefficients:")
for (i, name) in enumerate(names_m3)
    if occursin("covid", name)
        t_val = coefs[i] / se[i]
        p_val = 2 * (1 - cdf(Normal(), abs(t_val)))
        sig = p_val < 0.001 ? "***" : (p_val < 0.01 ? "**" : (p_val < 0.05 ? "*" : (p_val < 0.10 ? "†" : "")))
        println("  ", rpad(name, 45), round(coefs[i], digits=5), "  (p=", round(p_val, digits=4), ") ", sig)
    end
end

# Find the key interaction
idx_covid_mult_api = findfirst(x -> occursin("covid", x) && occursin("multiple", x) && occursin("high_api", x) && !occursin("tenure", x), names_m3)
if idx_covid_mult_api !== nothing
    covid_effect = coefs[idx_covid_mult_api]
    covid_se = se[idx_covid_mult_api]
    covid_p = 2 * (1 - cdf(Normal(), abs(covid_effect / covid_se)))
    
    println("\n" * "="^60)
    println("HYPOTHESIS TEST")
    println("="^60)
    println("\nPrediction: Regional penalty ATTENUATED during COVID (remote work)")
    println("Test: multiple × high_api × covid_period > 0 (penalty smaller)")
    println()
    println("Estimate: ", round(covid_effect, digits=4))
    println("p-value: ", round(covid_p, digits=4))
    println("Result: ", (covid_effect > 0 && covid_p < 0.05) ? "SUPPORTED ✓" : 
                        (covid_effect > 0 ? "Directionally supported (check p)" : "NOT SUPPORTED ✗"))
end

# === SPLIT SAMPLE ANALYSIS ===
println("\n=== SPLIT SAMPLE: PRE-COVID vs COVID ERA ===\n")

pre_covid = filter(row -> row.covid_period == 0, usa_long)
covid_era = filter(row -> row.covid_period == 1, usa_long)

println("--- PRE-COVID (2000-2019) ---")
m_pre = fit(MixedModel, 
    @formula(seniority ~ 1 + tenure * multiple * high_api + edu_num + (1 | person_id)), 
    pre_covid, REML=true)

coefs_pre = fixef(m_pre)
names_pre = coefnames(m_pre)
idx_pre = findfirst(x -> x == "multiple & high_api", names_pre)
println("multiple × high_api: ", round(coefs_pre[idx_pre], digits=4))

println("\n--- COVID ERA (2020-2024) ---")
m_covid = fit(MixedModel, 
    @formula(seniority ~ 1 + tenure * multiple * high_api + edu_num + (1 | person_id)), 
    covid_era, REML=true)

coefs_covid = fixef(m_covid)
names_covid = coefnames(m_covid)
idx_covid = findfirst(x -> x == "multiple & high_api", names_covid)
println("multiple × high_api: ", round(coefs_covid[idx_covid], digits=4))

println("\n=== COMPARISON ===")
println("Pre-COVID penalty:  ", round(coefs_pre[idx_pre], digits=4))
println("COVID-era penalty:  ", round(coefs_covid[idx_covid], digits=4))
println("Difference:         ", round(coefs_covid[idx_covid] - coefs_pre[idx_pre], digits=4))
println("Interpretation:     ", coefs_covid[idx_covid] > coefs_pre[idx_pre] ? 
        "Penalty SMALLER during COVID ✓" : "Penalty LARGER during COVID")

# === SAVE RESULTS ===
results = DataFrame(
    term = names_m3,
    estimate = round.(coefs, digits=6),
    std_error = round.(se, digits=6)
)
CSV.write("C:/jessiepaper/julia/output/covid_experiment_coefficients.csv", results)
println("\nSaved: covid_experiment_coefficients.csv")

println("\nDone!")