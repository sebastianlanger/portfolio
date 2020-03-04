USE bixit;

SET sql_mode = 'ONLY_FULL_GROUP_BY';


/* 
	***********PERFORMANCE IMPROVEMENTS 1 **********
	*******IMPORTANT: EXECUTE THIS CODE FIRST******** 
    **************************(BEGIN HERE)**********************
 */

-- This improves the performance of the queries over start_station_code
-- in my case from 6,5 minutes without the index to 4.5
ALTER TABLE `bixit`.`trips` 
ADD INDEX `idx_start_station_cod` USING BTREE (`start_station_code` ASC);

-- the same for is_member
ALTER TABLE `bixit`.`trips` 
ADD INDEX `idx_member` USING BTREE (`is_member` ASC);

-- This codes creates the necesary view

DROP VIEW IF EXISTS trips_v;

CREATE VIEW trips_v AS
    SELECT 
		id,
		start_date,
		YEAR(start_date) AS trip_year,
		MONTH(start_date) AS trip_month,
		DAY(start_date) AS trip_day,
		CASE DAYOFWEEK(start_date)        
			WHEN 1 THEN 'Sunday'
			WHEN 2 THEN 'Monday'
			WHEN 3 THEN 'Tuesday'
			WHEN 4 THEN 'Wednesday'
			WHEN 5 THEN 'Thursday'
			WHEN 6 THEN 'Friday'
			ELSE 'Saturday'
		END AS trip_day_name,
		CASE
			WHEN HOUR(start_date) BETWEEN 7 AND 11 THEN 'morning'
			WHEN HOUR(start_date) BETWEEN 12 AND 16 THEN 'afternoon'
			WHEN HOUR(start_date) BETWEEN 17 AND 21 THEN 'evening'
			ELSE 'night'
		END AS time_of_day,
		start_station_code,
		end_date,
		end_station_code,
		IF(start_station_code = end_station_code,
			1,
			0) round_trip,
		duration_sec,
		is_member,
		IF(is_member, 'Members', 'Non Members') AS membership_status
	FROM
		trips; 

 
 -- Creation of a table with sumarized data to deal with the queries in a faster way
 
 DROP TEMPORARY TABLE IF EXISTS trips_summary;
 
  CREATE TEMPORARY TABLE trips_summary (
  trip_year INT(11) UNSIGNED NOT NULL, -- I know, this integer values should be tinyint but if I do that I get a misterious out of range error
  trip_month  INT(11) UNSIGNED NOT NULL,
  trip_day INT(11) UNSIGNED NOT NULL,
  membership_status VARCHAR(50) NOT NULL, 
  trip_count INT(11) UNSIGNED NOT NULL,
  roundtrip_sum INT(11) UNSIGNED NOT NULL,
  non_roundtrip_sum INT(11) UNSIGNED  NULL,
  duration_sec_sum INT(11) UNSIGNED  NULL
) ENGINE=INNODB AUTO_INCREMENT=8584167 DEFAULT CHARSET=UTF8MB4 COLLATE=UTF8MB4_0900_AI_CI;


INSERT INTO trips_summary
 SELECT 
    trip_year,
    trip_month,
    trip_day,
    IF(is_member, 'Members', 'Non Members') AS membership_status,
    COUNT(*) AS trip_count,
    SUM(roundrip) AS roundtrip_sum,
    (COUNT(*) - SUM(roundrip)) AS non_roundtrip_sum,
    SUM(duration_sec) AS duration_sec_sum
FROM
    trips_v
GROUP BY trip_year , trip_month , trip_day , membership_status
ORDER BY trip_year , trip_month , trip_day , membership_status DESC;


/* 
	***********PERFORMANCE IMPROVEMENTS 1 **********
    **************************(END HERE)**********************
    
    Thank you! :)
 
 */

 
#########################
# 1. Usage Volume Overview #
#########################

-- 1.1. First, we will attempt to gain an overall view of the volume of usage 
-- of Bixi Bikes and what factors influence it. To do so calculate:

-- 1.1.1. The total number of trips for the years of 2016.
-- ANSWER: The number of trips in 2016 was 3917401

SELECT 
    SUM(trip_count) AS count_trips 
FROM
    trips_summary
WHERE
    trip_year = 2016;

