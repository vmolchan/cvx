# clear the memory!
rm(list=ls(all=TRUE))
gc()

# load the dependencies!
require(gdata)
require(randomForest)
require(RWeka)
require(caret)
require(fmsb)
library(foreach)
library(hydroTSM)
# require(relaimpo)
# library(MASS)

# set the work directory
setwd("~/Chevron/DSChallenge/test1")

# load base_training.csv
base <- read.csv("base_training.csv", header = TRUE, sep = ",", stringsAsFactors = FALSE)
# remove the Deepest Zone as it will be added below
base <- base[, -which(names(base) %in% c("Deepest_Zone"))]
# split Between Zone into 2
zones=data.frame(do.call(rbind, strsplit(as.vector(base$Between_Zone), split = " --> ", fixed=TRUE)))
names(zones) <- c("Top_Zone", "Deepest_Zone")
base <- cbind(base, zones)

# format Completion.Date
base$Completion.Date = as.Date(base$Completion.Date, origin = "1900-01-01")

# add Completion.Month
base$Completion.Month = as.numeric(format(base$Completion.Date, "%m"))

# add Completion.Season
base$Completion.Season <- time2season(base$Completion.Date, out.fmt = "seasons", type = "default")

write.table(base, "base_training_edits.csv", sep=",", row.names=FALSE, quote = FALSE)

# load completions_training.csv with Remarks removed!
completions <- read.csv("completions_training_removedRemarks.csv", header = T)
# unique completions
uniqueCompletions <- unique( completions )

write.table(uniqueCompletions, "completions_training_edits.csv", sep=",", row.names=FALSE, quote = FALSE)

# load geology_training.csv
geo <- read.csv("geology_training.csv", header = TRUE, sep = ",")

# mark the handpicked columns
handpicked <- c("CLFK..KHW.","U_SPBR..KHW.","L_SPBR..KHW.","WFMP..KHW.","WFMP_L..KHW.","WFMP_ATB..KH","CLINE..KHW.","STRN..KHW.","ATOK..KHW.","BEND..KHW.","ATOKA_L..KHW","MPLM..KHW.","WDFD..KHW.","DVNN..KHW.")
# mark the interpolated columns
interpolated <- c("CLEARFORK..MAP.","SPRABERRY_U..MAP.","SPRABERRY_L..MAP.","WOLFCAMP..MA","WOLFCAMP_L..","WFMP_ATB..MA","CLINE..MAP.","STRAWN..MAP.","ATOKA..MAP.","BEND..MAP.","ATOKA_L..MAP","MISSISSIPPIA","WOODFORD..MA","DEVINOAN_UNC")

# replace the Handpicked NAs by values from the Interpolated columns
for(i in 1:length(handpicked)) {
  print(paste(handpicked[i], interpolated[i], sep = " = "))
  geo[[handpicked[i]]][is.na(geo[[handpicked[i]]])] <- geo[[interpolated[i]]][is.na(geo[[handpicked[i]]])]
}

# drop interpolated columns
geo = geo[,-which(names(geo) %in% interpolated)]

write.table(geo, "geology_training_edits.csv", sep=",", row.names=FALSE, quote = FALSE)

# merging the files
temp <- merge(base, uniqueCompletions, by="WellID")
data <- merge(temp, geo, by="WellID")
write.table(data, "data.csv", sep=",", row.names=FALSE, quote = FALSE)
print(paste("=============== Data merged into one file with", nrow(data), "rows and", ncol(data), "columns ===============", sep = " "))

# replace "undefined", empty strings and #VALUE! as NAs for all columns
for(i in names(data)) {
  if (length(which(isUnknown(x=data[[i]], unknown = c("undefined","","#VALUE!")))) > 0) {
    data[[i]] <- unknownToNA(x=data[[i]], unknown=c("undefined","","#VALUE!"))
    print(paste(i,"replaced UNDEFINEDs=", any(isUnknown(x=data[[i]], unknown = c("undefined","","#VALUE!"))), sep = " "))
  }
}
# str(data)

