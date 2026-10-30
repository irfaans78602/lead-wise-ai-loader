"""
tools/generate_demo_data.py

Generates 2,000 customers and 3,000 conversations (75% completed, 25% abandoned)
for the LeadWise AI demo dashboard.

Distribution:
  - 75% of conversations are attached to the ENGLISH LEAF ad.
  - 25% split uniformly across the other leaf ads (ar, es, fr, zh).
  - The Root ad (Canonical) is NEVER used for customers.

Content distribution:
  - Every customer.ad_id points at a leaf.
  - Every answers.faq_id and qualifications.qualification_id point at the
    ROOT, because forbid_content_on_leaf_ad() prevents leaves from owning
    their own faqs / qualification_score rows.

Usage:
  python tools/generate_demo_data.py --start-date YYYY-MM-DD --end-date YYYY-MM-DD
"""

import os
import random
import argparse
from datetime import datetime, timezone, timedelta
import psycopg2
from psycopg2.extras import execute_values, RealDictCursor
from dotenv import load_dotenv


def parse_args():
    parser = argparse.ArgumentParser(description="Generate demo data for LeadWise AI.")
    parser.add_argument(
        "--start-date", 
        required=True,
        help="Start date (YYYY-MM-DD)."
    )
    parser.add_argument(
        "--end-date", 
        required=True,
        help="End date (YYYY-MM-DD)."
    )
    return parser.parse_args()


def random_date(start_dt, end_dt):
    delta = end_dt - start_dt
    return start_dt + timedelta(
        seconds=random.randint(0, int(delta.total_seconds()))
    )


