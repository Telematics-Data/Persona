library(SparkR)
######## Not run: ###### debugs spark 1.6 #####################################
cd /opt/cloudera/parcels/spark-1.6.2-bin-cdh5/bin;./sparkR
sc <- sparkR.init(appName="ClusterPoint2");sqlContext <- sparkRSQL.init(sc);hiveContext <- sparkRHive.init(sc)
CREATE external TABLE ubi_dw_cluster_point_201601 (deviceid String,tid String,vid String,start String,actual_start String,s_end String,dura DOUBLE,period String,lat_st_ori DOUBLE,lon_st_ori DOUBLE,lat_en_ori DOUBLE,lon_en_ori DOUBLE,m_ori DOUBLE,lat_st_def DOUBLE,lon_st_def DOUBLE,lat_en_def DOUBLE,lon_en_def DOUBLE,m_def DOUBLE,speed_mean DOUBLE,gps_speed_sd DOUBLE,gps_acc_sd DOUBLE,dura2 String,sort_st String,sort_en String,stat_date string) ROW format delimited FIELDS TERMINATED BY ',' LOCATION '/user/kettle/ubi/dw/cluster_point/stat_date=201601';
hadoop fs -mkdir /user/kettle/ubi/dm/ubi_dm_cluster_point/stat_date=201601;
/user/kettle/ubi/dm/ubi_dm_cluster_point
randomMatBr <- broadcast(sc, randomMat)
connectBackend.orig <- getFromNamespace('connectBackend', pos='package:SparkR')
connectBackend.patched <- function(hostname, port, timeout = 3600*48) {
   connectBackend.orig(hostname, port, timeout)
}
assignInNamespace("connectBackend", value=connectBackend.patched, pos='package:SparkR')
遗留问题：
1.hive中按天分区是的time.out问题；
2.建表中的 问题。（先将int变为了string）
######## import data #####################################
library(magrittr)
SparkR:::includePackage(sqlContext, 'SoDA')

trip<-sql(hiveContext,"SELECT * , LEAD(actual_start, 1, 0) OVER (PARTITION BY deviceid ORDER BY actual_start) AS start2 FROM trip_stat")
trip<-withColumn(trip, "dura2", trip$start2 - trip$s_end)
trip$start2<-NULL
trip = trip %>% withColumn("sort_st", lit("0")) %>% withColumn("sort_en", lit("0"))
trip_rdd<-SparkR:::toRDD(trip)

######## zip&groupBy with keys #####################################
list_rd<-SparkR:::map(trip_rdd, function(x) {
user<-matrix(unlist(x),floor(length(unlist(x))/25),ncol=25,byrow=T)
user<-user[1,1]
})
stat_rdd<-SparkR:::map(trip_rdd, function(x) {
stat_trip<-matrix(unlist(x),floor(length(unlist(x))/25),ncol=25,byrow=T)
stat_trip
})
rdd<-SparkR:::zipRDD(list_rd,stat_rdd)
parts <- SparkR:::groupByKey(rdd,200L)
SparkR:::cache(parts)

######## main function #####################################
end_rdd<-SparkR:::mapValues(parts, function(x) {
    library('SoDA')
    user_trip<-matrix(unlist(x),floor(length(unlist(x))/25),ncol=25,byrow=T)
    if(dim(user_trip)[1]==1){
      user_trip[1,23]<-0
      user_trip[1,24]<-1
      user_trip[1,25]<-2
    }else{
      ######## Set Initial Parameters #####################################
      user_trip<-user_trip[order(user_trip[,5],decreasing=F),]
      user_trip[,24]<-1:dim(user_trip)[1]
      user_trip[,25]<--(1:dim(user_trip)[1])
      ######## Set Initial Parameters #####################################
      for(i in 1:(dim(user_trip)[1]-1)){
        for(j in (i+1):dim(user_trip)[1]){
                  x<-  geoDist(user_trip[i,9],user_trip[i,10],user_trip[j,9],user_trip[j,10])
                  if(x<1000){
                    user_trip[j,24]<-user_trip[i,24]
                  }else{
                  }              
              }
    }
    ######## Set Initial Parameters #####################################
    for(i in 1:(dim(user_trip)[1]-1)){
      for(j in (i+1):dim(user_trip)[1]){
                x<-  geoDist(user_trip[i,11],user_trip[i,12],user_trip[j,9],user_trip[j,10])
                if(x<1000){
                  user_trip[i,25]<-user_trip[j,24]
                }else{
                }              
            }
  }
    ######## Set Initial Parameters #####################################
    for(i in 1:(dim(user_trip)[1]-1)){
      for(j in (i+1):dim(user_trip)[1]){
                x<-  geoDist(user_trip[i,11],user_trip[i,12],user_trip[j,11],user_trip[j,12])
                if(x<1000 & user_trip[j,25]<0 & user_trip[i,25]>0){
                  user_trip[j,25]<-user_trip[i,25]
                }else{if(x<1000 & user_trip[j,25]<0 & user_trip[i,25]<0){
                  user_trip[i,25]<-1000*abs(user_trip[j,25])
                  user_trip[j,25]<-1000*abs(user_trip[j,25])
                }
                }              
            }
  }
  point<-as.data.frame(base::table(c(user_trip[,24],user_trip[,25])))
  point_table<-point[order(point$Freq,decreasing=T),]
  point_table$Freq<-1:dim(point_table)[1]
  user_trip<-merge(user_trip,point_table,by.x="V24",by.y="Var1",all.x=T)
  user_trip<-user_trip[,-1]
  user_trip<-merge(user_trip,point_table,by.x="V25",by.y="Var1",all.x=T)
  user_trip<-user_trip[,-1]
  user_trip<-as.matrix(user_trip)
  }
  a<-user_trip[,22]
  user_trip[,22]<-user_trip[,23]
  user_trip[,23]<-user_trip[,24]
  user_trip[,24]<-user_trip[,25]
  user_trip[,25]<-a
  user_trip
    })
######## change structure #####################################
end_rdd_rdd <- SparkR:::flatMapValues(end_rdd, function(x) {
    stat_trip <-  matrix(unlist(x),floor(length(unlist(x))/25),ncol=25)
    stat_trip <- split(stat_trip, row(stat_trip))
    stat_trip
})
end_rdd_value<-SparkR:::values(end_rdd_rdd)
SparkR:::cache(end_rdd_value)
SparkR:::saveAsTextFile(end_rdd_value, "/user/kettle/ubi/dm/ubi_dm_cluster_point/stat_date=201601")


######## register dynamic.partitions table #####################################
end_end_rdd<-SparkR:::toDF(end_rdd_value,list('deciveid','tid','vid','start','actual_start','s_end','dura','period','lat_st_ori','lon_st_ori','lat_en_ori','lon_en_ori','m_ori','lat_st_def','lon_st_def','lat_en_def','lon_en_def','m_def','speed_mean','gps_speed_sd','gps_acc_sd','dura2','sort_st','sort_en','stat_date'))
registerTempTable(end_end_rdd,"cluster_point")
sql(hiveContext,"set hive.exec.dynamic.partition.mode=nostrick")
sql(hiveContext,"set hive.exec.dynamic.partition=true")
sql(hiveContext,"set hive.exec.max.dynamic.partitions.pernode = 2000000000")
sql(hiveContext,"set hive.exec.max.dynamic.partitions = 2000000000")
sql(hiveContext,"set hive.exec.max.created.files = 2000000000")
sql(hiveContext,"insert overwrite table ubi_dm_cluster_point partition (stat_date) select * from cluster_point")