-- 1.1.2. The total number of trips for the years of 2017.
-- ANSWER: The number of trips in 2017 was 4666765

SELECT 
    SUM(trip_count) AS count_trips 
FROM
    trips_summary
WHERE
    trip_year = 2017;


-- 1.1.3. The total number of trips for the years of 2016 broken-down by month.

SELECT 
    trip_year, trip_month, SUM(trip_count) AS count_trips
FROM
    trips_summary
WHERE
    trip_year = 2016
GROUP BY trip_year , trip_month
ORDER BY trip_month ASC;

-- 1.1.4. The total number of trips for the years of 2017 broken-down by month .

SELECT 
    trip_year, trip_month, SUM(trip_count) AS count_trips
FROM
    trips_summary
WHERE
    trip_year = 2017
GROUP BY trip_year , trip_month
ORDER BY trip_month ASC;

-- 1.1.5. The average number of trips a day for each year-month combination in the dataset.
-- TECHNICAL NOTE: If this query would be performed to the view the necesary inner join with the 
-- same query would take too much time. That's why I decided to handle it with 
--  a summarized temporary table that contains only 860 rows instead of 8M+ of the original table.
-- As temporary tables in this engine are not able to be used in an inner join agains themselves 
-- I decided to clone it to perform the nested query.alter



-- To perform with nested queries we need to use another temporary table with the exact content because 
-- because the engine does not support this operations in temporary tables. 
-- Don't worry, it's only 860 rows and I will drop it later

DROP TEMPORARY TABLE IF EXISTS trips_summary2;
CREATE TEMPORARY TABLE trips_summary2 LIKE trips_summary;
 
INSERT trips_summary2 
	SELECT * FROM trips_summary;


SELECT 
    ts.trip_year,
    ts.trip_month,
    AVG(tsd.trip_count) AS avg_trips_perday
FROM
    trips_summary ts
        INNER JOIN
			(SELECT 
					trip_year,
					trip_month,
					trip_day,
					SUM(trip_count) AS trip_count
			FROM
				trips_summary2 
			GROUP BY trip_year , trip_month, trip_day
			ORDER BY trip_year , trip_month,trip_day ASC) AS tsd ON ts.trip_year = tsd.trip_year
		AND ts.trip_month = tsd.trip_month
GROUP BY ts.trip_year , ts.trip_month
ORDER BY ts.trip_year , ts.trip_month ASC;

-- 1.2
-- Unsurprisingly, the number of trips varies greatly throughout the year. 
-- How about membership status? Should we expect member and non-member to behave differently? 
-- To start investigating that, calculate:

-- 1.2.1 The total number of trips in the year 2017 broken-down by membership status (member/non-member).
SELECT 
    trip_year,
    trip_month,
    membership_status,
    SUM(trip_count) AS trip_count
FROM
    trips_summary
WHERE
    trip_year = 2017
GROUP BY trip_year , trip_month , membership_status
ORDER BY trip_year , trip_month ASC;

-- 1.2.2 The fraction of total trips that were done by members for the year of 2017 broken-down by month.

SELECT 
    ts_members.trip_year,
    ts_members.trip_month,
    ts_members.membership_status,
    SUM(ts_members.trip_count) AS trip_count_members,
    ts_all.trip_count_all,
    SUM(ts_members.trip_count) / ts_all.trip_count_all AS fraction_trips_by_members
FROM
    trips_summary AS ts_members
        INNER JOIN
			(SELECT 
				trip_year, trip_month, SUM(trip_count) AS trip_count_all
			FROM
				trips_summary2
			WHERE
				trip_year = 2017
			GROUP BY trip_year , trip_month
			ORDER BY trip_year , trip_month ASC) AS ts_all ON ts_members.trip_year = ts_all.trip_year
        AND ts_members.trip_month = ts_all.trip_month
WHERE
    ts_members.trip_year = 2017
        AND ts_members.membership_status = 'Members'
GROUP BY ts_members.trip_year , ts_members.trip_month , ts_members.membership_status
ORDER BY ts_members.trip_year , ts_members.trip_month ASC;


-- 1.3. Use the above queries to answer the questions:

-- 1.3.1. Which time of the year the demand for Bixi bikes is at its peak?
-- ANSWER: The best 3 months are June, July and August, which is summer in Montreal


SELECT 
    trip_month,
    SUM(trip_count) AS trip_count
