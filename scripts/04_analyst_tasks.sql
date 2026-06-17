-- ============================================================================
-- MODULE 4 : TASKS — Automatisation du résumé quotidien
-- Durée : 15 min
-- Objectif : Montrer la mise en production avec une tâche planifiée
-- ============================================================================

USE DATABASE LAB_RETAIL_AI;
USE WAREHOUSE LAB_WH;

-- ─────────────────────────────────────────────────────────────────────────────
-- 1. Table de reporting où les résumés IA sont stockés chaque jour
-- ─────────────────────────────────────────────────────────────────────────────

CREATE SCHEMA IF NOT EXISTS REPORTING;

CREATE OR REPLACE TABLE REPORTING.DAILY_SUMMARIES (
    GENERATED_AT TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
    SUMMARY_TEXT VARCHAR(5000),
    NB_REVIEWS_ANALYZED INT,
    AVG_RATING FLOAT,
    TOP_ISSUE VARCHAR(500)
);

-- ─────────────────────────────────────────────────────────────────────────────
-- 2. Procédure stockée : génère le résumé IA
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE PROCEDURE REPORTING.GENERATE_DAILY_SUMMARY()
    RETURNS VARCHAR
    LANGUAGE SQL
    AS
$$
DECLARE
    v_summary VARCHAR;
    v_count INT;
    v_avg_rating FLOAT;
    v_top_issue VARCHAR;
BEGIN
    SELECT COUNT(*), AVG(RATING)
    INTO :v_count, :v_avg_rating
    FROM SILVER.REVIEWS_ENRICHED;

    SELECT SNOWFLAKE.CORTEX.COMPLETE(
        'llama3.1-8b',
        'Summarize these customer complaints in 3 bullet points. Be specific and actionable.\n\n' ||
        (SELECT LISTAGG(LEFT(REVIEW_TEXT, 150), ' | ')
         FROM (SELECT REVIEW_TEXT FROM SILVER.REVIEWS_ENRICHED WHERE RATING <= 2 LIMIT 20))
    ) INTO :v_summary;

    SELECT TOPIC INTO :v_top_issue
    FROM SILVER.REVIEWS_ENRICHED
    WHERE RATING <= 2
    GROUP BY TOPIC
    ORDER BY COUNT(*) DESC
    LIMIT 1;

    INSERT INTO REPORTING.DAILY_SUMMARIES (SUMMARY_TEXT, NB_REVIEWS_ANALYZED, AVG_RATING, TOP_ISSUE)
    VALUES (:v_summary, :v_count, :v_avg_rating, :v_top_issue);

    RETURN 'Summary generated: ' || :v_count || ' reviews analyzed';
END;
$$;

-- Tester
CALL REPORTING.GENERATE_DAILY_SUMMARY();
SELECT * FROM REPORTING.DAILY_SUMMARIES;

-- ─────────────────────────────────────────────────────────────────────────────
-- 3. Task planifiée : tous les jours à 8h
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE TASK REPORTING.TASK_DAILY_SUMMARY
    WAREHOUSE = LAB_WH
    SCHEDULE = 'USING CRON 0 8 * * * Europe/Paris'
    AS
    CALL REPORTING.GENERATE_DAILY_SUMMARY();

ALTER TASK REPORTING.TASK_DAILY_SUMMARY RESUME;

SHOW TASKS IN SCHEMA REPORTING;

-- ─────────────────────────────────────────────────────────────────────────────
-- 💡 En production réelle :
-- • La Task peut envoyer un email/Slack via notification integration
-- • On peut chaîner plusieurs Tasks (ex: résumé → alerte si PCT_NEGATIF > 30%)
-- • Le tout sans serveur, sans Lambda, sans infrastructure
-- ─────────────────────────────────────────────────────────────────────────────
