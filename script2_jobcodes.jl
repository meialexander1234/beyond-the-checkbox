using RData, DataFrames, Statistics, Dates, MixedModels, Distributions, CSV, XLSX

println("Loading data...")

# Load career data
individ = load("C:/jessiepaper/data/individ.RData")["individ"]
usa = DataFrame(individ)

# Load roles crosswalk
roles = CSV.read("C:/jessiepaper/data/roles.csv", DataFrame)

# Load O*NET Work Activities
xf = XLSX.readxlsx("C:/jessiepaper/data/Work Activities.xlsx")
sheet = xf[XLSX.sheetnames(xf)[1]]
work_activities = DataFrame(XLSX.eachtablerow(sheet))

println("Career data rows: ", nrow(usa))
println("Roles rows: ", nrow(roles))
println("Work Activities rows: ", nrow(work_activities))

# === CREATE INTERPERSONAL VS TECHNICAL SCORES ===

# Filter to "Importance" scale only
wa_importance = filter(row -> row["Scale Name"] == "Importance", work_activities)
println("\nImportance scale rows: ", nrow(wa_importance))

# Define interpersonal activities
interpersonal_activities = [
    "Communicating with Supervisors, Peers, or Subordinates",
    "Communicating with People Outside the Organization",
    "Establishing and Maintaining Interpersonal Relationships",
    "Selling or Influencing Others",
    "Resolving Conflicts and Negotiating with Others",
    "Performing for or Working Directly with the Public"
]

# Define technical activities
technical_activities = [
    "Processing Information",
    "Analyzing Data or Information",
    "Working with Computers"
]

# Filter and aggregate interpersonal score by O*NET code
wa_interp = filter(row -> row["Element Name"] in interpersonal_activities, wa_importance)
interp_scores = combine(groupby(wa_interp, "O*NET-SOC Code"),
    "Data Value" => mean => :interpersonal_score
)
rename!(interp_scores, "O*NET-SOC Code" => :onet_code)

# Filter and aggregate technical score by O*NET code
wa_tech = filter(row -> row["Element Name"] in technical_activities, wa_importance)
tech_scores = combine(groupby(wa_tech, "O*NET-SOC Code"),
    "Data Value" => mean => :technical_score
)
rename!(tech_scores, "O*NET-SOC Code" => :onet_code)

# Merge interpersonal and technical
onet_scores = innerjoin(interp_scores, tech_scores, on=:onet_code)
onet_scores.interp_vs_tech = onet_scores.interpersonal_score .- onet_scores.technical_score

println("\nO*NET scores created: ", nrow(onet_scores), " occupations")
println("Interpersonal score range: ", round(minimum(onet_scores.interpersonal_score), digits=2), 
        " - ", round(maximum(onet_scores.interpersonal_score), digits=2))
println("Technical score range: ", round(minimum(onet_scores.technical_score), digits=2),
        " - ", round(maximum(onet_scores.technical_score), digits=2))

# === MERGE WITH ROLES CROSSWALK ===

# Clean roles data
roles_clean = select(roles, :role_k1500, :onet_code)
dropmissing!(roles_clean)
roles_clean.onet_code = string.(roles_clean.onet_code)

# Merge roles with O*NET scores
roles_onet = innerjoin(roles_clean, onet_scores, on=:onet_code)
println("\nRoles with O*NET scores: ", nrow(roles_onet))

# === MERGE WITH CAREER DATA ===

# Filter USA, White + Multiple, 2000-2024
usa = filter(row -> row.country == "United States" && 
             row.ethnicity_predicted in ["White", "Multiple"], usa)
usa.year = year.(usa.startdate)
usa = filter(row -> row.year >= 2000 && row.year <= 2024, usa)

# Define state groups
high_api_states = ["California", "Hawaii", "Washington"]
low_api_states = ["Georgia", "North Carolina", "Alabama", "Mississippi", 
                  "South Carolina", "Louisiana", "Maryland", "Texas", "Florida"]
usa = filter(row -> row.state in vcat(high_api_states, low_api_states), usa)

usa.high_api = ifelse.(in.(usa.state, Ref(high_api_states)), 1, 0)
usa.multiple = ifelse.(usa.ethnicity_predicted .== "Multiple", 1, 0)

# Merge with O*NET scores via role_k1500
usa.role_k1500 = string.(usa.role_k1500)
usa_onet = innerjoin(usa, roles_onet, on=:role_k1500)

println("\nCareer data with O*NET scores: ", nrow(usa_onet))

# === CREATE PANEL VARIABLES ===