FROM
    trips_summary
GROUP BY trip_month 
ORDER BY trip_count DESC
LIMIT 3;



-- 1.3.2. If you were to offer non-members a special promotion in an attempt to convert them to members, when would you do it?
-- ANSWER:
-- I would launch special promotions in the first 2 months 
-- and the last 2 months of the bicking season after and before the snow
-- That would be April and May and October and November.
-- Those are the lowest months  in terms of trips and it's probably a good idea 
-- to incentivate people to use the service lowing the prices.
-- I would like to know what happens with the bikes during the December, January and February and March.
-- My advice should be to explore the possibility of offer the service in warmer cities at the best price of the market 
-- which is better than do anyithing with them during that time.

#####################
# 2. Trip Characteristics #
####################
-- Given what we just learned about trip volume it seems the usage pattern of Bixi bikes 
-- in warmer and colder months is quite different. Let's take a closer look at the characteristics 
-- of trips and see what else we can uncover.

-- 2.1. Calculate the average trip time across the entire dataset.

-- ANSWER: The average trip duration is 13.7 minutes or 824 seconds

SELECT 
    ROUND(AVG(duration_sec)) as avg_trip_time_sec,
    ROUND(AVG(duration_sec)/60,2) AS avg_trip_time_mins
FROM
    trips_v;
    

    
-- 2.2. Let's dig a bit deeper and slice the average trip time across a couple of interesting dimensions. 
-- 		Calculate the average trip time broken-down by:
-- 2.2.1	Membership status
-- OBSERVATION: Non Members make longest trips (20.35 min avg) than Members (12.35 min avg) 

SELECT 
	membership_status,
    ROUND(AVG(duration_sec)) as avg_trip_time_sec,
    ROUND(AVG(duration_sec)/60,2) AS avg_trip_time_mins
FROM
    trips_v
GROUP BY membership_status;


-- 2.2.2. Month
SELECT 
	trip_month,
    ROUND(AVG(duration_sec)) as avg_trip_time_sec,
    ROUND(AVG(duration_sec)/60,2) AS avg_trip_time_mins
FROM
    trips_v
GROUP BY trip_month
ORDER BY avg_trip_time_sec DESC;

-- 2.2.3 Day of the week
SELECT 
	trip_day_name,
    ROUND(AVG(duration_sec)) as avg_trip_time_sec,
    ROUND(AVG(duration_sec)/60,2) AS avg_trip_time_mins
FROM
    trips_v
GROUP BY trip_day_name
ORDER BY avg_trip_time_sec DESC;

-- OBSERVATION: The months with average longest trips are in 
-- the following order July(14.6 min), August(14.2 min), June (14 min)

/* 
	**********************PERFORMANCE IMPROVEMENTS 2 *************************
    *******IMPORTANT: BEFORE CONTINUE EXECUTE THIS CODE FIRST******** 
    ***********************************(BEGIN HERE)***************************************
 */

DROP TEMPORARY TABLE IF EXISTS stations_summary;

 CREATE TEMPORARY TABLE stations_summary (
  station_code INT(11) UNSIGNED NOT NULL,
  station_name VARCHAR(255)  NULL, 
  membership_status VARCHAR(50)  NULL, 
  start_trip_count INT(11) UNSIGNED  NULL,
  start_duration_sec_sum INT(11) UNSIGNED  NULL,
  start_duration_sec_avg FLOAT NULL,
  end_trip_count INT(11) UNSIGNED  NULL,
  end_duration_sec_sum INT(11) UNSIGNED  NULL,
  end_duration_sec_avg FLOAT NULL,  
  roundtrip_sum INT(11) UNSIGNED NOT NULL,
  non_roundtrip_sum INT(11) UNSIGNED  NULL
) ENGINE=INNODB AUTO_INCREMENT=8584167 DEFAULT CHARSET=UTF8MB4 COLLATE=UTF8MB4_0900_AI_CI;


-- Adding the information required to operate with start stations
INSERT INTO stations_summary
 SELECT 
    start_station_code,
    NULL,
    IF(is_member, 'Members', 'Non Members') AS membership_status,
    COUNT(*) AS start_trip_count,
    SUM(duration_sec) AS start_duration_sec_sum,
    ROUND(AVG(duration_sec),2) AS start_duration_sec_avg,
    NULL,
    NULL,
    NULL,
    SUM(roundrip) AS roundtrip_sum,
    (COUNT(*) - SUM(roundrip)) AS non_roundtrip_sum
