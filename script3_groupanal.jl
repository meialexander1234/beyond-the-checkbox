# ============================================================
# SCRIPT 1: H6 - Within-Group Variance Test
# ============================================================
# Save as: h6_variance.jl

using RData, DataFrames, Statistics, Dates, CSV, HypothesisTests, Distributions

println("="^60)
println("H6: WITHIN-GROUP VARIANCE TEST")
println("="^60)

println("\nLoading data...")
individ = load("C:/jessiepaper/data/individ.RData")["individ"]
usa = DataFrame(individ)

# Filter to USA, 2000-2024
usa = filter(row -> row.country == "United States", usa)
usa.year = year.(usa.startdate)
usa = filter(row -> row.year >= 2000 && row.year <= 2024, usa)

# Keep all 5 ethnic groups
usa = filter(row -> row.ethnicity_predicted in ["White", "Black", "Hispanic", "API", "Multiple"], usa)

println("Total observations: ", nrow(usa))

# === CALCULATE VARIANCE BY GROUP ===
println("\n=== SENIORITY VARIANCE BY ETHNICITY ===\n")

var_stats = combine(groupby(usa, :ethnicity_predicted),
    :seniority => mean => :mean_sen,
    :seniority => std => :sd_sen,
    :seniority => var => :var_sen,
    :seniority => length => :n
)
var_stats.mean_sen = round.(var_stats.mean_sen, digits=3)
var_stats.sd_sen = round.(var_stats.sd_sen, digits=3)
var_stats.var_sen = round.(var_stats.var_sen, digits=3)

sort!(var_stats, :var_sen, rev=true)
println(var_stats)

# === LEVENE'S TEST (Variance Equality) ===
println("\n=== LEVENE'S TEST FOR EQUALITY OF VARIANCES ===\n")

# Extract seniority vectors by group
sen_white = filter(row -> row.ethnicity_predicted == "White", usa).seniority
sen_black = filter(row -> row.ethnicity_predicted == "Black", usa).seniority
sen_hispanic = filter(row -> row.ethnicity_predicted == "Hispanic", usa).seniority
sen_api = filter(row -> row.ethnicity_predicted == "API", usa).seniority
sen_multiple = filter(row -> row.ethnicity_predicted == "Multiple", usa).seniority

# Variance ratios (Multiple vs each group)
println("Variance Ratios (Multiple / Other):")
println("  Multiple / White:    ", round(var(sen_multiple) / var(sen_white), digits=3))
println("  Multiple / Black:    ", round(var(sen_multiple) / var(sen_black), digits=3))
println("  Multiple / Hispanic: ", round(var(sen_multiple) / var(sen_hispanic), digits=3))
println("  Multiple / API:      ", round(var(sen_multiple) / var(sen_api), digits=3))

# F-tests for variance equality (Multiple vs each group)
println("\n=== F-TESTS: MULTIPLE VS EACH GROUP ===\n")

function variance_ftest(x, y, name)
    n1, n2 = length(x), length(y)
    v1, v2 = var(x), var(y)
    f_stat = v1 / v2
    df1, df2 = n1 - 1, n2 - 1
    # Two-tailed p-value
    if f_stat > 1
        p_val = 2 * (1 - cdf(FDist(df1, df2), f_stat))
    else
        p_val = 2 * cdf(FDist(df1, df2), f_stat)
    end
    println("Multiple vs $name:")
    println("  F = ", round(f_stat, digits=3), ", p = ", round(p_val, digits=6))
    println("  Multiple variance ", f_stat > 1 ? "GREATER" : "SMALLER")
    return (name=name, f_stat=f_stat, p_val=p_val, multiple_greater=f_stat > 1)
end

results = []
push!(results, variance_ftest(sen_multiple, sen_white, "White"))
push!(results, variance_ftest(sen_multiple, sen_black, "Black"))
push!(results, variance_ftest(sen_multiple, sen_hispanic, "Hispanic"))
push!(results, variance_ftest(sen_multiple, sen_api, "API"))

# === COEFFICIENT OF VARIATION ===
println("\n=== COEFFICIENT OF VARIATION (CV) ===\n")

var_stats.cv = round.(var_stats.sd_sen ./ var_stats.mean_sen .* 100, digits=2)
println("CV = (SD / Mean) × 100 — standardized measure of dispersion")
println()
println(select(var_stats, :ethnicity_predicted, :mean_sen, :sd_sen, :cv))

# === H6 HYPOTHESIS TEST ===
println("\n" * "="^60)
println("H6 HYPOTHESIS TEST")
println("="^60)

multiple_var = var(sen_multiple)
max_other_var = max(var(sen_white), var(sen_black), var(sen_hispanic), var(sen_api))
multiple_cv = std(sen_multiple) / mean(sen_multiple)
max_other_cv = maximum([std(sen_white)/mean(sen_white), std(sen_black)/mean(sen_black), 
                        std(sen_hispanic)/mean(sen_hispanic), std(sen_api)/mean(sen_api)])

println("\nH6 Prediction: Multiple has GREATER variance than any monoracial group")
println()
println("Multiple variance: ", round(multiple_var, digits=3))
println("Max monoracial variance: ", round(max_other_var, digits=3))
println("Multiple CV: ", round(multiple_cv * 100, digits=2), "%")
println("Max monoracial CV: ", round(max_other_cv * 100, digits=2), "%")
println()
println("Result: ", multiple_var > max_other_var ? "SUPPORTED ✓" : "NOT SUPPORTED ✗")

# === SAVE RESULTS ===
CSV.write("C:/jessiepaper/julia/output/h6_variance_results.csv", var_stats)
println("\nSaved: h6_variance_results.csv")

println("\nDone!")