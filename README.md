# beyond-the-checkbox

Replication code for "Beyond the Checkbox: Categorization Ambiguity and Career Trajectories of Multiracial Workers"

## Overview

This project analyzes career trajectories of multiracial workers using large-scale longitudinal workforce data (2000-2024). We test whether categorization ambiguity—the difficulty perceivers experience when they cannot readily assign someone to a single racial group—creates career penalties for multiracial workers.

## Key Findings

- Multiracial ("Multiple") workers rank **higher** than White workers in seniority (2.81 vs 2.78)
- Ranking: API (3.03) > Multiple (2.81) > White (2.78) > Black (2.50) > Hispanic (2.43)
- The Multiple salary advantage has grown from 1% to 14% over the study period
- Gender crossover effect: Multiple men outperform White men, but Multiple women underperform White women

## Scripts

| Script | Purpose |
|--------|---------|
| `01_load_data.jl` | Load and clean Revelio workforce data from RData format |
| `02_aggregate_data.jl` | Aggregate person-job spells to ethnicity × year panel |
| `03_descriptives.jl` | Generate descriptive statistics and summary tables |
| `04_hypothesis_tests.jl` | Formal hypothesis tests (H1, H2, H4) |

## Requirements

### Julia 1.10+

Install required packages:
```julia
using Pkg
Pkg.add(["DataFrames", "CSV", "RData", "Statistics", "Dates", "GLM", "CategoricalArrays"])
```

## Data

Data sourced from Revelio Labs via WRDS. Raw data files are not included due to license restrictions.

### Expected input
- `individ.RData` — Person-job spells with ethnicity, seniority, salary, dates

### Output files
- `longitude_data.csv` — Ethnicity × year panel
- `longitude_gender.csv` — Ethnicity × year × gender panel
- `firm_blau.csv` — Firm-level diversity index by year
- Various tables and figure data files

## Usage

Run scripts in order:
```bash
cd C:/jessiepaper/julia
julia 01_load_data.jl
julia 02_aggregate_data.jl
julia 03_descriptives.jl
julia 04_hypothesis_tests.jl
```

## Citation

Alexander, J. (2025). Beyond the Checkbox: Categorization Ambiguity and Career Trajectories of Multiracial Workers. Working Paper, University of Texas at Austin.

## License

MIT