FROM
    trips_v
GROUP BY start_station_code , membership_status
ORDER BY start_trip_count DESC;

-- Adding the information required to operate with END stations
UPDATE stations_summary INNER JOIN
	( SELECT 
		end_station_code,    
		IF(is_member, 'Members', 'Non Members') AS end_membership_status,
		COUNT(*) AS end_trip_count,
		SUM(duration_sec) AS end_duration_sec_sum,
		ROUND(AVG(duration_sec),2) AS end_duration_sec_avg
	FROM
		trips_v
	GROUP BY end_station_code , end_membership_status
	ORDER BY end_trip_count DESC) AS end_stations 
		ON stations_summary.station_code = end_stations.end_station_code AND
				stations_summary.membership_status = end_stations.end_membership_status
SET
	stations_summary.end_trip_count = end_stations.end_trip_count,
	stations_summary.end_duration_sec_sum = end_stations.end_duration_sec_sum,
	stations_summary.end_duration_sec_avg = end_stations.end_duration_sec_avg;

-- Update the names of the stations acording to their id
UPDATE stations_summary AS ss
        INNER JOIN
    stations s ON ss.station_code = s.code 
SET 
    ss.station_name = s.name;


/* 
	**********************PERFORMANCE IMPROVEMENTS 2 *************************
    ***********************************(END HERE)*****************************************
    
    Thank you! :)
    
 */

-- 2.2.4. Station name

-- TECHNINCAL OBSERVATION: I'm geting the average trips for the station in the case 
-- that the station was start station and also in the case it was the end station, all in the same row
-- As the members and non members are separated in rows for each station we need to add 
-- the numbers to get the rigth result

SELECT 
    station_name,
    (SUM(start_duration_sec_sum) / SUM(start_trip_count)) AS start_duration_sec_avg,
    ROUND((SUM(start_duration_sec_sum) / SUM(start_trip_count)) / 60,
            2) AS start_duration_min_avg,
    (SUM(end_duration_sec_sum) / SUM(end_trip_count)) AS end_duration_sec_avg,
    ROUND((SUM(end_duration_sec_sum) / SUM(end_trip_count)) / 60,
            2) AS end_duration_min_avg
FROM
    stations_summary
GROUP BY station_name;

-- 2.2.4,1. Which station has the longest trips on average?
-- ANSWER PART 1: The START station with the longest trips on average is Métro Jean-Drapeau (code 6501)
-- with 1899.16 seconds or 31.65 minutes.

SELECT 
    t.start_station_code,
    s.name as station_name,
    ROUND(SUM(duration_sec) / count(*)) AS start_duration_sec_avg,
    ROUND((SUM(duration_sec) / count(*)) / 60, 2) AS start_duration_min_avg
FROM
    trips_v  as t inner join stations as s on t.start_station_code = s.code
GROUP BY t.start_station_code , s.name
ORDER BY start_duration_sec_avg DESC
LIMIT 1;

-- ANSWER PART 2: The END station with the longest trips on average is ALSO Métro Jean-Drapeau (code 6501)
-- with 1941 seconds or 32.35 minutes.

SELECT 
    t.end_station_code,
    s.name as station_name,
    ROUND(SUM(duration_sec) / count(*)) AS end_duration_sec_avg,
    ROUND((SUM(duration_sec) / count(*)) / 60, 2) AS end_duration_min_avg
FROM
    trips_v  as t inner join stations as s on t.end_station_code = s.code
GROUP BY t.end_station_code , s.name
ORDER BY end_duration_sec_avg DESC
LIMIT 1;



-- 2.2.4.2. Which station has the shortest trips on average?
-- ANSWER PART 1: The  START station with the shortest trips on average is Métro Georges-Vanier (St-Antoine / Canning) (code 6408)
-- with average rides of 499 seconds or 8.31 minutes.
SELECT 
    t.start_station_code,
    s.name as station_name,
    ROUND(SUM(duration_sec) / count(*)) AS start_duration_sec_avg,
    ROUND((SUM(duration_sec) / count(*)) / 60, 2) AS start_duration_min_avg
FROM
    trips_v  as t inner join stations as s on t.start_station_code = s.code
