-- ============================================================================
-- MODULE 1 : PIPELINE — Bronze → Silver → Gold (Dynamic Tables)
-- Durée : 25 min
-- Architecture Medallion automatisée via Dynamic Tables
--
--  BRONZE (brut)        SILVER (enrichi)              GOLD (business)
-- ┌────────────┐     ┌──────────────────┐     ┌─────────────────────┐
-- │ REVIEWS    │────▶│ REVIEWS_CLEANED  │────▶│ CONTROL_TOWER       │
-- │ TRENDS     │     │ REVIEWS_ENRICHED │     │ (KPIs par produit)  │
-- │ CATEGORIES │────▶│ REVIEWS_FULL     │────▶│                     │
-- └────────────┘     └──────────────────┘     └─────────────────────┘
--
-- ============================================================================

USE DATABASE LAB_RETAIL_AI;
USE WAREHOUSE LAB_WH;

-- ═══════════════════════════════════════════════════════════════════════════════
-- SILVER : Données nettoyées + enrichies par l'IA
-- ═══════════════════════════════════════════════════════════════════════════════

-- ─── SILVER 1 : Nettoyage et typage ───
CREATE OR REPLACE DYNAMIC TABLE SILVER.REVIEWS_CLEANED
    TARGET_LAG = '1 minute'
    WAREHOUSE = LAB_WH
    AS
    SELECT
        REVIEW_ID,
        TRIM(REVIEW_TEXT) AS REVIEW_TEXT,
        RATING,
        VERIFIED_PURCHASE,
        LENGTH(REVIEW_TEXT) AS TEXT_LENGTH,
        CASE
            WHEN RATING >= 4 THEN 'positif'
            WHEN RATING = 3 THEN 'neutre'
            ELSE 'negatif'
        END AS SENTIMENT_LABEL
    FROM BRONZE.REVIEWS
    WHERE REVIEW_TEXT IS NOT NULL
      AND LENGTH(TRIM(REVIEW_TEXT)) > 20;

-- ─── SILVER 2 : Enrichissement IA (sentiment + classification + fraude) ───
CREATE OR REPLACE DYNAMIC TABLE SILVER.REVIEWS_ENRICHED
    TARGET_LAG = '1 minute'
    WAREHOUSE = LAB_WH
    AS
    SELECT
        REVIEW_ID,
        REVIEW_TEXT,
        RATING,
        VERIFIED_PURCHASE,
        SENTIMENT_LABEL,
        TEXT_LENGTH,

        -- Sentiment IA (score numérique -1 à 1)
        SNOWFLAKE.CORTEX.SENTIMENT(REVIEW_TEXT) AS SENTIMENT_SCORE,

        -- Classification IA du sujet
        TRIM(SNOWFLAKE.CORTEX.COMPLETE(
            'llama3.1-8b',
            'Classify this product review into ONE category: Product Quality, Delivery/Shipping, Price/Value, Customer Service, Packaging, Ease of Use, Durability, Other. Reply only the category.\n\nReview: ' || LEFT(REVIEW_TEXT, 500)
        )) AS TOPIC,

        -- Détection faux avis
        CASE
            WHEN RATING = 5 AND TEXT_LENGTH < 80 AND VERIFIED_PURCHASE = FALSE THEN TRUE
            ELSE FALSE
        END AS IS_SUSPICIOUS

    FROM SILVER.REVIEWS_CLEANED
    LIMIT 500;  -- Budget lab : 500 avis enrichis par l'IA

-- ─── SILVER 3 : Jointure avec catégories produits + Google Trends ───
CREATE OR REPLACE DYNAMIC TABLE SILVER.REVIEWS_FULL
    TARGET_LAG = '1 minute'
    WAREHOUSE = LAB_WH
    AS
    SELECT
        r.*,
        p.CATEGORY AS PRODUCT_CATEGORY,
        p.SUBCATEGORY AS PRODUCT_TYPE,
        p.PRICE_RANGE,
        g.CURRENT_INTEREST AS GOOGLE_POPULARITY,
        g.TREND_DIRECTION AS GOOGLE_TREND
    FROM SILVER.REVIEWS_ENRICHED r
    LEFT JOIN BRONZE.PRODUCT_CATEGORIES p
        ON CONTAINS(LOWER(r.REVIEW_TEXT), LOWER(p.PRODUCT_KEYWORD))
    LEFT JOIN BRONZE.GOOGLE_TRENDS g
        ON g.KEYWORD = p.GOOGLE_TREND_KEYWORD;

-- ═══════════════════════════════════════════════════════════════════════════════
-- GOLD : Agrégations business-ready
-- ═══════════════════════════════════════════════════════════════════════════════

