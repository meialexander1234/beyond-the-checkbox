# Beyond the Checkbox

Replication code for "Beyond the Checkbox: Categorization Ambiguity and Career Trajectories of Multiracial Workers"

## Overview

This project analyzes career trajectories of multiracial workers using large-scale longitudinal workforce data (2000-2024). We test whether categorization ambiguity—the difficulty perceivers experience when they cannot readily assign someone to a single racial group—creates career penalties for multiracial workers.

## Key Findings

### Main Result: The Hiring-Gate Finding
- Multiracial workers in high-API states (CA, HI, WA) face a **hiring penalty** of −0.11 seniority levels (p < .001)
- Once employed, multiracial workers advance at the **same rate** as White workers
- The penalty operates at the **hiring gate**, not on the **career ladder**
- This pattern is stable over 25 years (2000-2024) and survives education controls

### Descriptive National Patterns
- Multiracial ("Multiple") workers rank higher than White workers in seniority (2.81 vs 2.78)
- Ranking: API (3.03) > Multiple (2.81) > White (2.78) > Black (2.50) > Hispanic (2.43)
- Gender crossover effect: Multiple men outperform White men, but Multiple women underperform White women

## Scripts

| Script | Purpose | Hypothesis | Result |
|--------|---------|------------|--------|
| `script1_reganal.jl` | Regional DiD analysis comparing high-API vs low-API states | Hiring-gate penalty | **Supported** (p < .001) |
| `script2_jobcodes.jl` | H3: Occupational context moderation using O*NET Work Activities | Penalty larger in interpersonal jobs | Not supported (p = .29) |
| `script3_groupanal.jl` | H6: Within-group variance test | Multiple has highest variance | Not supported |
| `script4_covidanal.jl` | COVID natural experiment (remote work attenuation) | Penalty smaller during COVID | Not supported (p = .73) |
| `script5_firmswitch.jl` | Firm-switching reset test | Penalty larger in first 1-2 years at new firm | Not supported (p = .24) |
| `script6_doseresp.jl` | Dose-response test (BISG ambiguity strength) | Stronger ambiguity = larger penalty | Cannot complete (no BISG probabilities) |

## Requirements

### Julia 1.10+

Install required packages:
```julia
using Pkg
Pkg.add([
    "DataFrames", 
    "CSV", 
    "RData", 
    "Statistics", 
    "Dates", 
    "GLM", 
    "MixedModels",
    "CategoricalArrays",
    "Distributions",
    "HypothesisTests",
    "XLSX"
])
```

## Data

Data sourced from Revelio Labs. Raw data files are not included due to license restrictions.

### Required Input Files
- `individ.RData` — Person-job spells with ethnicity, seniority, salary, dates, firm IDs
- `roles.csv` — Crosswalk from job roles to O*NET codes
- `Work Activities.xlsx` — O*NET Work Activities ratings (download from [O*NET](https://www.onetcenter.org/database.html))

### Output Files
Scripts generate CSV files in `output/` directory:
- `did_expanded_*.csv` — Regional DiD model results
- `h3_onet_coefficients.csv` — Occupational moderation results
- `h6_variance_results.csv` — Variance by ethnicity
- `covid_experiment_coefficients.csv` — COVID period analysis
- `firm_switching_coefficients.csv` — Firm-switching results
- `dose_response_status.csv` — Dose-response data availability

## Usage

Update file paths in each script to match your local directory structure, then run:

```bash
julia script1_reganal.jl      # Main regional DiD analysis
julia script2_jobcodes.jl     # H3: Occupational context
julia script3_groupanal.jl    # H6: Variance test
julia script4_covidanal.jl    # COVID experiment
julia script5_firmswitch.jl   # Firm-switching test
julia script6_doseresp.jl     # Dose-response check
```

## Sample Sizes

| Analysis | Persons | Observations |
|----------|---------|--------------|
| Regional DiD | 987,020 | 3,024,180 |
| H3 (O*NET) | 905,171 | 2,697,055 |
| H6 (Variance) | — | 16,696,239 |
| COVID | 987,020 | 3,024,180 |
| Firm-switching | ~500,000 | ~1,500,000 |

## State Groups

**High-API States** (large Asian populations): California, Hawaii, Washington

**Low-API States** (comparison group): Texas, Florida, Georgia, North Carolina, Maryland, South Carolina, Louisiana, Alabama, Mississippi

## Citation

```
Alexander, J. (2025). Beyond the Checkbox: Categorization Ambiguity and 
Career Trajectories of Multiracial Workers. Working Paper.
```

## License

MIT