GROUP BY t.start_station_code , s.name
ORDER BY start_duration_sec_avg ASC
LIMIT 1;


-- ANSWER PART 2: The  END station with the shortest trips on average is ALSO Métro Georges-Vanier (St-Antoine / Canning) (code 6408)
-- with average rides of 544 seconds or 9.06 minutes.
SELECT 
    t.end_station_code,
    s.name as station_name,
    ROUND(SUM(duration_sec) / count(*)) AS end_duration_sec_avg,
    ROUND((SUM(duration_sec) / count(*)) / 60, 2) AS end_duration_min_avg
FROM
    trips_v  as t inner join stations as s on t.end_station_code = s.code
GROUP BY t.end_station_code , s.name
ORDER BY end_duration_sec_avg ASC
LIMIT 1;


-- 2.2.4.3. Extremely long / short trips can skew your results. How would avoid that?
-- PLEASE SEE THE WORD DOCUMENT. Thanks

SELECT 
    FLOOR(ROUND(duration_sec / 60)) AS duration_mins,
    COUNT(*) trips_count
FROM
    trips_v
GROUP BY duration_mins
ORDER BY duration_mins ASC;


-- 2.3. Let's call trips that start and end in the same station "round trips". Calculate the fraction of trips 
-- that were round trips and break it down by:

-- 2.3.1Membership status
-- OBSERVATION: Non members seems to make roundtrips more often than Members, 
-- in fraction should be 0,0488 for non members and 0.014 from Members
-- Nevertheless, the numbers of trips made by the members it's significantly higer than not members  
-- in quantity  with 6959342 for members and 1624824 for non members.


SELECT 
    membership_status,
    COUNT(*) AS trip_count,
    SUM(round_trip) roundtrip_sum,
    SUM(round_trip) / COUNT(*) AS round_trip_fraction
FROM
    trips_v
GROUP BY membership_status;

-- 2.3.2.Day of the week
-- OBSERVATION: Sundays and Saturdays seems to be the days with more roundtrips. 
SELECT 
    trip_day_name,
    count(*) AS trip_count_sum,
    SUM(round_trip) / count(*) AS round_trip_fraction
FROM
    trips_v
GROUP BY trip_day_name 
order by round_trip_fraction desc;

-- 2.4.Discuss the differences you observed and come up with possible explanations.

#################
#3. Popular Stations#
#################

-- It is clear now that average temperature, weekends and membership status 
-- are intertwined and influence greatly how people use Bixi bikes. Let's try to bring this 
-- knowledge with us and learn something about station popularity.
-- 
-- 3.1. What are the names of the 5 most popular starting stations?

SELECT 
    t.start_station_code,
    s.name as start_station_name,
    count(*) AS trip_count
FROM
    trips_v  as t INNER JOIN stations as s on t.start_station_code = s.code
GROUP BY     t.start_station_code, start_station_name
ORDER BY trip_count DESC
LIMIT 5; 

-- 3.2. What are the names of the 5 most popular ending stations?

SELECT 
    t.end_station_code,
    s.name as end_station_name,
    count(*) AS trip_count
FROM
    trips_v  as t INNER JOIN stations as s on t.end_station_code = s.code
GROUP BY     t.end_station_code, end_station_name
ORDER BY trip_count DESC
LIMIT 5; 


-- 3.3 If we break-up the hours of the day as follows (time of the day):
-- 3.3.1 How is the number of starts and ends distributed for the station Mackay / de Maisonneuve throughout the day?


SELECT 
    start_station.time_of_day,
    start_station.trip_count_start_station,
    start_station.trip_count_start_station / 
		(start_station.trip_count_start_station+end_station.trip_count_end_station) as fraction_as_start,
    end_station.trip_count_end_station,
    end_station.trip_count_end_station / 
		(start_station.trip_count_start_station+end_station.trip_count_end_station) as fraction_as_end
FROM
    (SELECT 
        time_of_day, COUNT(*) AS trip_count_start_station
    FROM
        trips_v
    WHERE
        start_station_code = 6100
    GROUP BY time_of_day
    ORDER BY time_of_day DESC) AS start_station
        LEFT JOIN
    (SELECT 
        time_of_day, COUNT(*) AS trip_count_end_station
    FROM
        trips_v
    WHERE
        end_station_code = 6100
    GROUP BY time_of_day
    ORDER BY time_of_day DESC) AS end_station ON start_station.time_of_day = end_station.time_of_day