def generate_data():
    args = parse_args()

    # 1. Setup
    print("Loading environment variables...")
    load_dotenv(".env.website_demo")
    DATABASE_URL = os.getenv("WEBSITE_DEMO_DATABASE_URL")
    if not DATABASE_URL:
        raise ValueError("WEBSITE_DEMO_DATABASE_URL not found in .env.website_demo")

    safe_url = (
        DATABASE_URL.split('@')[0].split(':')[0] + ':***@' + DATABASE_URL.split('@')[1]
        if '@' in DATABASE_URL else "local"
    )
    print(f"  Target Database: {safe_url}")

    random.seed(42)

    # 2. Parse Dates
    try:
        start_dt = datetime.strptime(args.start_date, "%Y-%m-%d").replace(tzinfo=timezone.utc)
        end_dt = datetime.strptime(args.end_date, "%Y-%m-%d").replace(
            hour=23, minute=59, second=59, tzinfo=timezone.utc
        )
    except ValueError as e:
        raise ValueError(f"Invalid date format. Use YYYY-MM-DD. Error: {e}")

    print(f"  Date Range:      {start_dt.strftime('%Y-%m-%d')} to {end_dt.strftime('%Y-%m-%d')}")
    print(f"  Random Seed:     42")

    print("\nConnecting to database...")
    
    # Use RealDictCursor so rows are returned as dictionaries
    conn = psycopg2.connect(DATABASE_URL, cursor_factory=RealDictCursor)
    conn.autocommit = False
    cur = conn.cursor()

    try:
        # ------------------------------------------------------------------
        # 3. Fetch every ad for the target client, with its language code
        # ------------------------------------------------------------------
        print("Fetching ads for the target client...")
        TARGET_CLIENT_ID = '35d69a44-9649-5556-81a0-251ab6dc537b'

        cur.execute("""
            SELECT a.ad_id, a.ad_name, a.reuse_ad_id, l.code AS language_code
            FROM ads a
            LEFT JOIN languages l ON l.language_id = a.language_id
            WHERE a.client_id = %s
            ORDER BY a.ad_name
        """, (TARGET_CLIENT_ID,))
        all_ads = cur.fetchall()

        if not all_ads:
            raise ValueError(
                f"No ads found for client {TARGET_CLIENT_ID}. "
                f"Please load the client JSON first."
            )

        root_ads = [a for a in all_ads if a['reuse_ad_id'] is None]
        leaves   = [a for a in all_ads if a['reuse_ad_id'] is not None]

        if not root_ads:
            raise ValueError(
                f"No root ad found for client {TARGET_CLIENT_ID}. "
                f"Every ad has reuse_ad_id set — check the client JSON."
            )

        root_ad = root_ads[0]
        if len(root_ads) > 1:
            print(f"  WARN: {len(root_ads)} root ads found; using the first: "
                  f"{root_ad['ad_name']} ({root_ad['ad_id']})")

        print(f"  Root ad:  {root_ad['ad_name']} ({root_ad['ad_id']}) "
              f"[lang={root_ad['language_code'] or 'unset'}]")
        print(f"  Leaves:   {len(leaves)}")
        for leaf in leaves:
            print(f"    {leaf['ad_name']:<40} "
                  f"[lang={leaf['language_code'] or 'unset'}]  "
                  f"({leaf['ad_id']})")

        # Index leaves by language code
        leaves_by_lang = {}
        for leaf in leaves:
            lang = leaf['language_code']
            if lang and lang not in leaves_by_lang:
                leaves_by_lang[lang] = leaf

        en_leaf = leaves_by_lang.get('en')
        if not en_leaf:
            print("  WARN: no 'en' leaf ad found. The 75% English share "
                  "will fall back to the root (Canonical).")
            en_leaf = root_ad
        else:
            print(f"  English leaf: {en_leaf['ad_name']} ({en_leaf['ad_id']})")

        other_leaf_langs = sorted(lang for lang in leaves_by_lang if lang != 'en')
        if not other_leaf_langs:
            print("  WARN: no non-English leaf ads found. All 3000 "
                  "conversations will go to the English leaf.")
        else:
            print(f"  Non-English leaves available: {', '.join(other_leaf_langs)}")

        # ------------------------------------------------------------------
        # 4. FAQs and qualification scores ALWAYS come from the ROOT
        # ------------------------------------------------------------------
        cur.execute("""
            SELECT faq_id, question_order
            FROM faqs
            WHERE ad_id = %s
            ORDER BY question_order
        """, (root_ad['ad_id'],))
        faqs = cur.fetchall()
        print(f"\n  Root FAQs:              {len(faqs)}")

        cur.execute("""
            SELECT qualification_score_id, level_code
            FROM qualification_score
            WHERE ad_id = %s
        """, (root_ad['ad_id'],))
        q_scores = cur.fetchall()
        print(f"  Root qualification bands: {len(q_scores)}")

        if not faqs or not q_scores:
            raise ValueError(
                "Missing FAQs or Qualification Scores on the root ad. "
                "Load the client JSON and the base seed first."
            )

        # ------------------------------------------------------------------
        # 5. Build the 3,000-slot target list
        # ------------------------------------------------------------------
        target_ads = []
        for _ in range(3000):
            if random.random() < 0.75:
                target_ads.append(en_leaf)
            else:
                if other_leaf_langs:
                    lang = random.choice(other_leaf_langs)
                    target_ads.append(leaves_by_lang[lang])
                else:
                    target_ads.append(en_leaf)

        # Distribution summary
        ad_distribution = {}
        for ad in target_ads:
            ad_distribution[ad['ad_id']] = ad_distribution.get(ad['ad_id'], 0) + 1

        print("\n  Planned conversation distribution:")
        for ad in all_ads:
            n = ad_distribution.get(ad['ad_id'], 0)
            if n:
                lang = ad['language_code'] or 'unset'
                print(f"    {ad['ad_name']:<40} [{lang:<5}]  {n:>4}")

        # Shuffle completed/abandoned (75% / 25%)
        conversation_types = ['abandoned'] * 750 + ['completed'] * 2250
        random.shuffle(conversation_types)

        # ------------------------------------------------------------------
        # 6. Generate rows
        # ------------------------------------------------------------------
        print("\nGenerating data (this may take a few seconds)...")

        customers_data = []
        conversations_data = []
        answers_data = []
        qualifications_data = []
        statuses_data = []

        for i in range(3000):
            if i > 0 and i % 1000 == 0:
                print(f"  ... generated {i} / 3000 conversations")

            target_ad = target_ads[i]
            target_ad_id = target_ad['ad_id']

            customer_id = i + 1 if i < 2000 else random.randint(1, 2000)

            if i < 2000:
                created_at = random_date(start_dt, end_dt)
                status = random.choices(
                    ['Pending', 'Contacted', 'Qualified', 'Converted', 'Withdrawn'],
                    weights=[10, 30, 40, 15, 5], k=1
                )[0]
                score = random.randint(10, 100)
                # FIXED: Access by string key, not index
                q_id = random.choice(q_scores)['qualification_score_id']

                customers_data.append((
                    customer_id, target_ad_id, None, 'chat',
                    f"user_{customer_id}", status, score, q_id, created_at
                ))

                note = random.choice([
                    "Customer requested pricing information.",
                    "Budget confirmation outstanding.",
                    "Decision-maker details provided.",
                    "Follow-up required regarding implementation timeline."
                ])
                statuses_data.append((customer_id, status, note, created_at))

            conv_type = conversation_types[i]
            conv_created_at = random_date(start_dt, end_dt)
            if i < 2000:
                conv_created_at = created_at + timedelta(minutes=random.randint(1, 60))

            if conv_type == 'completed':
                state = 'completed'
                current_order = len(faqs)
                completed_at = conv_created_at + timedelta(minutes=random.randint(2, 15))
            else:
                state = 'abandoned'
                current_order = random.randint(1, len(faqs) - 1)
                completed_at = None

            conversations_data.append((
                i + 1, customer_id, current_order, state, completed_at, conv_created_at
            ))

            # Answers always reference the ROOT's faq_ids
            for faq in faqs:
                faq_id = faq['faq_id']
                q_order = faq['question_order']
                if q_order <= current_order:
                    answers_data.append((
                        i + 1, faq_id, f"Sample answer for Q{q_order}", None,
                        conv_created_at + timedelta(seconds=q_order * 10)
                    ))

            # Qualifications always reference the ROOT ad_id + root qscores
            if conv_type == 'completed':
                # FIXED: Access by string key, not index
                q_score_id = random.choice(q_scores)['qualification_score_id']
                qualifications_data.append((
                    i + 1, customer_id, root_ad['ad_id'],
                    random.randint(10, 100),
                    q_score_id,
                    completed_at, completed_at
                ))

        print("\nGeneration complete:")
        print(f"  Customers:       {len(customers_data)}")
        print(f"  Conversations:   {len(conversations_data)} (750 abandoned, 2250 completed)")
        print(f"  Answers:         {len(answers_data)}")
        print(f"  Qualifications:  {len(qualifications_data)}")
        print(f"  Statuses:        {len(statuses_data)}")

        # ------------------------------------------------------------------
        # 7. Insert
        # ------------------------------------------------------------------
        print("\nInserting data...")

        print("  Inserting Customers...")
        execute_values(cur, """
            INSERT INTO customers (
                customer_id, ad_id, demo_session_id, channel, channel_user_id,
                status, qualification_score, qualification_id, created_at
            )
            OVERRIDING SYSTEM VALUE
            VALUES %s ON CONFLICT DO NOTHING
        """, customers_data)

        print("  Inserting Conversations...")
        execute_values(cur, """
            INSERT INTO conversations (
                conversation_id, customer_id, current_order, state,
                completed_at, created_at
            )
            OVERRIDING SYSTEM VALUE
            VALUES %s ON CONFLICT DO NOTHING
        """, conversations_data)

        print("  Inserting Answers...")
        execute_values(cur, """
            INSERT INTO answers (
                conversation_id, faq_id, answer_text, answer_values, created_at
            )
            VALUES %s ON CONFLICT DO NOTHING
        """, answers_data)

        print("  Inserting Qualifications...")
        execute_values(cur, """
            INSERT INTO qualifications (
                conversation_id, customer_id, ad_id, qualification_score,
                qualification_id, qualified_at, created_at
            )
            VALUES %s ON CONFLICT DO NOTHING
        """, qualifications_data)

        print("  Inserting Statuses...")
        execute_values(cur, """
            INSERT INTO customer_statuses (
                customer_id, status, note, changed_at
            )
            VALUES %s ON CONFLICT DO NOTHING
        """, statuses_data)

        # ------------------------------------------------------------------
        # 8. Reset sequences
        # ------------------------------------------------------------------
        print("\nResetting sequences...")

        cur.execute("SELECT setval(pg_get_serial_sequence('customers', 'customer_id'), coalesce(max(customer_id), 1)) FROM customers;")
        print("  -> Customers sequence reset.")

        cur.execute("SELECT setval(pg_get_serial_sequence('conversations', 'conversation_id'), coalesce(max(conversation_id), 1)) FROM conversations;")
        print("  -> Conversations sequence reset.")

        cur.execute("SELECT setval(pg_get_serial_sequence('answers', 'answer_id'), coalesce(max(answer_id), 1)) FROM answers;")
        print("  -> Answers sequence reset.")

        cur.execute("SELECT setval(pg_get_serial_sequence('qualifications', 'qualification_event_id'), coalesce(max(qualification_event_id), 1)) FROM qualifications;")
        print("  -> Qualifications sequence reset.")

        cur.execute("SELECT setval(pg_get_serial_sequence('customer_statuses', 'customer_status_id'), coalesce(max(customer_status_id), 1)) FROM customer_statuses;")
        print("  -> Customer Statuses sequence reset.")

        conn.commit()
        print("\n✅ Successfully generated and inserted demo data!")

    except Exception as e:
        conn.rollback()
        print(f"\n❌ Error: {e}")
        print("Transaction rolled back. No data was inserted.")
    finally:
        cur.close()
        conn.close()


if __name__ == "__main__":
    generate_data()