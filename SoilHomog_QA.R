#### SoilHarmonization QA ####
# This standalone script takes a user input Google Drive folder name and verifies that
# the soilHarmonization function has correctly produced a homogenized data file with all 
# the specified location and profile data given by the corresponding keykey file. Output
# to the working directory includes log file of data check flags and .png plots of data 
# variables.


#Load libraries
library(tidyr)
library(googledrive)
library(googlesheets)
library(lattice)
library(reshape2)
library(ggplot2)

homogenization.qa <- function(directoryName, temp.folder) {
  
  ### Get files from GD ###
  #########################################
  # Get files in specified GDrive folder (we can wrap this into ftn later)
  
  # FOR DEBUG
  # directoryName <- "Calhoun"
  # Original test diretcory: "HBR_W1"
  
  # Find files, same as homog script
  # access Google directory id for reference
  googleID <- googledrive::drive_get(directoryName) %>%
    dplyr::pull(id)
  
  # list files in Google directory
  dirFileList <- googledrive::drive_ls(path = directoryName)
  
  # isolate names from Google directory
  dirFileNames <- dirFileList %>%
    dplyr::select(name) %>%
    dplyr::pull(name)
  
  # Remove 'duplicates' folder from file name list
  dirFileNames <- dirFileNames[dirFileNames != 'duplicates']
  
  # Load raw data
  raw.name <- dirFileNames[!grepl("key",dirFileNames, ignore.case = T) & !grepl("HMGZD",dirFileNames, ignore.case = T) & 
                             !grepl("_log",dirFileNames, ignore.case = T) & !grepl("_plot",dirFileNames, ignore.case = T)]
  raw.data <- gs_read(ss=gs_title(raw.name), ws = 1, skip=0)
  
  # Load keykey
  key.name <- dirFileNames[grepl("key",dirFileNames, ignore.case = T) & !grepl("HMGZD",dirFileNames, ignore.case = T)] 
  key.loc <- gs_read(ss=gs_title(key.name), ws = 1, skip=0)
  key.prof <- gs_read(ss=gs_title(key.name), ws = 2, skip=0)
  
  # Load HMGZD
  hmg.name <- dirFileNames[!grepl("key",dirFileNames, ignore.case = T) & !grepl("notes",dirFileNames, ignore.case = T) & grepl("HMGZD",dirFileNames, ignore.case = T)]
  hmg.data <- gs_read(ss=gs_title(hmg.name), ws = 1, skip=0)
  
  ### Data QA checks ###
  ###############################################
  # Create list for .txt export
  QA.results <- list(directoryName,raw.name,key.name,hmg.name[1])
  
  # Formatting step - Add space in txt output
  QA.results <- append(QA.results, "")
  
  ### CHECK 1
  # Check match raw data nrow vs HMGZD nrow
  if(nrow(raw.data) == nrow(hmg.data)) {
    print("CHECK TRUE - Data rows match")
    QA.results <- append(QA.results, "Check True - Number of data rows match")
  } else {
    print("CHECK FALSE - Number of data rows do NOT match")
    QA.results <- append(QA.results, "FLAG - Number of data rows do NOT match")
  }
  
  ### CHECK 2
  
  ###TURNING OUT FALSE NEGATIVES DUE TO ROUNDING OF NUMERICS - NEEDS WORK
  
  # Check that all location values exist in HMGZD data
  loc.values <- c(na.omit(key.loc[,1]))
  hmg.toprow <- c(na.omit(t(hmg.data[1,])))
  
  if(length(intersect(loc.values[[1]], hmg.toprow)) == length(unique(loc.values[[1]]))) {
    print("CHECK TRUE - All location data found in HMGZD")
    QA.results <- append(QA.results, "Check True - All location data found in HMGZD")
  } else {
    print("CHECK FALSE - All location data NOT found in HMGZD")
    QA.results <- append(QA.results, "FLAG - All location data NOT found in HMGZD")
  }
  
  # Formatting step - Add space in txt output
  QA.results <- append(QA.results, "")
  
  # CHECK 3
  # Check profile data length
  
  # dataframe housekeeping
  # Convert dplyr dataframe output to standard dataframe
  hmg.data <- as.data.frame(hmg.data)
  key.prof <- as.data.frame(key.prof)
  
  # Convert NA data values to NA using specified value from keykey
  # Conversion NA warning expected
  nay.1 <- as.numeric(key.loc[13,1])
  nay.2 <- as.numeric(key.loc[14,1])
  
  hmg.data[hmg.data==nay.1]<-NA
  hmg.data[hmg.data==nay.2]<-NA
  
  raw.data[raw.data==nay.1]<-NA
  raw.data[raw.data==nay.2]<-NA
  
  # Output number of homogenized profile data columns
  prof.vars <- as.list(na.omit(key.prof[,c(1,4)]))
  QA.results <- append(QA.results, c(paste0("Found ",length(prof.vars[[1]]), " profile data columns to homogenize"),""))  
  
  
  for (i in 1:length(prof.vars[[1]])) {
    if(length(na.omit(hmg.data[[prof.vars[[2]][i]]])) != length(na.omit(raw.data[[prof.vars[[1]][i]]]))) {
      print(paste0("FLAG -Raw data variable ",prof.vars[[1]][i]," does not match HMGZD variable ",prof.vars[[2]][i]))
      QA.results <- append(QA.results, paste0("FLAG -Raw data variable ",prof.vars[[1]][i]," does NOT match HMGZD variable ",prof.vars[[2]][i]))
    } else {
      print(paste0("Raw data variable ",prof.vars[[1]][i]," confirmed to ",prof.vars[[2]][i]))
      QA.results <- append(QA.results, paste0("Raw data variable ",prof.vars[[1]][i]," confirmed to ",prof.vars[[2]][i]))
    }
  }
  # Console print status
  print("Variable input checks complete")
  
  ### Data QA plots ###
  # Prep values and data for plotting
  # Find number of experiment levels and number of data columns
  exp.lvls <- length(na.omit((key.prof[1:13,1])))
  data.cols <- length(prof.vars[[1]]) - exp.lvls
  
  # Melt data for plotting variables by experiment lvls
  m1 <- melt(hmg.data[,(ncol(hmg.data)-length(prof.vars[[1]])+1):ncol(hmg.data)], id.vars=seq(1,exp.lvls))
  
  # Convert values to numeric, NA's from non-numeric data expected, will produce blank plot in next step
  m1$value <- as.numeric(m1$value)
  
  # Plot all variables by experiment lvls and export plot to wd
  # NOTE: Used for-loop because I was having trouble indexing the hmg.data columns when using a ftn for plots. Stevan?
  for (i in 1:exp.lvls) {
    ggplot(m1,aes(x = as.character(m1[,i]), y = value, color=as.character(m1[,i]))) + facet_wrap(~variable, scales = "free_y") + 
      geom_boxplot() + geom_point(position = position_jitterdodge(), alpha = 0.3) + xlab(names(m1)[i]) + 
      theme(axis.text.x=element_text(angle=45, hjust=1),legend.position="none") + scale_colour_hue(l=50)
    
    ggsave(paste0(directoryName,"_",names(m1)[i],"_profile data_plot.png"), path=temp.folder, width=10, height=8)
  }
  
  
  ### COMMENT: Fairly easy to add in lvl combos, ie:L1 x tx_L1 --> boxplot. However, this will get messy if we were to 
  #           force all combos. Will --> Are there specific experiment and treatment combos of interest? Perhaps the highest lvls?
  
  
  ### Export QA results to csv log file
  ##############################################
  txt.output <- data.frame(matrix(unlist(QA.results), nrow=length(QA.results), byrow=T),stringsAsFactors=FALSE)
  write.table(txt.output,file=paste0(temp.folder,"/", directoryName,"_homog_log.txt"), col.names = F, row.names = F)
  
  # Console print status
  print("Data QA log export complete")
  
  
  ### Upload QA log and plots back to GDrive directory
  #########################################################
  filesToUpload <- c(row.names(file.info(list.files(pattern="*.png",path=temp.folder))),row.names(file.info(list.files(pattern="*.txt",path=temp.folder))))
  
  # upload these files to the target Google directory
  ###CHANGED TO USE THE WORKING DIRECTORY...
  lapply(filesToUpload, function(frame) {
    googledrive::drive_upload(paste0(temp.folder,"/", frame),
                              path = googledrive::drive_get(googledrive::as_id(googleID)),
                              type = "spreadsheet")
  })
 
  #Remove temporary files
  file.remove(file.path(temp.folder, list.files(temp.folder))) 
}

#DEBUG
# Ftn test
  #temp.files <- "C:/Users/Derek/Google Drive/Code/R/temp"
  #homogenization.qa(directoryName="Calhoun", temp.folder=temp.files)

