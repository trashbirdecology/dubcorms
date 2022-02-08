
<!-- README.md is generated from README.Rmd. Please edit that file -->
<!-- badges: start -->

[![Lifecycle:
experimental](https://img.shields.io/badge/lifecycle-experimental-orange.svg)](https://lifecycle.r-lib.org/articles/stages.html#experimental)
[![R-CMD-check](https://github.com/trashbirdecology/dubcorms/workflows/R-CMD-check/badge.svg)](https://github.com/trashbirdecology/dubcorms/actions)
<!-- badges: end -->

# dubcorms

The purpose of this R package (*likely to undergo a name change…*) is
to:

1.  provide a (currently) faster alternative to the R package `auk` for
    importing and munging the large eBird datasets\*
2.  integrate the BBS and eBird observation datasets for use in JAGS
    (`rjags`) and `mcgv::jagam()` by binding data to a common, spatial
    sampling grid

> \*[@cboettig](https://github.com/cboettig/) and
> [@amstrimas](https://github.com/amstrimas/) are currently developing
> an `auk` alternative, [`birddb`](https://github.com/cboettig/birddb/).
> It is likely that, once stable, this R package will use `birddb` as
> dependency for eBird import and manipulation. For now, however, the
> functions herein provide a much faster alternative to `auk`.

## Installation

Download development version from GitHub with:

``` r
# install.packages("devtools")
devtools::install_github("trashbirdecology/bbsassistant")
devtools::install_github("trashbirdecology/dubcorms")
```

## eBird Data Requirements

Prior to using this package, you must have downloaded eBird data. To
request and download eBird observations, visit [the eBird
website](https://ebird.org/data/download). Credentials are required, and
may take up to a few business days for approval, depending on use case.
For more information on the eBird data see the eBird website, or visit
[the repository for the Cornell Lab of Ornithology’s offical R package
for munging eBird data,
`auk`](https://github.com/CornellLabofOrnithology/auk/).

When your account is approved, you will gain access to the [eBird Basic
Database (EBD)](https://ebird.org/data/download/ebd). This package
requires two components of the EBD to be saved to local file:

1.  the **observations** (i.e. counts)
2.  the **sampling events** (i.e. information about the observation
    process)

# Runthrough

## Step 1: Setup

``` r
# 0:Setup -----------------------------------------------------------------
# install.packages("devtools")
devtools::install_github("trashbirdecology/dubcorms")
#explicitly load some packages
pkgs <- c("dubcorms",
          "bbsAssistant",
          "reshape2",
          "stringr",
          "dplyr",
          "sf")
# install.packages("mapview")
invisible(lapply(pkgs, library, character.only = TRUE))
rm(pkgs)
```

If using this README, this is the only RMD chunk you shoudl have to
edit. Most important are where the eBird data and BBS shapefiles are
stored (dir.orig.data) and where you wish to save resulting data/models
(dir.proj). The latter need not exist – if it does not exist the package
will create the directory for you.

``` r
# REQUIRED ARGUMENTS
dir.orig.data  = "C:/Users/jburnett/OneDrive - DOI/research/cormorants/dubcorm-data-backup/"
dir.proj       = "C:/users/jburnett/OneDrive - DOI/research/cormorants/House_Sparrow/"
species             = c("House Sparrow") ## eventually need to add alookup table to ensure species.abbr and speices align.
species.abbr        = c("houspa") # see ebird filename for abbreviation
##bbs arguments
usgs.layer          = "US_BBS_Route-Paths-Snapshot_Taken-Feb-2020" # name of the USGS BBS route shapefile to use
cws.layer           = "ALL_ROUTES"
##ebird arguments
mmyyyy              = "dec-2021" # the month and year of the eBird data downloads on file

# Strongly suggested but optional args
##general arguments
# dir.proj  = "C:/Users/jburnett/desktop/testing/"


### see bbsAssistant::region_codes
states              = c("us-fl")
countries           = c("US") ## string of  countries Call \code{dubcorms::iso.codes} to find relevant codes for Countries and States/Prov/Territories.
# species             = c("Double-crested Cormorant", "Nannopterum auritum", "phalacrocorax auritum")
# species.abbr        = c("doccor","dcco", "docco")

year.range          = 2008:2019
base.julian.date    = lubridate::ymd(paste0(min(year.range), c("-01-01"))) # used as base date for Julian dates.
crs.target          = 4326 #target CRS for all created spatial layers

##grid arguments
grid.size           = 1.00 # size in decimal degrees (for US/CAN a good est is 1.00dec deg == 111.11km)

##ebird arguments
min.yday            = 91
max.yday            = 245

##JAGS: arguments for customizing the resulting JAGS data list
jagam.args          = list(bs="ds",k=20, family="poisson", sp.prior="log.uniform", diagonalize=TRUE)

## Munge the states and countries indexes for use in dir/proj dir reation
if(!exists("states")) states <- NULL
if(!is.null(states)){regions <- states}else{regions <- countries}
stopifnot(all(tolower(states) %in% tolower(bbsAssistant::region_codes$iso_3166_2)))
```

This chunk is not required, but is recommended to check that you’ve
correctly specified the arguments above.

``` r
# temp=c("complete.checklists.only", "scale.vars", 'overwrite.ebird',"remove.bbs.obs" ,"overwrite.bbs", "hexagonal", "get.sunlight")
# for(i in seq_along(temp))stopifnot(is.logical(eval(parse(text=temp[i]))))
# temp=c("min.yday", "max.yday", "max.effort.km", "max.effort.mins", "max.C.ebird",
#        "grid.size", "crs.target","year.range")
# for(i in seq_along(temp)){stopifnot(class(eval(parse(text = temp[i]))) %in% c("integer", "numeric"))}
# rm(temp)
```

This chunk will create new environmental variables for project adn data
directries based on teh directories supplied above.

``` r
# proj.shorthand: this will make all directories within a new dir in dir.proj. this is useful for iterating over species/time/space and saving all resulting information in those directories.
subdir.proj <-  proj.shorthand(species.abbr, regions, grid.size, year.range)
dirs        <-  dir_spec(dir.orig.data = dir.orig.data,  
                         dir.proj = dir.proj,
                         subdir.proj = subdir.proj) # create and/or specify directories for later use.
# ensure all directories exist
suppressWarnings(stopifnot(all(lapply(dirs, dir.exists))))
```

## Step 2: Make Integrated Data

### Create a spatial sampling grid

``` r
if(is.null(states)){ states.ind <- NULL}else{states.ind<-gsub(x=toupper(states), pattern="-", replacement="")}
grid <- make_spatial_grid(dir.out = dirs[['dir.spatial.out']],
                          # overwrite=overwrite.grid,
                          states = states.ind,
                          countries = countries,
                          crs.target = crs.target,
                          grid.size = grid.size
                          )
plot(grid)
```

Create the BBS data. This chunk relies heabily on R package . The
resulting data is aligned with the spatial grid (see above).

``` r
## wrapper for creating all bbs data--debating making this an exported function. for now, DNE
# bbs <- make_bbs_data()
fns.bbs.in <-
  list.files(
    dirs$dir.bbs.out,
    pattern = "bbs_obs.rds",
    recursive = TRUE,
    full.names = TRUE
  )
  bbs_orig <- grab_bbs_data(bbs_dir = dirs$dir.bbs.out) ## need to add grab_bbs_data into munge_bbs_data and include an option for where to save that data. 
  bbs_obs  <- munge_bbs_data(
    bbs_list = bbs_orig,
    states   = states,
    species = species, 
    year.range = year.range
  )
  bbs_obs <-
    dubcorms:::match_col_names(bbs_obs) # munge column names to mesh with eBird
  saveRDS(bbs_obs, paste0(dirs$dir.bbs.out, "/bbs_obs.rds"))

# Overlay BBS and study area / sampling grid
### note, sometimes when running this in a notebook/rmd i randomly get a .rdf path error. I have no clue what this bug is. Just try running it again. See : https://github.com/rstudio/rstudio/issues/6260
bbs_spatial <- make_bbs_spatial(
  df = bbs_obs,
  cws.routes.dir = dirs$cws.routes.dir,
  usgs.routes.dir = dirs$usgs.routes.dir,
  plot.dir = dirs$dir.plots,
  crs.target = crs.target,
  grid = grid,
  dir.out = dirs$dir.spatial.out
)
```

Make eBird data,

``` r
(fns.ebird    <- id_ebird_files(
  dir.ebird.in = dirs$dir.ebird.in,
  dir.ebird.out = dirs$dir.ebird.out,
  mmyyyy = mmyyyy,
  species = species.abbr,
  states.ind = states
))
stopifnot(length(fns.ebird) > 1)

# Import and munge the desired files..
ebird <- munge_ebird_data(
  fns.ebird = fns.ebird,
  species = c(species, species.abbr),
  dir.ebird.out = dirs$dir.ebird.out,
  countries = countries,
  states = states,
  years = year.range
)

# Create spatial ebird
ebird_spatial <- make_ebird_spatial(
  df = ebird,
  crs.target = crs.target,
  grid = grid,
  dir.out = dirs$dir.spatial.out
)
```

## Step 3: Bundle Data for Use in JAGS/Elsewhere

Create a list of lists and indexes for use in JAGS or elsewhere. We
suggest creating a list using `make_jags_list` and subsequently
subsetting the data from there.

``` r
tictoc::toc()#~9 minutes to this point without package install for HOSP in Florida on a machine with 65G ram, 11th Gen Intel(R) Core(TM) i9-11950H @ 2.60GHz   2.61 GHz 64bit
tictoc::tic()
bundle <- bundle_data(
  dat = list(
    ebird = ebird_spatial,
    bbs = bbs_spatial,
    grid = grid,
    dirs = dirs
  ),
  overwrite = FALSE, # be sure to overwrite if you tweak arguments above beyond species, species abbr, year, or grid size
  dir.models = dirs$dir.models,
  dir.out = dirs$dir.jags,
  jagam.args = list(
    bs = "ds",
    k = 20,
    family = "poisson",
    sp.prior = "log.uniform",
    diagonalize = TRUE
  )
)
tictoc::toc() # ~120 seconds 
```

The function, `make_jags_list` produces a list of lists, where the
second-level lists comprise objects with similar names. E.g., call:

``` r
names(bundle) # top-level lists
names(bundle$bbs) # second-level lists within the BBS list
str(bundle$bbs$C) # count matrix (site by year)
names(bundle$bbs$Xp) # effects on detection / observer effects
names(bundle$bbs$indexing) # various indexes for use in JAGS loops
View(bundle$metadata) # 'meta' data table for the list resulting from `make_jags_list`
head(bundle$grid$XY) # grd cell centroid coords
head(bundle$grid$area) 
str(bundle$gam) # output from `mgcv::jagam()`
```

Note: if the eventual goal fo the package is to use bundle_data to
produce an analysis-ready list, we can consider having the user specify
in an argument (a) whether they want a list of all possible things or
(b) whether they want analysis-ready data for a particular packaged
model and if so, which model.

# Step 4: Model and Computational Specifications

Specifications for MCMC and parameters to monitor:

``` r
## mcmc specs
mcmc <- set_mcmc_specs() # default values

## initial values
myinits <- list(
  # alpha_pb  = rnorm(1, 0, 0.01),
  alpha_g   = rnorm(1, 0, 0.01),
  beta_g    = rnorm(1, 0, 0.01)
  # beta_pb   = rnorm(1, 0,  0.01),
  # beta_pw   = rnorm(1, 0,  0.01),
  # beta_pf   = rnorm(1, 0,  0.01)
)
inits <- make_inits_list(myinits, nc = mcmc$nc)

## parameters to monitor
params.monitor <- c("lambda_sb", "nu",  "Nb") 
```

Write the model as a .jags or .txt file.

``` r
{mod <- "model{
####################################################
####################################################
# Likelihoods
####################################################
for(t in 1:tb){
  for(s in 1:sb){
    Cb[s,t] ~ dpois(lambda_sb[s])
  } # end bbs data model s
} # end bbs data model t

# using nsgb and sg because we need to account for fact that not all grid cells have bbs data
for(s in 1:sb){ 
  lambda_sb[s]  = inprod(nu[], prop[s,])  # expected count at route-level 
}

for(g in 1:G){     # G = ALL POSSIBLE GRID CELLS, even where count data DNE
  log(nu[g]) = alpha_g + area[g]*beta_g        # 
} # end g (nu)

####################################################
####################################################
# Priors
####################################################
beta_g    ~ dnorm(0,0.01)
alpha_g   ~ dnorm(0,0.01)
####################################################
####################################################
# Derived
####################################################
for(t in 1:tb){
  Nb[t] <- sum(Cb[,t])
}
####################################################
####################################################
}"}
# export model
name <- paste0(dirs$dir.models,"/bbs-base") ## not sure why but when i knit the chunks outside this one it doesn't keep the params, so having trouble putting it up there.
fn   <- paste0(name, ".txt") # we want to name it now so we can call in jags functions
sink(fn)
cat(mod)
sink()
# browseURL(fn) # check file if you please
```

Grab necessary data only from the bundled lists

``` r
jags.data <- list(
  # BBS DATA
  ## Observed Counts
  Cb     = bundle$bbs$C, 
  ## bbs indexes
  sb     = bundle$bbs$indexing$nsites, 
  tb     = bundle$bbs$indexing$nyears, 
  # sgb    = bundle$bbs$indexing$sg,  # col1 == site index (row) col2 == grid ind (col)
  # nsgb   = bundle$bbs$indexing$nsg,  # col1 == site index (row) col2 == grid ind (col)
  ## proportion route in grid
  prop   = bundle$bbs$indexing$prop.sg, 
  # GRID DATA
  area   = scale(bundle$grid$area), 
  G      = nrow(bundle$grid$XY)
)
# free some mem
rm(bbs_spatial, ebird_spatial, grid)
save.image("grr.rdata")
```

# Step 5: Run Model

``` r
# browseURL(fn)
 tictoc::tic()
  fn.out <- paste0(dirs$dir.models, name, ".rds")
  out <- jagsUI::jags(
    data  = jags.data,
    model.file = fn,
    inits = inits,
    parameters.to.save = params.monitor,
    n.chains = mcmc$nc,
    n.thin = mcmc$nt,
    n.iter = mcmc$ni,
    n.burnin = mcmc$nb
  )
  x = tictoc::toc()
  mod.time <- paste0(round(x$toc - x$tic, 2), " seconds")
  out$tictoc.allchains <- mod.time
  # save model outputs
  saveRDS(out, file = fn.out)
```

<!-- # End Run -->