-- ─── GOLD 1 : Control Tower — KPIs par produit ───
CREATE OR REPLACE DYNAMIC TABLE GOLD.CONTROL_TOWER
    TARGET_LAG = '1 minute'
    WAREHOUSE = LAB_WH
    AS
    SELECT
        COALESCE(PRODUCT_TYPE, 'Non identifié') AS PRODUIT,
        COALESCE(PRODUCT_CATEGORY, 'Autre') AS CATEGORIE,
        COALESCE(GOOGLE_POPULARITY, 0) AS POPULARITE_WEB,
        COALESCE(GOOGLE_TREND, '-') AS TENDANCE,
        COUNT(*) AS NB_AVIS,
        ROUND(AVG(RATING), 2) AS NOTE_MOYENNE,
        ROUND(AVG(SENTIMENT_SCORE), 3) AS SENTIMENT_MOYEN,
        SUM(CASE WHEN RATING <= 2 THEN 1 ELSE 0 END) AS NB_NEGATIFS,
        SUM(CASE WHEN IS_SUSPICIOUS THEN 1 ELSE 0 END) AS NB_SUSPECTS,
        ROUND(SUM(CASE WHEN RATING <= 2 THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 1) AS PCT_INSATISFACTION
    FROM SILVER.REVIEWS_FULL
    GROUP BY PRODUIT, CATEGORIE, POPULARITE_WEB, TENDANCE;

-- ─── GOLD 2 : Stats par topic IA ───
CREATE OR REPLACE DYNAMIC TABLE GOLD.TOPIC_STATS
    TARGET_LAG = '1 minute'
    WAREHOUSE = LAB_WH
    AS
    SELECT
        TOPIC,
        COUNT(*) AS NB_AVIS,
        ROUND(AVG(RATING), 2) AS NOTE_MOYENNE,
        ROUND(AVG(SENTIMENT_SCORE), 3) AS SENTIMENT_MOYEN,
        SUM(CASE WHEN RATING <= 2 THEN 1 ELSE 0 END) AS NB_NEGATIFS,
        ROUND(SUM(CASE WHEN RATING <= 2 THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 1) AS PCT_NEGATIF
    FROM SILVER.REVIEWS_ENRICHED
    GROUP BY TOPIC;

-- ═══════════════════════════════════════════════════════════════════════════════
-- VÉRIFICATIONS
-- ═══════════════════════════════════════════════════════════════════════════════

-- Pipeline status
SELECT 'SILVER.REVIEWS_CLEANED' AS LAYER, COUNT(*) AS nb_ROWS FROM SILVER.REVIEWS_CLEANED
UNION ALL SELECT 'SILVER.REVIEWS_ENRICHED', COUNT(*) FROM SILVER.REVIEWS_ENRICHED
UNION ALL SELECT 'SILVER.REVIEWS_FULL', COUNT(*) FROM SILVER.REVIEWS_FULL
UNION ALL SELECT 'GOLD.CONTROL_TOWER', COUNT(*) FROM GOLD.CONTROL_TOWER
UNION ALL SELECT 'GOLD.TOPIC_STATS', COUNT(*) FROM GOLD.TOPIC_STATS;

-- Gold : Control Tower
SELECT * FROM GOLD.CONTROL_TOWER ORDER BY NB_AVIS DESC;

-- Gold : Topics
SELECT * FROM GOLD.TOPIC_STATS ORDER BY PCT_NEGATIF DESC;

-- Insight : Popularité Google vs Satisfaction
SELECT PRODUIT, POPULARITE_WEB, NOTE_MOYENNE, PCT_INSATISFACTION
FROM GOLD.CONTROL_TOWER
WHERE POPULARITE_WEB > 0
ORDER BY POPULARITE_WEB DESC;

-- ═══════════════════════════════════════════════════════════════════════════════
-- DÉMO LIVE : Nouvel avis → cascade automatique Bronze → Silver → Gold
-- ═══════════════════════════════════════════════════════════════════════════════

INSERT INTO BRONZE.REVIEWS VALUES (
    'DEMO_001',
    'Absolutely terrible AirPods clone. Battery dies after 30 minutes, the charging case broke on day 2, and customer service ghosted me. Complete waste of 45 dollars.',
    1,
    TRUE
);

-- Attendre ~1 minute puis :
-- SELECT * FROM SILVER.REVIEWS_FULL WHERE REVIEW_ID = 'DEMO_001';
-- → Le pipeline a automatiquement : nettoyé, analysé le sentiment, classifié le topic,
--   matché avec la catégorie "Wireless Earbuds", récupéré la popularité Google (49/100)
