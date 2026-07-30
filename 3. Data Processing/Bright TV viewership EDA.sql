-- Databricks notebook source
-------------------------------------------------------------------
-- USER PROFILE TABLE
-------------------------------------------------------------------

-- Preview first 10 rows
SELECT *
FROM bright_tv.default.user_profiles
LIMIT 10;

-- Count total rows and distinct UserIDs
SELECT COUNT(*) AS number_of_rows,
       COUNT(DISTINCT UserID) AS number_subs
FROM bright_tv.default.user_profiles;

-- Check for NULL UserIDs
SELECT COUNT(*) AS null_userids
FROM bright_tv.default.user_profiles
WHERE UserID IS NULL;

-- Find duplicate UserIDs
SELECT UserID,
       COUNT(*) AS duplicate_count
FROM bright_tv.default.user_profiles
GROUP BY UserID
HAVING COUNT(*) > 1;

-- Gender checks
SELECT DISTINCT gender
FROM bright_tv.default.user_profiles;

SELECT COUNT(*) AS blank_gender_count
FROM bright_tv.default.user_profiles
WHERE gender = ' ';

-- Checking subscriber distribution by gender
SELECT COUNT(DISTINCT UserID) AS subs,
       CASE
           WHEN gender = ' ' THEN 'None'
           ELSE gender
       END AS Gender
FROM bright_tv.default.user_profiles
GROUP BY Gender;

-- Race checks
SELECT COUNT(*) AS null_race_count
FROM bright_tv.default.user_profiles
WHERE Race IS NULL;

SELECT DISTINCT Race
FROM bright_tv.default.user_profiles;

-- Standardizing race categories for reporting consistency
SELECT DISTINCT
    CASE
        WHEN Race = 'other' THEN 'None'
        WHEN Race = ' ' THEN 'None'
        ELSE Race
    END AS Race
FROM bright_tv.default.user_profiles;

-- Province checks
SELECT DISTINCT Province
FROM bright_tv.default.user_profiles;

-- Replacing blank and uncategorized provinces
SELECT DISTINCT
    CASE
        WHEN Province = '' THEN 'Uncategorized'
        WHEN Province = 'None' THEN 'Uncategorized'
        ELSE Province
    END AS Region
FROM bright_tv.default.user_profiles;

-- Age checks
SELECT MIN(Age) AS min_age,
       MAX(Age) AS max_age
FROM bright_tv.default.user_profiles;

SELECT COUNT(*) AS null_age_count
FROM bright_tv.default.user_profiles
WHERE Age IS NULL;


-------------------------------------------------------------------
-- VIEWERSHIP TABLE
-------------------------------------------------------------------

-- Preview first 10 rows
SELECT *
FROM bright_tv.default.viewership
LIMIT 10;

-- Count total rows and unified users
SELECT COUNT(*) AS number_of_rows,
       COUNT(COALESCE(UserID0, userid4)) AS subs,
       COUNT(DISTINCT COALESCE(UserID0, userid4)) AS unique_users
FROM bright_tv.default.viewership;

-- Check NULL user IDs
SELECT COUNT(*) AS null_userids
FROM bright_tv.default.viewership
WHERE COALESCE(UserID0, userid4) IS NULL;

-- Distinct channels
SELECT DISTINCT Channel2
FROM bright_tv.default.viewership;

-- Standardizing inconsistent channel naming conventions
SELECT DISTINCT
    CASE
        WHEN Channel2 IN ('SawSee', 'Sawsee') THEN 'SawSee'
        WHEN Channel2 IN ('SuperSport Live Events', 'Live on SuperSport', 'Supersport Live Events', 'DStv Events 1') THEN 'SUpersport Live Events'
        ELSE Channel2
    END AS tv_channel
FROM bright_tv.default.viewership;