ORDER BY trip_count_start_station DESC;



-- 3.3.2. Explain the differences you see and discuss why the numbers are the way they are.
-- ANSWER: 
-- This station is a place where the people arrive mostly in the morning, maybe to go to work. 
-- In the evening and at night this station is more popular as a place of departure, maybe when people are coming back home from their activities. 
-- In the afternoon this place has a similar fraction of people using it both as a place of departure and arrival.

-- 3.4. (A) Which station has proportionally the least number of member trips? 
-- (B) How about the most? To damper variance, consider only stations for which there were at least
-- 10 trips starting and ending from it.

-- ANSWER (A) PART 1: START station with less trips of members 
-- 7075, CHSLD Éloria-Lepage (de la Pépinière / de Marseille) with 379

SELECT 
    station_code,
    station_name,
    start_trip_count as trips_made_by_members
FROM
    stations_summary
WHERE
    membership_status = 'Members'
        AND roundtrip_sum >= 10
ORDER BY trips_made_by_members ASC
LIMIT 1;
        


-- ANSWER (A) PART 2: END station with less trips of members 
-- '7009','CHSLD Benjamin-Victor-Rousselot (Dickson / Sherbrooke)','558'

SELECT 
    station_code,    
    station_name,
    end_trip_count as trips_made_by_members
FROM
    stations_summary
WHERE
    membership_status = 'Members'
        AND roundtrip_sum >= 10
ORDER BY trips_made_by_members ASC
LIMIT 1;


-- ANSWER (B) PART 1: START station with more trips of members 
-- '6100','Mackay / de Maisonneuve','80538'

SELECT 
    station_code,
    station_name,
    start_trip_count as trips_made_by_members
FROM
    stations_summary
WHERE
    membership_status = 'Members'
        AND roundtrip_sum >= 10
ORDER BY trips_made_by_members DESC
LIMIT 1;

-- ANSWER (B) PART 2: END station with more trips of members 
-- '6015','Berri / de Maisonneuve','83453'


SELECT 
    station_code,    
    station_name,
    end_trip_count as trips_made_by_members
FROM
    stations_summary
WHERE
    membership_status = 'Members'
        AND roundtrip_sum >= 10
ORDER BY trips_made_by_members DESC
LIMIT 1;



-- 3.5. List all stations for which at least 10% of trips are round trips. Recall round trips are 
-- those that start and end in the same station. This time we will only consider stations with at least 50 starting trips.

-- 3.5.1. First, write a query that counts the number of starting trips per station.


SELECT 
    station_code, station_name, SUM(start_trip_count) AS start_trip_count
FROM
    stations_summary
GROUP BY station_code , station_name;

-- 3.5.2. Second, write a query that counts, for each station, the number of round trips.

SELECT 
    station_code, station_name, SUM(roundtrip_sum) as round_trip_count
FROM
    stations_summary
GROUP BY station_code , station_name;

-- 3.5.3. Combine the above queries and calculate the fraction of round trips to the 
-- total number of starting trips for each station.

SELECT 
    station_code, station_name,
	SUM(start_trip_count) AS start_trip_count,
    SUM(roundtrip_sum) as round_trip_count,
    SUM(roundtrip_sum) / SUM(start_trip_count) as round_trip_fraction
FROM
    stations_summary
GROUP BY station_code , station_name;


-- 3.5.4. Filter down to stations with at least 50 trips originating from them.


DROP TEMPORARY TABLE IF EXISTS stations_summary2;
CREATE TEMPORARY TABLE stations_summary2 LIKE stations_summary;
 
INSERT stations_summary2 
	SELECT * FROM stations_summary;


SELECT 
    stations_summary.station_code,
    station_name,
    SUM(stations_summary.start_trip_count) AS start_trip_count,
    sations_round_trips.round_trip_count AS round_trip_count,
    sations_round_trips.round_trip_count / SUM(stations_summary.start_trip_count) AS round_trip_fraction
FROM
    stations_summary
        INNER JOIN
    (SELECT 
        station_code, 
			SUM(roundtrip_sum) AS round_trip_count,
            SUM(roundtrip_sum) / SUM(start_trip_count) as round_trip_fraction
    FROM
        stations_summary2
    GROUP BY station_code) sations_round_trips ON sations_round_trips.station_code = stations_summary.station_code