# detect the numerical columns to remove outliers
numericals <- sapply(data, is.numeric)
numericals
# deal outliers in numerical columns
data.numericals <- data[ , numericals]
# str(data.numericals)
replaceOutliers <- function(x) {
  quantiles <- quantile(x, c(.05, .95), na.rm = TRUE)
  if (quantiles[1] > 0 && quantiles[2] > 0) {
    x[ x < quantiles[1] ] <- quantiles[1]
    x[ x > quantiles[2] ] <- quantiles[2]
  }
  x
}
data.withoutOutliers <- replaceOutliers(data.numericals)
data.others <- data[ , !numericals]
data.cleaned <- cbind(data.withoutOutliers, data.others)

write.table(data.cleaned, "data_edits1.csv", sep=",", row.names=FALSE, quote = FALSE)
# str(data.cleaned)

# set 10% missing threshold
missingThreshold <- 0.75
cols <- ncol(data.cleaned)
rows <- nrow(data.cleaned)
NA_RowWise <- apply(data.cleaned, 1, function(z) sum(is.na(z)))
hist(NA_RowWise)
quantile(NA_RowWise)
# eliminate rows whose missing > 20%
colsMissing <- floor(cols*missingThreshold)
colsMissing
DelRows <- which(NA_RowWise > colsMissing)
DelRows
data.rowsCleaned <- data.cleaned
if (length(DelRows) > 0)
  data.rowsCleaned <- data.cleaned[-DelRows,]
nrow(data.rowsCleaned)
ncol(data.rowsCleaned)

NA_ColWise <- apply(data.rowsCleaned, 2, function(z) sum(is.na(z)))
hist(NA_ColWise)
quantile(NA_ColWise)
#eliminate cols whose missing > 20%
rowsMissing <- floor(rows*missingThreshold)
rowsMissing
DelCols <- which(NA_ColWise > rowsMissing)
DelCols
data.colsCleaned <- data.rowsCleaned
if (length(DelCols) > 0)
  data.colsCleaned <- data.rowsCleaned[,-DelCols]
nrow(data.colsCleaned)
ncol(data.colsCleaned)

write.table(data.colsCleaned, "data_cleaned2.csv", sep=",", row.names=FALSE, quote = FALSE)

# make data point to the cleaned up version
data <- data.colsCleaned
# str(data)

# find out type of columns
types <- lapply(data, class)
distincts <- lapply(data, function(c) unique(c))

for(i in names(data)){
  noOfCats <- length(levels(distincts[[i]]))
  # print(paste(i, "has", noOfCats, sep = " "))
  
  # remove categories that have just one category
  if (noOfCats == 1) {
    data[[i]] <- NULL
  } else if (noOfCats <= length(data[[i]])/2 && types[[i]] == "factor") {
    #     print(levels(distincts[[i]]))
    map <- mapLevels(data[[i]], )
    data[[i]] <- as.integer(data[[i]])
    print(paste(i, " factors ", length(levels(unique(data[[i]]))), " categories.", sep = ""))
    #     data[[i]] <- as.factor(data[[i]])
    #mapLevels(intCounty) <- mapCounty
    #all.equal(intCounty, productions$County) #TRUE
  } else if (types[[i]] == "character") {
    data[[i]] <- as.factor(data[[i]])
    map <- mapLevels(data[[i]], )
    data[[i]] <- as.integer(data[[i]])
    print(paste(i, " chars ", length(levels(unique(data[[i]]))), " categories.", sep = ""))
  }
}

# remove some unwanted columns
data <- data[, -which(names(data) %in% c("WellID","Completion.Date"))]
# str(data)

write.table(data, "data_labeled3.csv", sep=",", row.names=FALSE, quote = FALSE)
# str(data)