WITH base AS(
    -- Creating a unified subscriber identifier across multiple UserID fields
    SELECT COALESCE(UserID0, userid4) AS userid
    FROM bright_tv.default.viewership
),
processing AS (
SELECT 
        COALESCE(UserID0, userid4) AS userid,

        -- Creating date attributes that will support time-based analysis
        TO_CHAR(RecordDate2, 'yyyyMM') AS month_id,
        TO_DATE(RecordDate2) AS watch_date,
        DAY(RecordDate2) AS day_of_week,
        DAYNAME(RecordDate2) AS day_name,
        MONTHNAME(RecordDate2) AS month_name,

        -- Classifying viewing activity as weekday or weekend
        CASE 
            WHEN day_name IN ('Sat','Sun') THEN 'weekend'
            Else 'weekday'
        END AS day_clasification,

        -- Standardizing channel names before analysis
        CASE
            WHEN Channel2 IN ('SawSee', 'Sawsee') THEN 'SawSee'
            WHEN Channel2 IN ('SuperSport Live Events', 'Live on SuperSport', 'Supersport Live Events', 'DStv Events 1') THEN 'SUpersport Live Events'
        ELSE Channel2
        END AS tv_channel,

        -- Extracting watch time attributes for audience viewing patterns
        date_format(RecordDate2, 'HH:mm:ss') AS watch_time,
        HOUR(RecordDate2) AS hour_of_day,

        -- Formatting duration into time format
        date_format(`Duration 2`, 'HH:mm:ss') AS duration

FROM bright_tv.default.viewership
)


-------------------------------------------------------------------
-- VIEWERSHIP DASHBOARD VIEW
-- Creating a dashboard-ready dataset by combining user profile
-- information with audience viewing behaviour
-------------------------------------------------------------------

CREATE OR REPLACE VIEW bright_tv.default.viewership_dashboard AS -- This command creates or updates a virtual table (view) named viewership_dashboard inside the bright_tv.default schema

WITH user_profiles AS ( -- I'm creating a CTE to prepare and clean the user profile dataset

SELECT  UserID,
        
        -- Replacing blank and uncategorized province values
        CASE
            WHEN Province = ' ' THEN 'Uncategorized'        
            WHEN Province = 'None' THEN 'Uncategorized'     
         ELSE Province                                  
        END AS Region,

        -- Creating age bands to improve audience segmentation
        CASE
            WHEN age < 1 THEN 'Infant'
            WHEN age BETWEEN 1 AND 12 THEN 'Child'
            WHEN age BETWEEN 13 AND 17 THEN 'Teen'
            WHEN age BETWEEN 18 AND 34 THEN 'Young Adult'
            WHEN age BETWEEN 35 AND 54 THEN 'Mid Adult'
            WHEN age BETWEEN 55 AND 64 THEN 'Mature Adult'
            WHEN age >= 65 THEN 'Senior'
        END AS age_groups,

        age,

        -- Identifying subscribers with a valid email address
        CASE
            WHEN email IS NOT NULL OR (email <>' ')   OR (email NOT IN ('None')) THEN 1
        ELSE 0
        END AS email_flag,

        -- Identifying subscribers with a social media handle
        CASE
            WHEN `Social Media Handle` IS NOT NULL OR `Social Media Handle` !=' ' OR `Social Media Handle` NOT IN ('None') THEN 1
        ELSE 0
        END AS sm_flag,

        -- Standardizing race values
        CASE
            WHEN Race ilike ('%other%') THEN 'None'   
            WHEN Race=' ' THEN 'None'        
        ELSE Race                        
        END AS Race,

        -- Replacing blank gender values
        CASE
            WHEN gender = ' ' THEN 'None'      
        ELSE gender                       
        END AS Gender

FROM bright_tv.default.user_profiles

),