WHERE
    sations_round_trips.round_trip_count >= 50 AND
    sations_round_trips.round_trip_fraction >= 0.1
GROUP BY stations_summary.station_code , stations_summary.station_name
ORDER BY sations_round_trips.round_trip_fraction DESC;

-- 3.5.5. Given what we learned above about the relation between round trips, membership status, 
-- and day of the week, where would you expect to find stations with a high fraction of round trips?

-- ANSWER FOR NON MEMBERS:
-- If we take the 4 most relevant
-- 6026, de la Commune / Place Jacques-Cartier on Saturday with 8185 and Sunday with 7745
-- 6036, de la Commune / St-Sulpice on Saturday with 6429 and Sunday with 6176

SELECT 
    trips_v.start_station_code,
    relevant_stations.station_name,
    trips_v.trip_day_name,
    trips_v.membership_status,
    count(*) as trips_count_relevant_station
FROM
    trips_v
        INNER JOIN
    (SELECT 
        stations_summary.station_code,
            stations_summary.station_name,
            stations_summary.membership_status,
            stations_summary.start_trip_count AS start_trip_count,
            sations_round_trips.round_trip_count AS round_trip_count,
            sations_round_trips.round_trip_fraction
    FROM
        stations_summary
    INNER JOIN (SELECT 
        station_code,
            membership_status,
            roundtrip_sum AS round_trip_count,
            roundtrip_sum / start_trip_count AS round_trip_fraction
    FROM
        stations_summary2
    ORDER BY station_code , membership_status) sations_round_trips ON sations_round_trips.station_code = stations_summary.station_code
        AND sations_round_trips.membership_status = stations_summary.membership_status
    WHERE
        sations_round_trips.round_trip_count >= 50
            AND sations_round_trips.round_trip_fraction >= 0.1
    ORDER BY sations_round_trips.round_trip_fraction DESC) relevant_stations ON relevant_stations.station_code = trips_v.start_station_code
        AND relevant_stations.membership_status = trips_v.membership_status
WHERE  trips_v.membership_status = 'Non Members'	
GROUP BY trips_v.start_station_code , relevant_stations.station_name , trips_v.trip_day_name , trips_v.membership_status , relevant_stations.round_trip_fraction
ORDER BY trips_count_relevant_station DESC
LIMIT 4;




-- ANSWER FOR  MEMBERS:
-- If we take the 4 most relevant
-- always  in 6501, Métro Jean-Drapeau in this order of relevance:
-- A - on Sunday with 1849
-- B -on Saturday 1531
-- C- on Friday 848
-- D- on Wednesday 717


SELECT 
    trips_v.start_station_code,
    relevant_stations.station_name,
    trips_v.trip_day_name,
    trips_v.membership_status,
    count(*) as trips_count_relevant_station
FROM
    trips_v
        INNER JOIN
    (SELECT 
        stations_summary.station_code,
            stations_summary.station_name,
            stations_summary.membership_status,
            stations_summary.start_trip_count AS start_trip_count,
            sations_round_trips.round_trip_count AS round_trip_count,
            sations_round_trips.round_trip_fraction
    FROM
        stations_summary
    INNER JOIN (SELECT 
        station_code,
            membership_status,
            roundtrip_sum AS round_trip_count,
            roundtrip_sum / start_trip_count AS round_trip_fraction
    FROM
        stations_summary2
    ORDER BY station_code , membership_status) sations_round_trips ON sations_round_trips.station_code = stations_summary.station_code
        AND sations_round_trips.membership_status = stations_summary.membership_status
    WHERE
        sations_round_trips.round_trip_count >= 50
            AND sations_round_trips.round_trip_fraction >= 0.1
    ORDER BY sations_round_trips.round_trip_fraction DESC) relevant_stations ON relevant_stations.station_code = trips_v.start_station_code
        AND relevant_stations.membership_status = trips_v.membership_status
WHERE  trips_v.membership_status = 'Members'	
GROUP BY trips_v.start_station_code , relevant_stations.station_name , trips_v.trip_day_name , trips_v.membership_status , relevant_stations.round_trip_fraction
ORDER BY trips_count_relevant_station DESC
LIMIT 4;


    