# Tenure
person_start = combine(groupby(usa_onet, :user_id), :year => minimum => :career_start)
usa_onet = leftjoin(usa_onet, person_start, on=:user_id)
usa_onet.tenure = usa_onet.year .- usa_onet.career_start
usa_onet = filter(row -> row.tenure >= 0 && row.tenure <= 20, usa_onet)

# Education
edu_map = Dict("High School" => 1, "Associate" => 2, "Bachelor" => 3, 
               "Master" => 4, "MBA" => 4, "PhD" => 5, "MD" => 5, "JD" => 5)
usa_onet.edu_num = [get(edu_map, d, 3) for d in usa_onet.highest_degree]

# High interpersonal indicator (above median)
median_interp = median(usa_onet.interp_vs_tech)
usa_onet.high_interp = ifelse.(usa_onet.interp_vs_tech .> median_interp, 1, 0)

# Filter to 2+ obs per person
person_obs = combine(groupby(usa_onet, :user_id), nrow => :n_obs)
usa_onet = leftjoin(usa_onet, person_obs, on=:user_id)
usa_onet = filter(row -> row.n_obs >= 2, usa_onet)
usa_onet.person_id = string.(usa_onet.user_id)

println("Final longitudinal sample: ", nrow(usa_onet))
println("Unique persons: ", length(unique(usa_onet.user_id)))

# === DESCRIPTIVES ===
println("\n=== DESCRIPTIVES BY OCCUPATIONAL CONTEXT ===\n")

desc = combine(groupby(usa_onet, [:high_interp, :high_api, :multiple]),
    :user_id => (x -> length(unique(x))) => :n_persons,
    :seniority => mean => :mean_sen,
    :interpersonal_score => mean => :mean_interp,
    :technical_score => mean => :mean_tech
)
desc.mean_sen = round.(desc.mean_sen, digits=3)
desc.mean_interp = round.(desc.mean_interp, digits=2)
desc.mean_tech = round.(desc.mean_tech, digits=2)
sort!(desc, [:high_interp, :high_api, :multiple])
println(desc)

# === MODEL 1: BASE (No Occupational Context) ===
println("\n=== MODEL 1: BASE DiD (No Occupational Context) ===\n")

m1 = fit(MixedModel, 
    @formula(seniority ~ 1 + tenure * multiple * high_api + 
             edu_num + (1 | person_id)), 
    usa_onet, REML=true)
println(m1)

# === MODEL 2: ADD OCCUPATIONAL CONTEXT ===
println("\n=== MODEL 2: ADD HIGH_INTERP MAIN EFFECT ===\n")

m2 = fit(MixedModel, 
    @formula(seniority ~ 1 + tenure * multiple * high_api + 
             high_interp + edu_num + (1 | person_id)), 
    usa_onet, REML=true)
println(m2)

# === MODEL 3: H3 TEST - OCCUPATIONAL MODERATION ===
println("\n=== MODEL 3: H3 TEST - MULTIPLE × HIGH_API × HIGH_INTERP ===\n")

m3 = fit(MixedModel, 
    @formula(seniority ~ 1 + tenure * multiple * high_api * high_interp + 
             edu_num + (1 | person_id)), 
    usa_onet, REML=true)
println(m3)

# === EXTRACT H3 RESULTS ===
println("\n" * "="^70)
println("H3 HYPOTHESIS TEST")
println("="^70)

coefs = fixef(m3)
se = stderror(m3)
names_m3 = coefnames(m3)

println("\nKey coefficients:")
for (i, name) in enumerate(names_m3)
    if occursin("high_interp", name)
        t_val = coefs[i] / se[i]
        p_val = 2 * (1 - cdf(Normal(), abs(t_val)))
        sig = p_val < 0.001 ? "***" : (p_val < 0.01 ? "**" : (p_val < 0.05 ? "*" : (p_val < 0.10 ? "†" : "")))
        println("  ", rpad(name, 50), round(coefs[i], digits=5), "  (p=", round(p_val, digits=4), ") ", sig)
    end
end

println("\n" * "="^70)
println("H3 Prediction: Penalty larger in high-interpersonal occupations")
println("Test: multiple × high_api × high_interp < 0")
println("="^70)

# === SAVE RESULTS ===
results = DataFrame(
    term = names_m3,
    estimate = round.(coefs, digits=6),
    std_error = round.(se, digits=6)
)
results.t_stat = round.(results.estimate ./ results.std_error, digits=3)
results.p_value = round.(2 .* (1 .- cdf.(Normal(), abs.(results.t_stat))), digits=6)

CSV.write("C:/jessiepaper/julia/output/h3_onet_coefficients.csv", results)
println("\nSaved: h3_onet_coefficients.csv")

println("\nDone!")