viewership AS (

SELECT 
        -- Creating a single subscriber key to support joining between datasets
        COALESCE(UserID0, userid4,0) AS userid,

        -- Dates
        TO_DATE(RecordDate2) AS watch_date, -- To extract the date from timestamp in our table
        TO_CHAR(TO_DATE(RecordDate2), 'yyyyMM') AS month_id, --TO_CHAR(): Converts a date into a string and TO_DATE(): Converts a string into a date 
        DAY(RecordDate2) AS day_of_week,
        DAYNAME(TO_DATE(RecordDate2)) AS day_name,
        MONTHNAME(RecordDate2) AS month_name ,

        -- Identifying weekday and weekend consumption patterns
        CASE 
            WHEN day_name IN ('Sat','Sun') THEN 'weekend'
            Else 'weekday'
        END AS day_clasification,

        -- Standardizing channel names to eliminate duplicate categories
        CASE
            WHEN Channel2 IN ('SawSee', 'Sawsee') THEN 'SawSee'
            WHEN Channel2 IN ('SuperSport Live Events', 'Live on SuperSport', 'Supersport Live Events', 'DStv Events 1') THEN 'Supersport Live Events'
        ELSE Channel2
        END AS tv_channel,

        -- Creating hourly viewing attributes
        date_format(RecordDate2, 'HH:mm:ss') AS watch_time,
        HOUR(RecordDate2) AS hour_of_day,

        -- Segmenting audience behaviour by time of day
        CASE
            WHEN watch_time BETWEEN '00:00:00' AND '03:59:59' THEN 'Late Night'
            WHEN watch_time BETWEEN '04:00:00' AND '07:59:59' THEN 'Early Morning'
            WHEN watch_time BETWEEN '08:00:00' AND '11:59:59' THEN 'Morning'
            WHEN watch_time BETWEEN '12:00:00' AND '15:59:59' THEN 'Afternoon'
            WHEN watch_time BETWEEN '16:00:00' AND '19:59:59' THEN 'Evening'
            WHEN watch_time BETWEEN '20:00:00' AND '23:59:59' THEN 'Night'
        END AS time_of_day,

        date_format(`Duration 2`, 'HH:mm:ss') AS duration,

        -- Converting viewing duration into minutes and hours for KPI calculations
        ROUND((HOUR(`Duration 2`) * 60 +
        MINUTE(`Duration 2`) +
        SECOND(`Duration 2`) / 60),2) AS duration_minutes,

        ROUND((HOUR(`Duration 2`)  +
        MINUTE(`Duration 2`) / 60 +
        SECOND(`Duration 2`) / 3600),2) AS duration_hours,

        -- Creating screen time segments to analyse engagement levels
        CASE
            WHEN duration BETWEEN '00:00:01' AND '00:14:59' THEN 'Very Low usage: < 15 min'
            WHEN duration BETWEEN '00:15:00' AND '00:29:59' THEN 'Low usage: < 30 min'
            WHEN duration BETWEEN '00:30:00' AND '00:59:59' THEN 'Moderate usage: < 60 min'
            WHEN duration BETWEEN '01:00:00' AND '01:59:59' THEN 'High usage: < 120 min'
            WHEN duration >= '02:00:00' THEN 'Very High usage: > 120 min'
            ELSE 'No usage'
        END AS screen_time_bucket,

        -- Categorizing viewers based on viewing frequency
        CASE 
            WHEN COUNT(*) OVER (PARTITION BY COALESCE(UserID0, userid4, 0)) = 1 THEN 'One-time users'
            WHEN COUNT(*) OVER (PARTITION BY COALESCE(UserID0, userid4, 0)) BETWEEN 2 AND 5 THEN 'Returning users'
            ELSE 'Loyal users (5+)'
        END AS user_type,

        -- Identifying whether a subscriber has watched content
        CASE 
            WHEN duration = '00:00:00' THEN 'Inactive user'
            ELSE 'Active user'
        END AS user_flag

FROM bright_tv.default.viewership
)

-- Joining demographic and viewership data to create a single dataset for dashboard reporting
SELECT  COALESCE(A.userid, B.userid) AS subs_id,
        user_type,
        month_id,
        watch_date,
        day_of_week,
        day_name,
        day_clasification,
        month_name,
        tv_channel,
        watch_time,
        time_of_day,
        hour_of_day,
        duration,
        duration_minutes,
        duration_hours,
        screen_time_bucket,
        user_flag,
        Region,
        age_groups,
        email_flag,
        sm_flag,
        Race,
        Gender
FROM viewership AS A
LEFT JOIN user_profiles AS B
ON A.userid = B.userid
GROUP BY ALL;

-- Validating the final dashboard view
SELECT *
FROM bright_tv.default.viewership_dashboard;