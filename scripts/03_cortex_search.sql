-- ============================================================================
-- MODULE 3 : CORTEX SEARCH — "Trouve-moi les avis qui parlent de..."
-- Durée : 15 min
-- Objectif : Recherche sémantique sur les avis clients
-- ============================================================================

USE DATABASE LAB_RETAIL_AI;
USE WAREHOUSE LAB_WH;

-- ─────────────────────────────────────────────────────────────────────────────
-- 1. Créer le Search Service sur les avis
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE CORTEX SEARCH SERVICE SILVER.SEARCH_REVIEWS
    ON REVIEW_TEXT
    ATTRIBUTES RATING, SENTIMENT_LABEL, TOPIC
    WAREHOUSE = LAB_WH
    TARGET_LAG = '1 hour'
    AS (
        SELECT
            REVIEW_TEXT,
            RATING::VARCHAR AS RATING,
            SENTIMENT_LABEL,
            TOPIC
        FROM SILVER.REVIEWS_ENRICHED
    );

-- ─────────────────────────────────────────────────────────────────────────────
-- 2. Recherches en langage naturel
-- ─────────────────────────────────────────────────────────────────────────────

-- "Problèmes de batterie qui ne tient pas"
SELECT PARSE_JSON(SNOWFLAKE.CORTEX.SEARCH_PREVIEW(
    'LAB_RETAIL_AI.SILVER.SEARCH_REVIEWS',
    '{"query": "battery dies quickly does not hold charge", "columns": ["REVIEW_TEXT", "RATING", "TOPIC"], "limit": 5}'
))['results'] AS RESULTATS;

-- "Produit arrivé cassé ou endommagé"
SELECT PARSE_JSON(SNOWFLAKE.CORTEX.SEARCH_PREVIEW(
    'LAB_RETAIL_AI.SILVER.SEARCH_REVIEWS',
    '{"query": "arrived broken damaged in shipping", "columns": ["REVIEW_TEXT", "RATING", "TOPIC"], "limit": 5}'
))['results'] AS RESULTATS;

-- "Clients satisfaits qui recommandent le produit"
SELECT PARSE_JSON(SNOWFLAKE.CORTEX.SEARCH_PREVIEW(
    'LAB_RETAIL_AI.SILVER.SEARCH_REVIEWS',
    '{"query": "excellent product highly recommend great value for money", "columns": ["REVIEW_TEXT", "RATING", "TOPIC"], "limit": 5}'
))['results'] AS RESULTATS;

-- "Problème de taille ou de compatibilité"
SELECT PARSE_JSON(SNOWFLAKE.CORTEX.SEARCH_PREVIEW(
    'LAB_RETAIL_AI.SILVER.SEARCH_REVIEWS',
    '{"query": "wrong size does not fit not compatible with my device", "columns": ["REVIEW_TEXT", "RATING", "TOPIC"], "limit": 5}'
))['results'] AS RESULTATS;

-- ─────────────────────────────────────────────────────────────────────────────
-- 💡 INFO :
-- ILIKE '%batterie%' ne trouverait que le mot exact "batterie".
-- Cortex Search trouve "dies quickly", "doesn't hold charge", "power issues"...
-- C'est la différence entre un CTRL+F et un moteur de recherche intelligent.
-- ─────────────────────────────────────────────────────────────────────────────

-- Preuve : ILIKE rate des résultats
SELECT COUNT(*) AS resultats_ilike
FROM SILVER.REVIEWS_ENRICHED
WHERE REVIEW_TEXT ILIKE '%battery%';
-- vs. Cortex Search qui trouve aussi "charge", "power", "dies", etc.
