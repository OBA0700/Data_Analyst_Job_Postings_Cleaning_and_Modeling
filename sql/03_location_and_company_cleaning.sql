/*
===============================================================================
STAGE 4 — LOCATION VALUE CONSISTENCY
===============================================================================
*/


/*
4.1 — Inspect Location Values and Their Frequency

The location field is first profiled without initially assuming the 
presence of errors from different representations.
*/

SELECT
    location,
    COUNT(*) AS job_count
FROM unique_raw_job_postings
GROUP BY location
ORDER BY job_count DESC;


/*
OBSERVATION

The field contains several representations such as "Anywhere", "United States", 
and other geographic values.

Different location labels are not automatically data-quality problems. Hence,
rather than forcing them into a new geographic hierarchy without supporting 
evidence, the next query tests for objective string-formatting inconsistencies.
*/


/*
4.2 — Diagnose Location Formatting

CASE classifies the location values into several potential formatting conditions.
*/

SELECT
    CASE
        WHEN location IS NULL THEN 'NULL'
        WHEN location = '' THEN 'Empty string'
        WHEN TRIM(location) = '' THEN 'Whitespace only'
        WHEN location <> TRIM(location) THEN 'Leading/trailing whitespace'
        ELSE 'No formatting issue'
    END AS location_issue,
    COUNT(*) AS job_count
FROM unique_raw_job_postings
GROUP BY location_issue
ORDER BY job_count DESC;


/*
RESULT

    Rows with leading/trailing whitespace:    36,571
    NULL location values:                         37

WHY THIS MATTERS

Leading or trailing whitespace can cause visually identical locations to
behave as different strings during grouping, filtering, joins, and distinct
counts.

The 37 NULL values is treated as a different situation because some job positngs
can genuinely contain no specified location value. 

DECISION

The confirmed whitespace inconsistency will be corrected.

The genuine NULL values will be preserved rather than replaced with invented
location information.
*/


/*
4.3 — Remove Leading and Trailing Location Whitespace

TECHNICAL NOTE — TRIM

TRIM() removes unwanted characters from the beginning and end of a string.
Here, it corrects confirmed formatting inconsistencies without altering the
meaning or geographic granularity of the location value.
*/

UPDATE unique_raw_job_postings
SET location = TRIM(location)
WHERE location <> TRIM(location);


/*
4.4 — Validate the Location Cleaning
*/

SELECT
    COUNT(*) AS whitespace_remaining
FROM unique_raw_job_postings
WHERE location <> TRIM(location);


/*
RESULT

    whitespace_remaining = 0

All identified leading/trailing location whitespace has been removed, while
the 37 genuinely missing locations remain preserved as NULL.
*/


/*
===============================================================================
STAGE 5 — COMPANY-NAME CONSISTENCY
===============================================================================
*/


/*
5.1 — Check Company Names for Whitespace
*/

SELECT
    COUNT(*) AS whitespace_error_count
FROM unique_raw_job_postings
WHERE company_name <> TRIM(company_name);


/*
RESULT

No company-name whitespace inconsistencies were detected.
*/


/*
5.2 — Check for Missing Company Names
*/

SELECT
    COUNT(*) AS missing_company_name
FROM unique_raw_job_postings
WHERE company_name IS NULL
   OR company_name = '';


/*
RESULT

No NULL or empty company names were detected.

Since basic completeness and whitespace are not found, the investigation
moves to whether equivalent companies are represented under different letter
cases.
*/


/*
5.3 — Inspect Companies Appearing Across Multiple Job Records

Repeated company names are expected because one employer may post more that one 
jobs.
This query helps to establish the repeated-company pattern before testing for 
naming variations.
*/

SELECT
    company_name,
    COUNT(*) AS job_count
FROM unique_raw_job_postings
GROUP BY company_name
HAVING COUNT(*) > 1
ORDER BY job_count DESC;


/*
OBSERVATION

Multiple companies appear across many job records. Upwork, for example,
appears in 7,533 records.

The important question is not whether a company appears repeatedly, but whether
the same company is being split into multiple similar entities because of
letter-case differences.
*/


/*
5.4 — Detect Case-Based Company-Name Variations

LOWER() creates a common comparison form while COUNT(DISTINCT company_name)
measures how many original representations occur for that normalized value.
*/

SELECT
    LOWER(company_name) AS company_name_normalized,
    COUNT(DISTINCT company_name) AS name_variations
FROM unique_raw_job_postings
GROUP BY company_name_normalized
HAVING COUNT(DISTINCT company_name) > 1
ORDER BY name_variations DESC;


/*
The result confirms that some equivalent company names differ only by
capitalization.

The next query displays the different representation versions directly.
*/


/*
5.5 — Inspect the Actual Case Variations

TECHNICAL NOTE — STRING_AGG

STRING_AGG() combines values from multiple rows into one readable string.

Here it is used diagnostically to display the different representations of an
otherwise equivalent company name side by side before any update is made.
*/

SELECT
    LOWER(company_name) AS normalized_name,
    STRING_AGG(
        DISTINCT company_name,
        ' | ' ORDER BY company_name
    ) AS variations
FROM unique_raw_job_postings
GROUP BY LOWER(company_name)
HAVING COUNT(DISTINCT company_name) > 1
ORDER BY normalized_name;


/*
DECISION

Because the identified variations are case-based, company names are normalized
to lowercase before they are extracted into a dedicated company reference
table.
*/


/*
5.6 — Standardize Company Names
*/

UPDATE unique_raw_job_postings
SET company_name = LOWER(company_name);


/*
5.7 — Validate Company-Name Standardization
*/

SELECT
    LOWER(company_name) AS normalized_name,
    COUNT(DISTINCT company_name) AS variations
FROM unique_raw_job_postings
GROUP BY LOWER(company_name)
HAVING COUNT(DISTINCT company_name) > 1;


/*
RESULT

The validation returns no case-based company-name variations.

WHY THIS MATTERS

Standardizing case prevents the same employer from being represented as
multiple company entities merely because capitalization differs.

The dataset now contains unique jobs, standardized analytical types, cleaned
location formatting, and consistent company-name casing.

The next major quality issue concerns the availability and consistency of
job-skill information.
*/