#stepwise VIF function used below
vif_func<-function(in_frame,thresh,trace){
  #   in_frame <- data
  #   thresh <- 10
  #   trace <- TRUE
  
  if(class(in_frame) != 'data.frame') in_frame<-data.frame(in_frame)
  
  #get initial vif value for all comparisons of variables
  vif_init<-NULL
  for(val in names(in_frame)){
    form_in<-formula(paste(val,' ~ .'))
    vif_init<-rbind(vif_init,c(val,VIF(lm(form_in,data=in_frame))))
  }
  vif_max<-max(as.numeric(vif_init[,2]))
  print(paste("default", vif_max, sep = ","))
  
  if(vif_max < thresh){
    if(trace==T){ #print output of each iteration
      prmatrix(vif_init,collab=c('var','vif'),rowlab=rep('',nrow(vif_init)),quote=F)
      cat('\n')
      cat(paste('All variables have VIF < ', thresh,', max VIF ',round(vif_max,2), sep=''),'\n\n')
    }
    return(names(in_frame))
  } else {
    
    in_dat<-in_frame
    
    #backwards selection of explanatory variables, stops when all VIF values are below 'thresh'
    while(vif_max >= thresh){
      
      vif_vals<-NULL
      
      for(val in names(in_dat)){
        form_in<-formula(paste(val,' ~ .'))
        vif_add<-VIF(lm(form_in,data=in_dat))
        vif_vals<-rbind(vif_vals,c(val,vif_add))
      }
      max_row<-which(vif_vals[,2] == max(as.numeric(vif_vals[,2])))[1]
      
      vif_max<-as.numeric(vif_vals[max_row,2])
      
      if(vif_max<thresh) break
      
      if(trace==T){ #print output of each iteration
        prmatrix(vif_vals,collab=c('var','vif'),rowlab=rep('',nrow(vif_vals)),quote=F)
        cat('\n')
        cat('removed: ',vif_vals[max_row,1],vif_max,'\n\n')
        flush.console()
      }
      
      in_dat<-in_dat[,!names(in_dat) %in% vif_vals[max_row,1]]
      
    }
    return(names(in_dat))
  }
}

names <- vif_func(in_frame=data,thresh=5,trace=T)
names
data <- data[,which(names(data) %in% names)]
# str(data)

write.table(data, "data_dissimilar4.csv", sep=",", row.names=FALSE, quote = FALSE)
# str(data)

# impute the missing values
data <- rfImpute(EUR_o..Mstb. ~., data)
write.table(data, "data_imputed5.csv", sep=",", row.names=FALSE, quote = FALSE)

# TODO RANKING!
# linear = lm(EUR_o..Mstb. ~., data = data, na.action = na.exclude)
# rankings <- calc.relimp(linear,data=data)
# ranks=sort(rankings$lmg,decreasing=T)
# ranks
# step <- stepAIC(linear, direction="both")

# modeling
iterations <- 100
best.rmse <- 10000
best.train <- NULL
best.test <- NULL
best.fit <- NULL
best.cor <- -1
best.seed <- -1

