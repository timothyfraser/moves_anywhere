# `README`: MOVES inputs

This document summarizes MOVES input tables used in the MOVES County Data Manager, catagorized by how the MOVES Anywhere software interacts with and adapts them. 

Tables below borrowed from Cloud MOVES paper.

## Optional Tables for EPA MOVES's County Data Manager, *listed by MOVES Menu*

| Topic | Table | Adjustment | Adaptation |
|-------|-------|------------|------------|
| **Menu: Starts** | | | |
| Hourly Vehicle Starts | startsHourFraction | Filtered | Filter by dayID and hourID |
| Annual Vehicle Starts | starts | Filtered | Filter by yearID |
| Daily Vehicle Starts | startsPerDay | Filtered | Filter by dayID |
| Daily Starts per Vehicle | StartsPerDayPerVehicle | Filtered | Filter by dayID |
| Monthly Adjustment for Starts | startsMonthAdjust | Untouched | *Untouched* |
| Age Adjustment for Starts | startsAgeAdjustment | Untouched | *Untouched* |
| Operating Mode Distribution for Starts | startsOpModeDistribution | Filtered | Filter by opModeID, dayID, hourID |
| **Menu: Hotelling** | | | |
| Hotelling Activity by Zone | hotellingActivityDistribution | Filtered | Filter by zoneID |
| Hours Spent Hotelling | hotellingHours | Untouched | *Untouched* |
| Hourly Hotelling Fraction | hotellingHourFraction | Untouched | *Untouched* |
| Age Distribution of Hotelling Vehicles | hotellingAgeFraction | Untouched | *Untouched* |
| Monthly Adjustment for Hotelling | hotellingMonthAdjust | Untouched | *Untouched* |
| **Menu: Idling** | | | |
| Total Fraction of Idling | totalIdleFraction | Filtered | Filter by idleRegionID, countyTypeID, monthID, dayID |
| Model Year Groups for Idling | idleModelYearGrouping | Untouched | *Untouched* |
| Monthly Adjustment for Idling | idleMonthAdjust | Untouched | *Untouched* |
| Daily Adjustment for Idling | idleDayAdjust | Untouched | *Untouched* |
| **Menu: Retrofit Data** | | | |
| On-Road Retrofit Information | onRoadRetrofit | Untouched | *Untouched* |


## User-Supplied Tables Required by EPA MOVES's County Data Manager, *listed by MOVES Menu*

| Topic | Table | Adjustment | Adaptation |
|-------|-------|------------|------------|
| **Menu: Vehicle Type VMT** | | | |
| Vehicle Miles Traveled by Vehicle Type | sourceTypeYearVMT OR HPMSVtypeYear | Projected | By default, interpolate SourceTypeYearVMT from National Emissions Inventory |
| **Menu: Source Type Population** | | | |
| Vehicle Population by Vehicle Type | sourceTypeYear | Projected | By default, interpolate sourceTypeYear from National Emissions Inventory |
| **Menu: Road Type Distribution** | | | |
| VMT Distribution by Road Type | roadTypeDistribution | Untouched | *Untouched* |
| **Menu: Age Distribution** | | | |
| Vehicle Population by Age and Type | sourceTypeAge-Distribution | Filtered | Filter by yearID |
| **Menu: Vehicle Type VMT** | | | |
| Monthly VMT Fraction | monthVMTFraction | Untouched | Used if VMT is Annual |
| Daily VMT Fraction | dayVMTFraction | Untouched | Used if VMT is Annual |
| Hourly VMT Fraction | hourVMTFraction | Untouched | Used if VMT is Annual or Daily |
| **Menu: Average Speed Distribution** | | | |
| Average Speeds by Hour | avgSpeedDistribution | Filtered | Filter by hourDayID |
| **Menu: I/M Programs** | | | |
| Inspection & Maintenance Coverage | IMCoverage | Filtered | Filter by stateID, countyID, yearID |
| **Menu: Meteorology Data** | | | |
| Meteorological Conditions by Hour | zoneMonthHour | Filtered | Filter by zoneID, monthID, hourID |
| **Menu: Fuel** | | | |
| Fleet Technology and Fuel Types | AVFT<sup>1</sup> | Projected | Using samplevehiclepopulation, group by sourceTypeID, modelYearID, fuelTypeID, and engTechID and sum stmyFraction to make fuelEngFraction. |
| Fuel Use by Year and County | FuelUsageFraction | Filtered | Filter by countyID, fuelYearID |
| Fuel Supply by Region and Month | FuelSupply | Copied | *Borrowed* from New York State Dept. of Environmental Conservation |
| Fuel Characteristics | FuelFormulation | Copied | *Borrowed* like FuelSupply |

