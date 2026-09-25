/*
===============================================================================
STAGE 6 — SKILL INFORMATION ASSESSMENT
===============================================================================
*/


/*
6.1 — Measure Jobs With and Without Supplied Skill Tokens

From early observation, "description_tokens" contains the skill information allocated
for jobs, while some records without supplied tokens use the textual empty-list
representation:

    []

The first task is to measure the scale of that missing-token population.

TECHNICAL NOTE — FILTER

PostgreSQL's FILTER clause allows conditional aggregate counts to be measured
against the same population within one query.
*/

SELECT
    COUNT(*) AS total_jobs,

    COUNT(*) FILTER (
        WHERE description_tokens <> '[]'
    ) AS jobs_with_tokens,

    COUNT(*) FILTER (
        WHERE description_tokens = '[]'
    ) AS jobs_without_token

FROM unique_raw_job_postings;


/*
RESULT

    Total jobs:                   58,775
    Jobs without skill tokens:    12,812

WHY THIS MATTERS

Leaving the missing tokens untouched is possible, but each job also contains a
full description.

Before settliing for all 12,812 missing-token records as unrecoverable, the project
tests whether some absent skills can be reconstructed conservatively from the
existing "description" column texts.
*/


/*
6.2 — Confirm Description Availability Where Tokens Are Missing

Skill recovery is only worth investigating if the underlying job descriptions
are actually available.
*/

SELECT
    COUNT(*) FILTER (
        WHERE description_tokens = '[]'
          AND description IS NOT NULL
          AND description <> ''
    ) AS empty_tokens_but_description_available,

    COUNT(*) FILTER (
        WHERE description_tokens = '[]'
          AND (description IS NULL OR description = '')
    ) AS empty_tokens_and_description_missing
FROM unique_raw_job_postings;


/*
RESULT

There are no missing "descriptions" value among the records being investigated for
absent skill tokens.

DECISION

Because the descriptive source text is available, skill recovery can be
explored without introducing information from an external dataset.

However, a central term and a conservative matching method are
required before any records are updated.
*/