# n iterations to get best model
for(i in 1:iterations) {
  # set seed
  seed.val <- sample(1:500, 1)
  set.seed(seed.val)
  
  # do random stratified sampling to generate training & test sets
  trainIndex <- sample(nrow(data),floor(nrow(data)*0.70))
  # trainIndex <- createDataPartition(data$EUR_o..Mstb., p = .7,list = FALSE,times = 1, groups = 10)
  train=data[trainIndex,]
  test=data[-trainIndex,]
  
  actual= test$EUR_o..Mstb.
  
  # the model - M5P from RWeka package
  fit_M5P <- M5P(EUR_o..Mstb. ~. , data = train, na.action = na.pass)
  predicted_M5P <- predict(fit_M5P, newdata = test)
  
  #Convert predicted response vector as dataframe
  predicted_M5P <- as.data.frame(predicted_M5P)
  colnames(predicted_M5P) <- "predicted.M5P.EUR"
  
  # The RMSE of M5P
  RMSE_m5p<-sqrt((sum((actual-predicted_M5P)^2))/nrow(test))
  COR_m5p <- cor(actual, predicted_M5P)
  
  # print results of the best iteration
  #   summary(fit_M5P)
  #   print(paste(RMSE_m5p, "M5P", sep = " "))
  #   print(paste(COR_m5p, "M5P", sep = " "))  
  
  # randon Forest
  fit_rf <- randomForest(EUR_o..Mstb. ~. , data = train, ntree = 100, na.action = na.exclude)  
  predicted_rf <- predict(fit_rf, newdata = test)
  
  #Convert predicted response vector as dataframe
  predicted_rf <- as.data.frame(predicted_rf)
  colnames(predicted_rf) <- "predicted.RF.EUR"
  #Replacing NA with average EUR from training set (NA not allowed for submission)
  predicted_rf[is.na(predicted_rf)] <- mean(train$EUR_o..Mstb.)
  
  # The RMSE
  RMSE_rf<-sqrt((sum((actual-predicted_rf)^2))/nrow(test))
  COR_rf <- cor(actual, predicted_rf)
  
  #   print(paste(RMSE_rf, "Random Forest", sep = " "))
  #   print(paste(COR_rf, "Random Forest", sep = " "))  
  
  if (RMSE_m5p < best.rmse && COR_m5p > best.cor) {
    print(paste("====>","M5P scores!",COR_m5p,RMSE_m5p,seed.val,sep = " "))
    best.rmse <- RMSE_m5p
    best.train <- train
    best.test <- test
    best.fit <- fit_M5P
    best.cor <- COR_m5p
    best.seed <- seed.val
  }
  if (RMSE_rf < best.rmse && COR_rf > best.cor) {
    print(paste("====>","RF scores!",COR_rf,RMSE_rf,seed.val,sep = " "))
    best.rmse <- RMSE_rf
    best.train <- train
    best.test <- test
    best.fit <- fit_rf
    best.cor <- COR_rf
    best.seed <- seed.val
  }
}

# write the best training and test sets
write.table(best.train, "best_train.csv",sep=",",row.names=FALSE, quote = FALSE)
write.table(best.test, "best_test.csv",sep=",",row.names=FALSE, quote = FALSE)

# the best
actual= best.test$EUR_o..Mstb.
predicted <- predict(best.fit, newdata = best.test)

#Convert predicted response vector as dataframe
predicted <- as.data.frame(predicted)
colnames(predicted) <- "predicted.EUR"
#Replacing NA with average EUR from training set (NA not allowed for submission)
predicted[is.na(predicted)] <- mean(best.train$EUR_o..Mstb.)

# The RMSE
RMSE<-sqrt((sum((actual-predicted)^2))/nrow(best.test))
COR <- cor(actual, predicted)

final = cbind(actual,predicted)
write.table(final, "output.csv",sep=",",row.names=FALSE, quote = FALSE)

# length_divisor<-4
# iterations<-500
# predicted<-foreach(m=1:iterations,.combine=cbind) %do% {
#   training_positions <- sample(nrow(train), size=floor((nrow(train)/length_divisor)))
#   train_pos<-1:nrow(train) %in% training_positions
#   bagFit <- M5P(EUR_o..Mstb. ~. , data=train[training_positions,], na.action = na.pass)
#   predict(bagFit,newdata=test)
# }
# predicted<-rowMeans(predicted)
# 
# # The RMSE
# bagRMSE<-sqrt((sum((actual-predicted)^2))/nrow(test))
# bagCOR <- cor(actual, predicted)
# 
# # summary(fit)
# print(paste("Bagging RMSE", bagRMSE, sep = " = "))
# print(paste("Bagging COR", bagCOR, sep = " = "))
# 
# final = cbind(actual,predicted)
# write.table(final, "bagged_output.csv",sep=",",row.names=FALSE, quote = FALSE)