<sup>1</sup> **AVFT** stands for 'Alternate Vehicle Fuel and Technologies' input table.

## MariaDB Tables Used by Adapt Functions

This section lists all MariaDB database tables that are accessed by the adapt functions in `moves_anywhere/moves_anywhere/scripts/adapt_*.R` when performing MOVES input table adaptation. These tables are read from the default MOVES database to generate adapted input tables.

### Identifier Tables
- `county` - County information including countyID, countyTypeID, stateID
- `state` - State information including stateID, idleRegionID
- `zone` - Zone information including zoneID, countyID
- `regioncounty` - Region-county associations including regionID, countyID, fuelYearID
- `zoneroadtype` - Zone-road type associations including zoneID, roadTypeID
- `year` - Year information including yearID, isBaseYear, fuelYearID
- `idleregion` - Idle region information including idleRegionID
- `pollutantprocessassoc` - Pollutant-process associations including pollutantID, polProcessID
- `opmodepolprocassoc` - Operating mode-pollutant-process associations including polProcessID, opModeID

### Fuel Tables
- `fuelusagefraction` - Fuel usage fractions by county, fuelYearID, modelYearGroupID, sourceBinFuelTypeID, fuelSupplyFuelTypeID
- `samplevehiclepopulation` - Sample vehicle population data used to generate AVFT table (grouped by sourceTypeID, modelYearID, fuelTypeID, engTechID)

### VMT Tables
- `hpmsvtypeyear` - HPMS vehicle type year data including HPMSVtypeID, yearID, VMTGrowthFactor, HPMSBaseYearVMT
- `sourcetypeyearvmt` - Source type year VMT data including yearID, sourceTypeID, VMT
- `sourcetypedayvmt` - Source type day VMT data including yearID, monthID, dayID, sourceTypeID, VMT
- `hpmsvtypeday` - HPMS vehicle type day data including yearID, monthID, dayID, HPMSVtypeID, VMT

### VMT Fraction Tables
- `dayvmtfraction` - Daily VMT fraction by sourceTypeID, monthID, roadTypeID, dayID
- `hourvmtfraction` - Hourly VMT fraction by sourceTypeID, roadTypeID, dayID, hourID
- `monthvmtfraction` - Monthly VMT fraction by sourceTypeID, monthID

### Vehicle Population Tables
- `sourcetypeyear` - Source type year population including yearID, sourceTypeID, sourceTypePopulation
- `sourcetypeagedistribution` - Source type age distribution including sourceTypeID, yearID, ageID, ageFraction

### Speed Distribution Tables
- `avgspeeddistribution` - Average speed distribution by sourceTypeID, roadTypeID, hourDayID, avgSpeedBinID, avgSpeedFraction

### Road Type Tables
- `roadtypedistribution` - Road type VMT distribution by sourceTypeID, roadTypeID, roadTypeVMTFraction

### Starts Tables
- `starts` - Annual vehicle starts by hourDayID, monthID, yearID, ageID, zoneID, sourceTypeID
- `startshourfraction` - Hourly starts fraction by dayID, hourID, sourceTypeID, allocationFraction
- `startsperday` - Starts per day by dayID, sourceTypeID, startsPerDay
- `startsperdaypervehicle` - Starts per day per vehicle by dayID, sourceTypeID, startsPerDayPerVehicle
- `startsopmodedistribution` - Starts operating mode distribution by dayID, hourID, sourceTypeID, ageID, opModeID, opModeFraction

### Hotelling Tables
- `hotellingactivitydistribution` - Hotelling activity distribution by zoneID, fuelTypeID, beginModelYearID, endModelYearID, opModeID, opModeFraction

### Idling Tables
- `totalidlefraction` - Total idle fraction by sourceTypeID, minModelYearID, maxModelYearID, monthID, dayID, idleRegionID, countyTypeID

### Inspection & Maintenance Tables
- `imcoverage` - I/M program coverage by polProcessID, stateID, countyID, yearID, sourceTypeID, fuelTypeID, IMProgramID, begModelYearID, endModelYearID, inspectFreq, testStandardsID, useIMyn, complianceFactor

### Climate Tables
- `zonemonthhour` - Zone month hour meteorological data including zoneID, monthID, hourID, temperature, relHumidity

### Notes
- All tables listed above are read from the default MOVES database (typically named "moves" or the default database name specified in the runspec)
- These tables are used as reference data when custom input tables are not provided by the user
- The adapt functions filter these tables based on runspec parameters (geoid, year, month, day, hour, etc.)
- Some tables may be commented out in the adapt functions but are listed here for completeness

