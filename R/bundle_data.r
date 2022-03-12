#' @title Bundle Data for Use in JAGS (LONG format)
#'
#' @description An updated version of bundle_data, where site by year elements are provided in long format
#' @param bbs BBS data
#' @param ebird eBird data
#' @param grid spatial sampling grid/study area
#' @param scale.covs logical if TRUE will automatically scale the numeric/integer covariates.
#' @param K the maximum number of basis functions that JAGAM will produce. Used for code development purposes, mostly. Do not change unless you know what you're doing.
#' @param X variable name associated with the x-coordinate (e.g., long, longitude, Easting, X) across 'grid', 'bbs', and 'ebird'
#' @param Y variable name associated with the x-coordinate (e.g., latitude, Northing, Y) across 'grid', 'bbs', and 'ebird'
#' @param cell.id column name(s) of the grid cell identifier
#' @param site.id column name(s) of the site  identifier (e.g., BBS route, eBird checklists)
#' @param year.id column name of the temporal identifier
#' @param bf.method method for developing basis functions. Defaults to creating duchon splines using mgcv::jagam().
#' @param obs.id  column name(s) of the observer identifier
#' @param use.ebird.in.ENgrid logical if TRUE will use data across both eBird and BBS observations to create basis functions.
#' @param cell.covs column name(s) of the grid-level covariates
#' @param ENgrid.arg if "max" will use the maximum value of observed birds at each grid cell. Alternatives include "min", "mean".
#' @param site.covs column name(s) of the site-level covariates
#' @param dev.mode logical if TRUE will return a reduced data set to use in development/debugging purposes. This method reduces the number of time units to 2, the maximum number of grid cells to 10, and 2 sites from each data source
#' @param fill.cov.nas value with with to fill missing covariate values. User can specify value as FALSE if no fill is requested.
#' @importFrom dplyr group_by mutate select distinct arrange filter
#'
#' @export bundle_data
bundle_data <-
  function(bbs,
           ebird,
           grid,
           scale.covs  = TRUE,
           fill.cov.nas = sample(size = 1, c(-666,-6969,-999)),
           bf.method   = "cubic2D",
           use.ebird.in.ENgrid = TRUE,
           ENgrid.arg    = "max",
           X           = "cell.lon.centroid",
           Y           = "cell.lat.centroid",
           cell.id     = "gridcellid",
           year.id     = "year",
           site.id     = c("checklist_id", "rteno"),
           obs.id      = c("obsn", "observer_id"),
           cell.covs   = c("area"),
           site.covs   = c(
             "wind",
             "noise",
             "cars",
             "observ",
             "minute",
             "assistant",
             "obsfirstyearbbs",
             "obsfirstyearonbbs",
             "obsfirstyearroute",
             "obsfirstyearonroute",
             "time_observations_started_hsm",
             "time_observations_started",
             "duration_minutes",
             "effort_distance_km",
             "effort_area_ha",
             "protocol_type",
             "protocol_code",
             "number_observers"
           ),
           K = NULL,
           dev.mode    = FALSE) {
    # ARG CHECK AND MUNGE ---------------------------------------------------------------
    ENgrid.arg <- tolower(ENgrid.arg)
    bf.method  <- tolower(bf.method)
    stopifnot(ENgrid.arg %in% c("mean", "max", "min"))
    stopifnot(
        is.integer(fill.cov.nas) |
        is.numeric(fill.cov.nas) |
        is.double(fill.cov.nas) | !fill.cov.nas
    )
    stopifnot(is.logical(use.ebird.in.ENgrid))
    stopifnot(is.logical(scale.covs))
    stopifnot(bf.method %in% c("mgcv", "jagam", "cubic2d"))

    # Drop Spatial Geometry ---------------------------------------------------
    # bbs=bbs_spatial; ebird=ebird_spatial; grid=study_area ## FOR DEV
    bbs   <- as.data.frame(bbs)
    ebird <- as.data.frame(ebird)
    grid  <- as.data.frame(grid)


    # COLS TO LOWER -----------------------------------------------------------
    names(bbs)   <- tolower(names(bbs))
    names(ebird) <- tolower(names(ebird))
    names(grid)  <- tolower(names(grid))

    # RENAME VARS FOR CONSISTENT OUTPUT ----------------------------------------------------
    L <- list(bbs = bbs,
              ebird = ebird,
              grid = grid)
    for (i in seq_along(L)) {
      n <- ns <- nt <- nc <- no <- nx <- ny <- NULL
      ### find overlap in things i want to rename
      n  <- names(L[[i]])
      if (any(year.id %in% n))
        nt <- data.frame(old = n[n %in% c(year.id)], new = "year.id")
      if (any(obs.id %in% n))
        no <- data.frame(old = n[n %in% c(obs.id)], new = "obs.id")
      if (any(site.id %in% n))
        ns <- data.frame(old = n[n %in% c(site.id)], new = "site.id")
      if (any(cell.id %in% n))
        nc <- data.frame(old = n[n %in% c(cell.id)], new = "cell.id")
      if (any(X %in% n))
        nx <- data.frame(old = n[n %in% c(X)], new = "X")
      if (any(Y %in% n))
        ny <- data.frame(old = n[n %in% c(Y)], new = "Y")

      nn <- rbind(nt, ns, nc, nx, ny, no)
      if (is.null(nn))
        next()
      # if(!any(n %in% nn$old))next()
      for (j in 1:nrow(nn)) {
        colind <- which(names(L[[i]]) == nn$old[j])
        names(L[[i]])[colind] <- nn$new[j]
      }
    }#end L loop

    bbs   <- L$bbs
    ebird <- L$ebird
    grid  <- L$grid
    rm(L)

    # Ensure no duplicates exist ----------------------------------------------
    bbs   <-
      bbs %>% distinct(year.id, site.id, cell.id, c, .keep_all = TRUE)
    ebird <-
      ebird %>% distinct(year.id, site.id, cell.id, c, .keep_all = TRUE) ## this is a prtoblem (duplicates in ebird, though it might be because we have multiple observers. huge amoutn of excess data..)

    # SUBSET FOR dev.mode -----------------------------------------------------
    # browser()
    if (dev.mode) {
      message(paste0(
        "dev.mode=TRUE; output object will be a subset of original data.\n"
      ))
      # ebird=ebird_spatial;bbs=bbs_spatial;grid=study_area
      # keep 3 years data max
      T.keep <- max(unique(bbs$year.id), na.rm = TRUE)
      T.keep <- (T.keep - 10):T.keep
      G.keep <- sample(unique(grid$cell.id), 10)
      ## keep max 10 grid cells
      grid <- grid[grid$cell.id %in% G.keep,]

      bbs  <-   bbs %>% filter(cell.id %in% G.keep &
                                 year.id %in% T.keep)
      ebird  <- ebird %>% filter(cell.id %in% G.keep &
                                   year.id %in% T.keep)
      # bbs    <- bbs[bbs$cell.id %in% G.keep &
      #                      bbs$year.id %in% T.keep, ]
      #
      # ebird  <- ebird[ebird$cell.id %in% G.keep & ### this is inferior to above, it hink. doesnt wanna run
      #                   ebird$year.id %in% T.keep, ] ## filter is much faster than base...

      ## keep random sample of 10 routes or checklists per grid cell
      ### this will likely not reduce bbs by much (possible zero reduction) but will reduce ebird
      #### slice_max orders by site and takes 'top' n
      b.samp.keep <- bbs %>%
        dplyr::distinct(year.id, cell.id, site.id, .keep_all = TRUE) %>%
        group_by(year.id, cell.id) %>%
        mutate(maxn=n_distinct(site.id))
      bbs <- b.samp.keep %>%
        slice_sample(n=min(b.samp.keep$maxn, 10)) %>%
        ungroup()

      e.samp.keep <- ebird %>%
        dplyr::distinct(year.id, cell.id, site.id, .keep_all = TRUE) %>%
        group_by(year.id, cell.id) %>%
        mutate(maxn=n_distinct(site.id))
      ebird <- e.samp.keep %>%
        slice_sample(n=min(e.samp.keep$maxn, 10)) %>%
        ungroup()

      rm(T.keep, G.keep, e.samp.keep, b.samp.keep)
    }
    # GLOBAL INDEXES -----------------------------------------------------------------
    cat("  [note] creating global indexes\n")
    ## STUDY AREA GRID CELL INDEX
    cell.index <- grid %>%
      units::drop_units() %>%
      arrange(cell.id) %>%
      distinct(cell.id, X, Y, .keep_all = TRUE) %>%
      # create grid cell id as index and not identity (though they may be the)
      mutate(cell.ind = 1:n())
    # keep only useful information....
    cell.index <-
      cell.index[names(cell.index) %in% c("cell.id", "cell.ind", "X", "Y", cell.covs)]
    ## scale if specified
    if (scale.covs) {
      cell.index <- cell.index %>%
        mutate(area = standardize(area)) %>%
        mutate(X  = standardize(X)) %>%
        mutate(Y  = standardize(Y))
    }

    ## YEAR INDEX
    year.index <-
      data.frame(year.id = min(c(ebird$year.id, bbs$year.id), na.rm = TRUE):max(c(ebird$year.id, bbs$year.id), na.rm =
                                                                                  TRUE)) %>% mutate(year.ind = 1:n())
    # ### YEAR-GRID INDEX
    # # make a version of all years and grid index combinations, regardless data availability.
    # # this is used here, internally, but can also be called in certain jags model components
    yg.index <-
      expand.grid(year.ind = year.index$year.ind,
                  cell.ind = cell.index$cell.ind) %>%
      merge(year.index) %>%
      merge(cell.index) %>%
      dplyr::select(cell.ind, cell.id, year.ind, year.id)

    # BBS-EBIRD INDEXES ---------------------------------------------------------------
    ## for bbs and ebird data, create site (route, checklist_id) and observer indexes
    LL <- list(bbs = bbs, ebird = ebird)
    cat("  [note] creating indexes for sampling events and sites")
    for (i in seq_along(LL)) {
      ## first, drop grid-level covariates and metadata since it iwll be stored there
      LL[[i]] <-
        LL[[i]][!names(LL[[i]]) %in% c("X", "Y", cell.covs)]
      ## second, drop NA count values, since we don't want to include non-sampled site-year combinations
      LL[[i]] <- LL[[i]] %>%
        units::drop_units() %>%
        filter(!is.na(site.id),!is.na(c))
      ## create index each for SITE and OBSERVER, then append to the data frame
      LL[[i]] <-
        LL[[i]] %>%
        mutate(obs.ind  = obs.id  %>% as.factor() %>% as.integer()) %>%
        mutate(site.ind = site.id %>% as.factor() %>% as.integer())
      ## just to be safe, ensure all join by vars are same type
      LL[[i]] <- LL[[i]] %>%
        mutate(year.id = as.integer(year.id),
               cell.id = as.integer(cell.id))

      ## this is a shitty workaround, but currently (other than using data.table)
      ## is the only tractable way I know for dealing with the large eBird data tables...
      ## using a direct left join or a merge is not possible, even on my 60+GB RAM machine..
      ## very happy to receive changes
      #### extract the columsn on which to join

      LL.sub <- LL[[i]] %>% dplyr::select(cell.id, year.id)
      LL.sub <-
        LL.sub %>% left_join(yg.index, by = c("cell.id", "year.id"))
      stopifnot(nrow(LL.sub) == nrow(LL[[i]]))
      ### remove from the LL.sub extracted columns from data and then append new (four ) columns
      LL[[i]] <- LL[[i]] %>% dplyr::select(-cell.id,-year.id)

      LL[[i]] <- LL[[i]] %>%  dplyr::bind_cols(LL.sub)

      stopifnot(!any(is.na(LL[[i]]$cell.ind)))
      stopifnot(!any(is.na(LL[[i]]$year.ind)))

      ## finally, drop the NA observations on bbs and ebird..
      LL[[i]] <-     LL[[i]][!is.na(LL[[i]]$site.ind), ]

    } # end LL loop
    # browser()
    ##extract from list
    bbs   <- LL$bbs
    ebird <- LL$ebird
    rm(LL)

    # BBS-SPECIFIC DATA CREATE MATRIX PROP (% site.ind in cell.ind) ----------------------------------------------------
    stopifnot(nrow(bbs %>% distinct(site.ind, cell.ind, proprouteincell)) ==
                nrow(bbs %>% distinct(site.ind, cell.ind)))
    ## grab all cell ids and site inds
    prop <- bbs %>%
      distinct(site.ind, cell.ind, proprouteincell) %>%
      full_join(cell.index %>% dplyr::select(cell.ind), by = "cell.ind")
    prop$proprouteincell[is.na(prop$proprouteincell)] <-
      0  ##supply prop with zero if route
    prop <-
      reshape2::acast(prop,
                      site.ind ~ cell.ind,
                      value.var = "proprouteincell",
                      fill = 0)
    # remove the rownames==NA (the last row usually..)
    if (any(rownames(prop) %in% c("NA", NA))) {
      prop <-
        prop[-which(rownames(prop) %in% c(NA, "NA")),]
    }

    # COVARIATES --------------------------------------------------------------
    ## create arrays for covariates
    ### dimensions are n.sites by n.years
    LL    <- list(bbs = bbs,  ebird = ebird) # data
    Xsite <- list(bbs = NULL, ebird = NULL) # empty list for storing site-cov matrices for bbs and ebird data
    cat("  [note] creating site-level covariate matrices....\n")
    for (i in seq_along(LL)) {
      temp <- site.covs[site.covs %in% names(LL[[i]])]
      if (length(temp) == 0)
        next()
      # remove the extra data (for routes w/>1 grid cell)
      LL[[i]] <-
        LL[[i]] %>% dplyr::distinct(site.ind, year.ind, .keep_all = TRUE)
      for (j in seq_along(temp)) {
        cov.name  <- temp[j]

        cov.dat   <- data.frame(as.vector(LL[[i]][cov.name]),
                                LL[[i]]["site.ind"],
                                LL[[i]]["year.ind"])
        ## scale the covariate if scale.covs==TRUE'###
        #### NEED TO ADD OPTION TO OUTPUT COV>DAT IN LONG FORM (PERHAPS JUST APPEND AS SCALED VERSIONS TO EBIRd/BBS.DF..)
        names(cov.dat)[1] <- "cov"
        if (all(is.na(cov.dat$cov))){next()}
        is.time   <- class(cov.dat$cov) %in% c("period", "time", "Period")
        is.binary <-if(is.time){FALSE}else{
          !(max(cov.dat$cov, na.rm = TRUE) > 1)
        }
        is.factor <- ifelse(is.factor(cov.dat$cov) | is.character(cov.dat$cov), TRUE, FALSE )
        if(is.time) cov.dat$cov <- cov.dat$cov@hour*60 + cov.dat$cov@minute
        if (scale.covs &
            is.binary)
          cat("  [note] site covariate ",
              cov.name,
              " is binary and was not standardized.\n",
              sep = "")
        if (scale.covs &
            is.factor){cat("  [note] site covariate ",
              cov.name, " is a factor and was not standardized (but was converted to integer) \n",
              sep = "")
          cov.dat$cov <- as.integer(as.factor(cov.dat$cov))

          }

        if (scale.covs &
            !is.binary) {
          cov.dat$cov <- standardize(cov.dat$cov)
        }

       ### specify the fill value
       fill.value <- ifelse(!fill.cov.nas, NA, fill.cov.nas)

       ## create a matrix for the site covariates and add to the Xsite list
       cov.mat  <-  reshape2::acast(cov.dat,
                                     site.ind ~ year.ind,
                                     value.var = "cov",
                                     fill = fill.cov.nas)
      ## to ensure rownames and colnames match the indexes..
      stopifnot(all(as.integer(rownames(cov.mat)) == as.integer(sort(
        unique(cov.dat$site.ind)
      ))))
      stopifnot(all(as.integer(colnames(cov.mat)) == as.integer(sort(
        unique(cov.dat$year.ind)
      ))))

      Xsite[[i]][[j]] <- cov.mat
      names(Xsite[[i]])[j] <- cov.name
      ### finally, replace the orgiinal data with the transformed vectors.
      cov.dat$cov[is.na(cov.dat$cov)] <- fill.value
      LL[[i]][cov.name]  <- cov.dat$cov
      } # j loop
    }# end Xsite i loop
    cat("  [note] done building covariate matrices\n")

    ## rename LL elements
    bbs   <- LL$bbs
    ebird <- LL$ebird


    # GRID-LEVEL COVARIATES ---------------------------------------------------
    ## create arrays for grid cell-level covariates
    ### dimensions are ngrid by nyear
    Xgrid <- list(NULL)

    cell.index <- cell.index %>% arrange(cell.ind)
    cell.covs <- cell.covs[cell.covs %in% colnames(cell.index)]
    if (!is.null(cell.covs)) {
      for (i in seq_along(cell.covs)) {
        Xgrid[[i]] <- cell.index[, cell.covs[i]]
        names(Xgrid)[i] <- cell.covs[i]
      }# end Xgrid loop
    }# end if cell.covs

    # BASIS FUNCTIONS -------------------------------------------------------------
    # create basis functions and data for GAM model components
    ## first, we need to grab the maximum number of birds per grid cell/year
    ## argument use.ebird.in.ENgrid lets user ignore the eBird data when producing the GAM data
    ## this is important when modeling only the BBS data, as eBird observations
    ## are typically >>> BBS observations for some (many?) species.
    # cat("  [note] creating basisi functions")
    if (use.ebird.in.ENgrid) {
      ENgrid <- rbind(
        bbs %>% dplyr::distinct(cell.ind, year.ind, c),
        ebird %>% dplyr::distinct(cell.ind, year.ind, c)
      )
    } else{
      ENgrid <-  bbs %>% dplyr::distinct(cell.ind, year.ind, c)
    }

    # evaluate according to specified argument.
    ### id prefer to just evaluate the argument inside the
    ### the filter call, but not sure rn how to do that.
    ### using filter(c==eval(parse(text=paste0(ENgrid.arg,"(c,na.rm=TRUE)")))))
    ### did not work. Nor does bang bang !!ENgrid.arg(c,na.rm=TRUE)
    ### have yet to test out !!rlang::sym(Engrid.arg)(c,na.rm=TRUE)..

    myfun = paste0(
      "test <- ENgrid %>%\n
      dplyr::group_by(cell.ind, year.ind) %>%\n
      dplyr::filter(c ==",
      ENgrid.arg,
      "(c, na.rm=TRUE)) %>%\n
      dplyr::ungroup()\n"
    )
    eval(str2expression(myfun))

    ## next, add the missing grid cells and fill in with grand MEAN
    gy.all <- expand.grid(cell.ind = cell.index$cell.ind,
                          year.ind = year.index$year.ind)
    ENgrid <-
      full_join(gy.all, ENgrid, by = c("cell.ind", "year.ind"))
    ENgrid$c[is.na(ENgrid$c)] <-
      round(mean(ENgrid$c, na.rm = TRUE), 0)

    ## make a matrix of ENgrid for use in JAGS model as the expected abundance in grid cell.
    ### for casting into a matrix, first sum C within each cell and year.
    ENgrid <- ENgrid %>% dplyr::group_by(cell.ind, year.ind) %>%
      dplyr::mutate(c = sum(c, na.rm = TRUE)) %>%
      dplyr::ungroup() %>%
      dplyr::distinct()
    ENgrid.mat   <-  reshape2::acast(
      ENgrid,
      cell.ind ~ year.ind,
      value.var = "c",
      fill = mean(ENgrid$c, na.rm = TRUE)
    )



    # create data for use in creating spatial basis functions
    bf.in <- data.frame(merge(ENgrid, cell.index))
    bf.in <-
      bf.in %>%
      dplyr::group_by(cell.ind) %>%
      dplyr::filter(c == max(c, na.rm = TRUE)) %>%
      dplyr::ungroup() %>%
      dplyr::distinct(cell.ind, .keep_all = TRUE)

    ### 'scale' down the XY coordinates until max is under 10 (10 is an arbitrary choice sorta)
    while (abs(max(c(bf.in$X, bf.in$Y), na.rm = TRUE)) > 10) {
      bf.in <- bf.in %>%
        dplyr::mutate(X = X / 10,
                      Y = Y / 10)
    }


    ## DEFINE K  ---------------------------------------------------------------
    # if not specified, K is defined as:
    ### this is kind of arbitrary. based on some Wood, Simon paper about min 20
    ### and anything > like 100 will crash most systems.
    ### also need to consider compute time for use in Bayesian param estiamtion
    if (is.null(K)) {
      K <- min(length(unique(ENgrid$cell.ind)), 150)
    }

    ## JAGAM -------------------------------------------------------------------------
    message(
      "[FYI] K is currently set to ",
      K,
      ". If you have memory errors, try defining K in arguments as a lower value\n"
    )
    if (bf.method %in% c("mgcv", "jagam")) {
      cat("  [note] creating 2D duchon splines using `mgcv::jagam()`\n")
      jagam.fn <- paste0(dirs$dir.models, "/gam-UNEDITED.txt")
      jagam.mod <- mgcv::jagam(
        c ~ s(
          # note the c doesn't matter, it's just for show
          X,
          Y,
          bs = "ds",
          k = K,
          m = c(1, 0.5)
        ),
        file = jagam.fn,
        sp.prior = "log.uniform",
        data = bf.in,
        diagonalize = TRUE,
        # parallell = TRUE,
        # modules = "glm"
        family = "poisson"
      )
      jagam.mod$fn <- jagam.fn
      ## specify some output scalars and data
      Z.mat <-
        jagam.mod$jags.data$X               # dims <ncells  by nknots>
      nbfs  <-
        dim(jagam.mod$jags.data$X)[2]        # number of basis functions/knots

    } else{
      jagam.mod <- NULL
    }

    ##STREBEL ET AL METHOD --------------------------------------------------
    ### follow the methods of Strebel et al. (which follows methods of Royle and Kery AHM)
    if (bf.method %in% c("cubic2d")) {
      # browser()
      cat("  [note] creating 2D cubic splines\n")
      XY <- bf.in[c("X", "Y")] ### the "scaled down" coordinates
      XY.orig <- cell.index[c("X", "Y")]
      # Define the omega and Z.k matrices for the random effects
      omega.all <-
        fields::rdist(XY, XY) ^ 3 # 2D cubic splines on "reduced coords
      svd.omega.all <- svd(omega.all)
      sqrt.omega.all <-
        t(svd.omega.all$v %*% (t(svd.omega.all$u) * sqrt(svd.omega.all$d)))
      ##
      Z.k   <- (fields::rdist(XY.orig, XY)) ^ 3
      Z.mat <- t(solve(sqrt.omega.all, t(Z.k)))
      nbfs  <- dim(Z.mat)[2]
    }

    # BUNDLE DATA -------------------------------------------------------------
    bundle.out <- list(
      # "all" data
      bbs.df     = bbs %>% distinct(year.ind, site.ind, .keep_all = TRUE),
      ebird.df   = ebird %>% distinct(year.ind, site.ind, .keep_all = TRUE),
      grid.df    = grid,
      # max C per grid per year  (zero-filled)
      ENgrid       = ENgrid,
      ENgrid.mat   = ENgrid.mat,
      # covariate matrices
      Xsite      = Xsite,
      Xgrid      = Xgrid,
      # indexes created
      prop       = prop,
      # % BBS route per grid cell (dims <ngrid nroutes>)
      cell.index = cell.index,
      # lookup table for grid cells
      year.index = year.index,
      # lookup table for year
      # create indexes here
      T          = length(unique(year.index$year.ind)),
      # number of years across all data
      G          = length(unique(cell.index$cell.id)),
      # number of grid cells in study area
      Mb         = length(unique(bbs$site.id)),
      # number of routes bbs
      Me         = length(unique(ebird$site.id)),
      # number of checklists bbs
      gy         = gy.all,
      ngy        = nrow(gy.all),
      ## more indexes
      GTb        = bbs   %>% dplyr::distinct(cell.ind, year.ind) %>% dplyr::arrange(cell.ind, year.ind),
      # grid-years sampled bbs
      GTe        = ebird %>% dplyr::distinct(cell.ind, year.ind) %>% dplyr::arrange(cell.ind, year.ind),
      # grid-years sampled ebird
      # all JAGAM output
      Z.mat      = Z.mat,
      # dims <ncells  by nbfs/knots
      nbfs       = nbfs                                 # number of basis functions/knots
    )


    # RETURNED OBJECT ---------------------------------------------------------
    stopifnot(!any(is.na(bundle.out$bbs.df$c)))
    stopifnot(!any(is.na(bundle.out$ebird.df$c)))

    return(bundle.out)

  } # end function
