using RData, DataFrames, Statistics, Dates, GLM, MixedModels, CategoricalArrays, Distributions, CSV

println("Loading data...")
individ = load("C:/jessiepaper/data/individ.RData")["individ"]

# Filter to USA, White + Multiple only, years 2000-2024
usa = DataFrame(individ)
usa = filter(row -> row.country == "United States" && 
             row.ethnicity_predicted in ["White", "Multiple"], usa)

usa.year = year.(usa.startdate)
usa = filter(row -> row.year >= 2000 && row.year <= 2024, usa)

println("Total USA records: ", nrow(usa))

# === DEFINE STATE GROUPS ===
high_api_states = ["California", "Hawaii", "Washington"]
low_api_states = ["Georgia", "North Carolina", "Alabama", 
                  "Mississippi", "South Carolina", "Louisiana", "Maryland",
                  "Texas", "Florida"]

usa = filter(row -> row.state in vcat(high_api_states, low_api_states), usa)
println("Filtered to selected states: ", nrow(usa))

# Create indicators
usa.high_api = ifelse.(in.(usa.state, Ref(high_api_states)), 1, 0)
usa.multiple = ifelse.(usa.ethnicity_predicted .== "Multiple", 1, 0)

# === CREATE PERSON-LEVEL PANEL ===
println("\nCreating person-level panel...")

person_start = combine(groupby(usa, :user_id), :year => minimum => :career_start)
usa = leftjoin(usa, person_start, on=:user_id)

usa.tenure = usa.year .- usa.career_start
usa = filter(row -> row.tenure >= 0 && row.tenure <= 20, usa)

# Center year at 2012 (midpoint)
usa.year_c = usa.year .- 2012

# Log salary
usa.log_salary = log.(max.(usa.salary, 1.0))

# Education numeric
edu_map = Dict("High School" => 1, "Associate" => 2, "Bachelor" => 3, 
               "Master" => 4, "MBA" => 4, "PhD" => 5, "MD" => 5, "JD" => 5)
usa.edu_num = [get(edu_map, d, 3) for d in usa.highest_degree]

# Period indicator
usa.late_period = ifelse.(usa.year .>= 2013, 1, 0)

# Count observations per person
person_obs = combine(groupby(usa, :user_id), nrow => :n_obs)
usa = leftjoin(usa, person_obs, on=:user_id)
usa_long = filter(row -> row.n_obs >= 2, usa)

usa_long.person_id = string.(usa_long.user_id)

println("Longitudinal sample: ", nrow(usa_long))
println("Unique persons: ", length(unique(usa_long.user_id)))
println("Year range: ", minimum(usa_long.year), " - ", maximum(usa_long.year))

# === DESCRIPTIVES BY PERIOD ===
println("\n=== SAMPLE BY PERIOD ===\n")

period_desc = combine(groupby(usa_long, [:late_period, :high_api, :multiple]),
    :user_id => (x -> length(unique(x))) => :n_persons,
    :seniority => mean => :mean_sen,
    :tenure => mean => :mean_tenure
)
period_desc.mean_sen = round.(period_desc.mean_sen, digits=3)
period_desc.mean_tenure = round.(period_desc.mean_tenure, digits=2)
sort!(period_desc, [:late_period, :high_api, :multiple])
println(period_desc)

# === MODEL 1: BASE DiD (replication) ===
println("\n=== MODEL 1: BASE DiD (No Time Trend) ===\n")

m1 = fit(MixedModel, 
    @formula(seniority ~ 1 + tenure * multiple * high_api + 
             edu_num + (1 | person_id)), 
    usa_long, REML=true)
println(m1)

# === MODEL 2: ADD CALENDAR YEAR ===
println("\n=== MODEL 2: ADD CALENDAR YEAR (Year_c) ===\n")

m2 = fit(MixedModel, 
    @formula(seniority ~ 1 + tenure * multiple * high_api + 
             year_c + edu_num + (1 | person_id)), 
    usa_long, REML=true)
println(m2)

# === MODEL 3: YEAR INTERACTIONS WITH MULTIPLE ===
println("\n=== MODEL 3: YEAR × MULTIPLE INTERACTION ===\n")

m3 = fit(MixedModel, 
    @formula(seniority ~ 1 + tenure * multiple * high_api + 
             year_c * multiple + edu_num + (1 | person_id)), 
    usa_long, REML=true)
println(m3)

# === MODEL 4: YEAR INTERACTIONS WITH MULTIPLE AND HIGH_API ===
println("\n=== MODEL 4: YEAR × MULTIPLE × HIGH_API ===\n")

m4 = fit(MixedModel, 
    @formula(seniority ~ 1 + tenure * multiple * high_api + 
             year_c * multiple * high_api + edu_num + (1 | person_id)), 
    usa_long, REML=true)
println(m4)

# === MODEL 5: FULL FOUR-WAY INTERACTION ===
println("\n=== MODEL 5: TENURE × MULTIPLE × HIGH_API × YEAR (Four-Way) ===\n")

m5 = fit(MixedModel, 
    @formula(seniority ~ 1 + tenure * multiple * high_api * year_c + 
             edu_num + (1 | person_id)), 
    usa_long, REML=true)
println(m5)

# === MODEL 6: PERIOD-BASED DiD (Early vs Late) ===
println("\n=== MODEL 6: PERIOD-BASED DiD (Early 2000-2012 vs Late 2013-2024) ===\n")

m6 = fit(MixedModel, 
    @formula(seniority ~ 1 + tenure * multiple * high_api * late_period + 
             edu_num + (1 | person_id)), 
    usa_long, REML=true)
println(m6)

# === EXTRACT KEY TIME-RELATED COEFFICIENTS ===
println("\n" * "="^70)
println("KEY TIME-RELATED FINDINGS")
println("="^70)

# From Model 4: Year × Multiple × High_API
coefs4 = fixef(m4)
se4 = stderror(m4)
names4 = coefnames(m4)

println("\nModel 4: Year interactions")
for (i, name) in enumerate(names4)
    if occursin("year_c", name)
        t_val = coefs4[i] / se4[i]
        p_val = 2 * (1 - cdf(Normal(), abs(t_val)))
        sig = p_val < 0.001 ? "***" : (p_val < 0.01 ? "**" : (p_val < 0.05 ? "*" : (p_val < 0.10 ? "†" : "")))
        println("  ", rpad(name, 40), round(coefs4[i], digits=5), "  (p=", round(p_val, digits=4), ") ", sig)
    end
end

# From Model 5: Four-way interaction
coefs5 = fixef(m5)
se5 = stderror(m5)
names5 = coefnames(m5)

println("\nModel 5: Four-way interaction terms")
for (i, name) in enumerate(names5)
    if occursin("year_c", name)
        t_val = coefs5[i] / se5[i]
        p_val = 2 * (1 - cdf(Normal(), abs(t_val)))
        sig = p_val < 0.001 ? "***" : (p_val < 0.01 ? "**" : (p_val < 0.05 ? "*" : (p_val < 0.10 ? "†" : "")))
        println("  ", rpad(name, 45), round(coefs5[i], digits=5), "  (p=", round(p_val, digits=4), ") ", sig)
    end
end

# From Model 6: Period-based
coefs6 = fixef(m6)
se6 = stderror(m6)
names6 = coefnames(m6)

println("\nModel 6: Period interactions (Late = 2013-2024)")
for (i, name) in enumerate(names6)
    if occursin("late_period", name)
        t_val = coefs6[i] / se6[i]
        p_val = 2 * (1 - cdf(Normal(), abs(t_val)))
        sig = p_val < 0.001 ? "***" : (p_val < 0.01 ? "**" : (p_val < 0.05 ? "*" : (p_val < 0.10 ? "†" : "")))
        println("  ", rpad(name, 50), round(coefs6[i], digits=5), "  (p=", round(p_val, digits=4), ") ", sig)
    end
end

# === COMPUTE TIME-VARYING GAPS ===
println("\n" * "="^70)
println("MULTIPLE VS WHITE GAP OVER TIME (from Model 4)")
println("="^70)

# Find coefficients
idx_mult = findfirst(x -> x == "multiple", names4)
idx_year_mult = findfirst(x -> x == "year_c & multiple", names4)
idx_year_mult_api = findfirst(x -> occursin("year_c") && occursin("multiple") && occursin("high_api"), names4)

b_mult = coefs4[idx_mult]
b_year_mult = idx_year_mult !== nothing ? coefs4[idx_year_mult] : 0.0
b_year_mult_api = idx_year_mult_api !== nothing ? coefs4[idx_year_mult_api] : 0.0

println("\nPredicted Multiple intercept gap by year (relative to White):")
println("\n        Year    Low-API Gap    High-API Gap")
for yr in [2000, 2005, 2010, 2015, 2020, 2024]
    yr_c = yr - 2012
    gap_low = b_mult + b_year_mult * yr_c
    gap_high = b_mult + b_year_mult * yr_c + b_year_mult_api * yr_c  # simplified
    println("        ", yr, "      ", round(gap_low, digits=3), "          ", round(gap_high, digits=3))
end

# === PERIOD-SPECIFIC DiD ===
println("\n" * "="^70)
println("PERIOD-SPECIFIC ANALYSIS")
println("="^70)

# Split data
early_data = filter(row -> row.year <= 2012, usa_long)
late_data = filter(row -> row.year >= 2013, usa_long)

println("\nEarly period (2000-2012): ", nrow(early_data), " observations")
println("Late period (2013-2024): ", nrow(late_data), " observations")

# Run separate models
println("\n--- EARLY PERIOD (2000-2012) ---\n")
m_early = fit(MixedModel, 
    @formula(seniority ~ 1 + tenure * multiple * high_api + 
             edu_num + (1 | person_id)), 
    early_data, REML=true)

coefs_early = fixef(m_early)
names_early = coefnames(m_early)
se_early = stderror(m_early)

idx_did_early = findfirst(x -> x == "tenure & multiple & high_api", names_early)
did_early = coefs_early[idx_did_early]
se_did_early = se_early[idx_did_early]
t_early = did_early / se_did_early
p_early = 2 * (1 - cdf(Normal(), abs(t_early)))

idx_tm_early = findfirst(x -> x == "tenure & multiple", names_early)
tm_early = coefs_early[idx_tm_early]

println("Tenure × Multiple (Low-API advantage): ", round(tm_early, digits=4))
println("Tenure × Multiple × High_API (DiD): ", round(did_early, digits=4), " (p=", round(p_early, digits=4), ")")

println("\n--- LATE PERIOD (2013-2024) ---\n")
m_late = fit(MixedModel, 
    @formula(seniority ~ 1 + tenure * multiple * high_api + 
             edu_num + (1 | person_id)), 
    late_data, REML=true)

coefs_late = fixef(m_late)
names_late = coefnames(m_late)
se_late = stderror(m_late)

idx_did_late = findfirst(x -> x == "tenure & multiple & high_api", names_late)
did_late = coefs_late[idx_did_late]
se_did_late = se_late[idx_did_late]
t_late = did_late / se_did_late
p_late = 2 * (1 - cdf(Normal(), abs(t_late)))

idx_tm_late = findfirst(x -> x == "tenure & multiple", names_late)
tm_late = coefs_late[idx_tm_late]

println("Tenure × Multiple (Low-API advantage): ", round(tm_late, digits=4))
println("Tenure × Multiple × High_API (DiD): ", round(did_late, digits=4), " (p=", round(p_late, digits=4), ")")

# === SUMMARY ===
println("\n" * "="^70)
println("SUMMARY: DiD EFFECT BY PERIOD")
println("="^70)

println("\n                          Early (2000-2012)    Late (2013-2024)")
println("Low-API Multiple advantage:    ", round(tm_early, digits=4), "              ", round(tm_late, digits=4))
println("DiD (High-API attenuation):    ", round(did_early, digits=4), "              ", round(did_late, digits=4))
println("DiD p-value:                   ", round(p_early, digits=4), "              ", round(p_late, digits=4))

change_did = did_late - did_early
println("\nChange in DiD (Late - Early):  ", round(change_did, digits=4))
println("Interpretation: ", change_did < 0 ? "DiD effect STRENGTHENING over time" : "DiD effect WEAKENING over time")

# === SAVE RESULTS ===
println("\n=== SAVING RESULTS ===\n")

# Save Model 5 coefficients (four-way)
results_m5 = DataFrame(
    term = names5,
    estimate = round.(coefs5, digits=6),
    std_error = round.(se5, digits=6)
)
results_m5.t_stat = round.(results_m5.estimate ./ results_m5.std_error, digits=3)
results_m5.p_value = round.(2 .* (1 .- cdf.(Normal(), abs.(results_m5.t_stat))), digits=6)
CSV.write("C:/jessiepaper/julia/output/panel_fourway_coefficients.csv", results_m5)
println("Saved: panel_fourway_coefficients.csv")

# Save period comparison
period_comparison = DataFrame(
    period = ["Early (2000-2012)", "Late (2013-2024)"],
    low_api_advantage = round.([tm_early, tm_late], digits=5),
    did_estimate = round.([did_early, did_late], digits=5),
    did_p_value = round.([p_early, p_late], digits=5)
)
CSV.write("C:/jessiepaper/julia/output/panel_period_comparison.csv", period_comparison)
println("Saved: panel_period_comparison.csv")

# Save Model 6 coefficients
results_m6 = DataFrame(
    term = names6,
    estimate = round.(coefs6, digits=6),
    std_error = round.(se6, digits=6)
)
results_m6.t_stat = round.(results_m6.estimate ./ results_m6.std_error, digits=3)
results_m6.p_value = round.(2 .* (1 .- cdf.(Normal(), abs.(results_m6.t_stat))), digits=6)
CSV.write("C:/jessiepaper/julia/output/panel_period_interaction_coefficients.csv", results_m6)
println("Saved: panel_period_interaction_coefficients.csv")

println("\n" * "="^70)
println("DONE")
println("="^70)